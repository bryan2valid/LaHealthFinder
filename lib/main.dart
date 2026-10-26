import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'clinic_model.dart';
import 'services/care_matcher.dart';
import 'services/geo.dart';
import 'theme/app_theme.dart';
import 'widgets/clinic_card.dart';
import 'widgets/map_marker.dart';

/// Map tiles.
///
/// CARTO now requires a free API key on its raster tiles (without one the map
/// is covered in an "API KEY REQUIRED" watermark). If you have a key, run with:
///   flutter run --dart-define=CARTO_KEY=your_key_here
/// Without a key the app uses OpenStreetMap's keyless tiles instead.
const String _cartoKey = String.fromEnvironment('CARTO_KEY');
const bool _useCarto = _cartoKey != '';
const String _tileUrl = _useCarto
    ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png?key=$_cartoKey'
    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const String _tileCredit = _useCarto ? 'CARTO / OpenStreetMap contributors' : 'OpenStreetMap contributors';

/// Quick-pick cities for when GPS is unavailable (or the user declines it).
const Map<String, LatLng> _quickCities = {
  'Hammond': LatLng(30.5044, -90.4612),
  'Baton Rouge': LatLng(30.4515, -91.1871),
  'New Orleans': LatLng(29.9511, -90.0715),
  'Houma': LatLng(29.5958, -90.7195),
  'Lafayette': LatLng(30.2241, -92.0198),
  'Lake Charles': LatLng(30.2266, -93.2174),
  'Alexandria': LatLng(31.3113, -92.4451),
  'Monroe': LatLng(32.5093, -92.1193),
  'Shreveport': LatLng(32.5252, -93.7502),
};

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LA Clinic Finder',
      theme: AppTheme.dark,
      home: const ClinicFinderScreen(),
    );
  }
}

class ClinicFinderScreen extends StatefulWidget {
  const ClinicFinderScreen({super.key});

  @override
  State<ClinicFinderScreen> createState() => _ClinicFinderScreenState();
}

class _ClinicFinderScreenState extends State<ClinicFinderScreen> {
  // ---- data ----
  List<Clinic> allClinics = [];
  Map<String, dynamic> zipMap = {};
  int locatedCount = 0; // clinics whose ZIP we could turn into coordinates
  List<NearbyClinic> displayed = []; // what the list and map are showing

  // ---- controls ----
  final TextEditingController searchController = TextEditingController();
  final MapController mapController = MapController();
  bool mapReady = false;
  bool isMapView = false;
  bool filterOnlyER = false;
  bool filterMentalHealth = false;
  bool filterVeterans = false;
  bool includeLabs = false; // ~87% of the dataset is lab listings; hidden by default
  bool isLoading = true;

  // ---- location ----
  Position? userPosition; // from GPS
  LatLng? zipCenter; // set when the user types a 5-digit ZIP instead
  LatLng? pickedCenter; // set when the user taps a quick-pick city
  String? pickedLabel;

  // ZIPs that aren't in zip_codes.json are looked up online, once, and cached.
  final Map<String, dynamic> _onlineZips = {};
  final Set<String> _zipPending = {};
  final Set<String> _zipFailed = {};
  bool isFetchingLocation = false;
  String? locationStatusMessage;
  double radiusMiles = 10.0; // what the user asked for
  double radiusUsed = 10.0; // what we actually used (may have widened)

  // ---- search state ----
  CareNeed? activeNeed; // e.g. "X-ray & imaging" when the search matches one
  String? resultNote;

  // Only used when there is no location at all but the user is searching.
  static const int _maxWithoutLocation = 30;

  /// Where "nearby" is measured from: a typed ZIP wins, then a picked city,
  /// then GPS.
  LatLng? get searchCenter {
    if (zipCenter != null) return zipCenter;
    if (pickedCenter != null) return pickedCenter;
    final p = userPosition;
    return p == null ? null : LatLng(p.latitude, p.longitude);
  }

  @override
  void initState() {
    super.initState();
    loadClinicData();
    _getUserLocation();
  }

  @override
  void dispose() {
    searchController.dispose();
    mapController.dispose();
    super.dispose();
  }

  Future<void> _getUserLocation() async {
    setState(() {
      isFetchingLocation = true;
      locationStatusMessage = null;
    });

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() {
          isFetchingLocation = false;
          locationStatusMessage =
              'Turn on location services, or type your ZIP code above.';
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          isFetchingLocation = false;
          locationStatusMessage =
              'Location permission denied. Type your ZIP code above to search near you.';
        });
        return;
      }

      // timeLimit stops the app from waiting forever when the browser or
      // device can't produce a fix (common on desktop Chrome without GPS).
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 15),
        ),
      );

      setState(() {
        userPosition = position;
        pickedCenter = null; // real GPS beats a picked city
        pickedLabel = null;
        isFetchingLocation = false;
        locationStatusMessage = null;
      });
      applyFilters();
    } catch (e) {
      setState(() {
        isFetchingLocation = false;
        locationStatusMessage = kIsWeb
            ? 'Your browser could not find your location. Check the lock icon in the address bar, or type your ZIP code above.'
            : 'Could not get your location. Type your ZIP code above instead.';
      });
      debugPrint('Location error: $e');
    }
  }

  Future<void> loadClinicData() async {
    try {
      final zipText = await rootBundle.loadString('assets/data/zip_codes.json');
      zipMap = json.decode(zipText) as Map<String, dynamic>;

      final clinicText = await rootBundle.loadString('assets/data/clinics.json');
      final List<dynamic> jsonList = json.decode(clinicText);

      final clinics = jsonList.map((raw) {
        final item = raw as Map<String, dynamic>;
        final cleanZip = (item['ZIP']?.toString() ?? '').trim().split('-').first;

        // Attach coordinates only when the ZIP is known. Clinics without a
        // match stay "unlocated" and are left out of distance searches.
        final zip = zipMap[cleanZip];
        if (zip != null) {
          item['LATITUDE'] = zip['latitude'];
          item['LONGITUDE'] = zip['longitude'];
        }
        return Clinic.fromJson(item);
      }).toList();

      if (!mounted) return;
      setState(() {
        allClinics = clinics;
        locatedCount = clinics.where((c) => c.hasRealLocation).length;
        isLoading = false;
      });
      // Whichever finishes last (clinic data or GPS) triggers the real result.
      applyFilters();
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
      debugPrint('Error loading clinic data: $e');
    }
  }

  /// The heart of the app. Runs whenever the search text, a filter, the
  /// radius, or the user's location changes:
  ///   1. Work out what the search means (a ZIP code? a kind of care? a name?)
  ///   2. Filter the clinics down to the ones that qualify.
  ///   3. Keep only the ones near the user, nearest first.
  void applyFilters() {
    final query = searchController.text.trim();
    final lowerQuery = query.toLowerCase();

    // 1) What does the search box mean?
    LatLng? manualCenter;
    final isZipQuery = RegExp(r'^\d{5}$').hasMatch(query);
    final zip = isZipQuery ? (zipMap[query] ?? _onlineZips[query]) : null;
    final unknownZip = isZipQuery && zip == null;
    if (unknownZip) _lookupZipOnline(query);
    final zipLookupPending = unknownZip && _zipPending.contains(query);
    if (zip != null) {
      manualCenter = LatLng((zip['latitude'] as num).toDouble(), (zip['longitude'] as num).toDouble());
    }
    final need = manualCenter == null ? CareMatcher.match(query) : null;
    final isNameSearch = manualCenter == null && need == null && query.isNotEmpty && !isZipQuery;

    // 2) Which clinics qualify?
    bool qualifies(Clinic c) {
      if (filterOnlyER && !c.hasER) return false;
      if (filterMentalHealth && !c.offersMentalHealth) return false;
      if (filterVeterans && !c.servesVeterans) return false;
      if (need != null) return need.accepts(c);
      if (isNameSearch) {
        return '${c.name} ${c.parish} ${c.city}'.toLowerCase().contains(lowerQuery);
      }
      return includeLabs || c.type != FacilityType.lab;
    }

    final candidates = allClinics.where(qualifies).toList();
    final unlocated = candidates.where((c) => !c.hasRealLocation).length;
    final center = manualCenter ?? pickedCenter ?? _gpsCenter();

    // 3a) No idea where the user is: don't dump the whole state on them.
    if (center == null) {
      var list = <NearbyClinic>[];
      if (need != null || isNameSearch) {
        candidates.sort((a, b) => a.name.compareTo(b.name));
        list = candidates.take(_maxWithoutLocation).map((c) => NearbyClinic(c, null)).toList();
      }
      setState(() {
        zipCenter = null;
        activeNeed = need;
        displayed = list;
        radiusUsed = radiusMiles;
        resultNote = unknownZip ? _unknownZipNote(query, zipLookupPending, hasCenter: false) : null;
      });
      return;
    }

    // 3b) Nearby search.
    final result = findNearby(
      candidates: candidates,
      lat: center.latitude,
      lng: center.longitude,
      radiusMiles: radiusMiles,
    );

    String? note;
    if (result.items.isEmpty) {
      note = 'No matches within ${result.radiusUsed.round()} mi of this location.';
    } else if (result.widened) {
      note = 'Fewer than 5 within ${radiusMiles.round()} mi, so we widened to ${result.radiusUsed.round()} mi.';
    }
    if (unknownZip) {
      final msg = _unknownZipNote(query, zipLookupPending, hasCenter: true);
      note = note == null ? msg : '$note $msg';
    }
    if (unlocated > 0 && (need != null || isNameSearch)) {
      final extra = '$unlocated matching facilities are hidden because their ZIP has no coordinates yet.';
      note = note == null ? extra : '$note $extra';
    }

    setState(() {
      zipCenter = manualCenter;
      activeNeed = need;
      displayed = result.items;
      radiusUsed = result.radiusUsed;
      resultNote = note;
    });
    _moveMap(center, result.radiusUsed);
  }

  String _unknownZipNote(String zip, bool pending, {required bool hasCenter}) {
    if (pending) return 'Looking up ZIP $zip…';
    return hasCenter
        ? "Couldn't find ZIP $zip, so these results are near your current location instead."
        : "Couldn't find ZIP $zip. Check the number, or pick a city below.";
  }

  /// Fallback for ZIPs missing from zip_codes.json: ask a free ZIP lookup
  /// service once, cache the answer, and re-run the search.
  Future<void> _lookupZipOnline(String zip) async {
    if (_zipPending.contains(zip) || _zipFailed.contains(zip)) return;
    _zipPending.add(zip);
    try {
      final res = await http
          .get(Uri.parse('https://api.zippopotam.us/us/$zip'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final place = (json.decode(res.body)['places'] as List).first;
        _onlineZips[zip] = {
          'latitude': double.parse(place['latitude'].toString()),
          'longitude': double.parse(place['longitude'].toString()),
        };
      } else {
        _zipFailed.add(zip);
      }
    } catch (e) {
      _zipFailed.add(zip);
      debugPrint('ZIP lookup failed for $zip: $e');
    } finally {
      _zipPending.remove(zip);
    }
    // Only refresh if the user is still looking at this ZIP.
    if (mounted && searchController.text.trim() == zip) applyFilters();
  }

  void _pickCity(String name) {
    setState(() {
      if (pickedLabel == name) {
        pickedCenter = null; // tapping the selected city again clears it
        pickedLabel = null;
      } else {
        pickedCenter = _quickCities[name];
        pickedLabel = name;
      }
    });
    applyFilters();
  }

  LatLng? _gpsCenter() {
    final p = userPosition;
    return p == null ? null : LatLng(p.latitude, p.longitude);
  }

  void _moveMap(LatLng center, double miles) {
    if (!mapReady) return;
    mapController.move(center, _zoomForRadius(miles));
  }

  double _zoomForRadius(double miles) {
    if (miles <= 5) return 10.9;
    if (miles <= 10) return 9.8;
    if (miles <= 25) return 8.5;
    if (miles <= 50) return 7.5;
    return 6.5;
  }

  /// Directions use the street address, not our ZIP-based coordinates
  /// (those are only accurate to the ZIP area, not the building).
  Future<void> openExternalMap(Clinic c) async {
    final query = Uri.encodeComponent('${c.name}, ${c.address}, ${c.city}, LA');
    final Uri googleMapsUrl =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    if (await canLaunchUrl(googleMapsUrl)) {
      await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open external mapping utility.')),
      );
    }
  }

  Future<void> _callNumber(String phone) async {
    final digitsOnly = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$digitsOnly');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openWebsite(String url) async {
    final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showRadiusPicker() {
    const options = [5.0, 10.0, 25.0, 50.0, 100.0];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Search radius',
                    style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                const Text(
                  "If fewer than 5 results fall inside this range, we automatically widen it so you still see options.",
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: options.map((mi) {
                    final selected = radiusMiles == mi;
                    return GestureDetector(
                      onTap: () {
                        setState(() => radiusMiles = mi);
                        applyFilters();
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: selected ? AppColors.accent.withValues(alpha: 0.14) : AppColors.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: selected ? AppColors.accent : AppColors.border),
                        ),
                        child: Text('${mi.round()} mi',
                            style: TextStyle(
                              color: selected ? AppColors.accent : AppColors.textSecondary,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                              fontSize: 13,
                            )),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showClinicDetail(Clinic clinic, double? distanceMiles) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(clinic.name,
                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 17)),
                const SizedBox(height: 4),
                if (clinic.address.isNotEmpty)
                  Text('${clinic.address}, ${clinic.city}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(Icons.star_rounded, size: 16,
                        color: clinic.rating != null ? AppColors.wellness : AppColors.textFaint),
                    const SizedBox(width: 6),
                    Text(
                      clinic.rating != null ? '${clinic.rating!.toStringAsFixed(1)} / 5' : 'No rating available yet',
                      style: TextStyle(
                        color: clinic.rating != null ? AppColors.textPrimary : AppColors.textFaint,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (distanceMiles != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.near_me_rounded, size: 15, color: AppColors.accent),
                      const SizedBox(width: 7),
                      Text('about ${distanceMiles.toStringAsFixed(1)} miles away',
                          style: const TextStyle(color: AppColors.accent, fontSize: 13.5, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _sheetActionButton(
                        icon: Icons.call_rounded,
                        label: 'Call',
                        onTap: clinic.phone == 'N/A' ? null : () => _callNumber(clinic.phone),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _sheetActionButton(
                        icon: Icons.public_rounded,
                        label: 'Website',
                        onTap: clinic.website == null ? null : () => _openWebsite(clinic.website!),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _sheetActionButton(
                        icon: Icons.directions_rounded,
                        label: 'Directions',
                        onTap: () => openExternalMap(clinic),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sheetActionButton({required IconData icon, required String label, required VoidCallback? onTap}) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: enabled ? AppColors.accent.withValues(alpha: 0.12) : AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: enabled ? AppColors.accent.withValues(alpha: 0.4) : AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: enabled ? AppColors.accent : AppColors.textFaint),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                  color: enabled ? AppColors.accent : AppColors.textFaint,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                )),
          ],
        ),
      ),
    );
  }

  /// One-line status under the filters: widened radius, ZIP lookups, etc.
  String? _statusText() => resultNote;

  Widget _buildStatusBanner(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  /// Shown whenever we don't have GPS or a typed ZIP, so there's always a way
  /// to see nearby facilities: enable location, or tap a city.
  Widget _buildCityPicker() {
    final message = pickedLabel != null
        ? 'Showing facilities near $pickedLabel. Pick another city or enable location.'
        : isFetchingLocation
            ? 'Finding your location…'
            : (locationStatusMessage ?? 'Share your location, type a ZIP code, or pick a city.');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_off_rounded, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(message, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ),
                if (!isFetchingLocation)
                  TextButton(
                    onPressed: _getUserLocation,
                    child: const Text('Enable',
                        style: TextStyle(color: AppColors.accent, fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final name in _quickCities.keys)
                  GestureDetector(
                    onTap: () => _pickCity(name),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: pickedLabel == name ? AppColors.accent.withValues(alpha: 0.14) : AppColors.background,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: pickedLabel == name ? AppColors.accent : AppColors.border),
                      ),
                      child: Text(name,
                          style: TextStyle(
                            color: pickedLabel == name ? AppColors.accent : AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: pickedLabel == name ? FontWeight.w700 : FontWeight.w500,
                          )),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Shown when the search text matched a kind of care ("x-ray", "broken arm"...).
  Widget _buildNeedBanner(CareNeed need) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.medical_services_rounded, size: 16, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Showing: ${need.label}',
                      style: const TextStyle(color: AppColors.accent, fontSize: 12.5, fontWeight: FontWeight.w700)),
                  Text(need.hint, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _statusText();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildSearchBar(),
            if (activeNeed != null) _buildNeedBanner(activeNeed!),
            _buildFilterRow(),
            if (!isLoading && userPosition == null && zipCenter == null) _buildCityPicker(),
            if (!isLoading && status != null) _buildStatusBanner(status),
            const SizedBox(height: 4),
            Expanded(
              child: isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2),
                    )
                  : _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  /// Map on top, list below. In "map view" the map takes the whole body.
  Widget _buildBody() {
    return Column(
      children: [
        Expanded(
          flex: isMapView ? 1 : 3,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                children: [
                  buildMapSection(),
                  Positioned(right: 8, bottom: 8, child: _mapLegend()),
                ],
              ),
            ),
          ),
        ),
        if (!isMapView) Expanded(flex: 7, child: buildListSection()),
      ],
    );
  }

  Widget _buildHeader() {
    final hasCenter = searchCenter != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isLoading ? AppColors.textFaint : AppColors.accent,
              boxShadow: isLoading
                  ? null
                  : [BoxShadow(color: AppColors.accent.withValues(alpha: 0.6), blurRadius: 8)],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LA CLINIC FINDER',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(letterSpacing: 1.2),
                ),
                // Only visible while debugging: confirms which build and map
                // tiles are running (handy when the browser serves a stale copy).
                if (kDebugMode)
                  Text(
                    'debug v4 · tiles: ${_useCarto ? "CARTO" : "OpenStreetMap"} · $locatedCount/${allClinics.length} facilities located',
                    style: const TextStyle(color: AppColors.textFaint, fontSize: 10.5),
                  ),
              ],
            ),
          ),
          if (hasCenter && !isLoading)
            Text(
              '${displayed.length} within ${radiusUsed.round()} mi',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: TextField(
        controller: searchController,
        onChanged: (_) => applyFilters(),
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
        decoration: InputDecoration(
          hintText: 'Try "x-ray", "broken arm", "cancer", or a ZIP code',
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textFaint, size: 20),
          suffixIcon: searchController.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppColors.textFaint, size: 18),
                  onPressed: () {
                    searchController.clear();
                    applyFilters();
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildFilterRow() {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _filterToggle(
            label: 'Emergency Room',
            selected: filterOnlyER,
            color: AppColors.critical,
            onTap: (v) {
              setState(() => filterOnlyER = v);
              applyFilters();
            },
          ),
          const SizedBox(width: 8),
          _filterToggle(
            label: 'Mental Health',
            selected: filterMentalHealth,
            color: AppColors.wellness,
            onTap: (v) {
              setState(() => filterMentalHealth = v);
              applyFilters();
            },
          ),
          const SizedBox(width: 8),
          _filterToggle(
            label: 'Veteran Care',
            selected: filterVeterans,
            color: AppColors.coverage,
            onTap: (v) {
              setState(() => filterVeterans = v);
              applyFilters();
            },
          ),
          const SizedBox(width: 8),
          _filterToggle(
            label: 'Include labs',
            selected: includeLabs,
            color: AppColors.textSecondary,
            onTap: (v) {
              setState(() => includeLabs = v);
              applyFilters();
            },
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _showRadiusPicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.social_distance_rounded, size: 14, color: AppColors.accent),
                  const SizedBox(width: 5),
                  Text('${radiusMiles.round()} mi',
                      style: const TextStyle(color: AppColors.accent, fontSize: 12.5, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _mapToggleButton(),
        ],
      ),
    );
  }

  Widget _filterToggle({
    required String label,
    required bool selected,
    required Color color,
    required ValueChanged<bool> onTap,
  }) {
    return GestureDetector(
      onTap: () => onTap(!selected),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.14) : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : AppColors.border),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? color : AppColors.textSecondary,
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _mapToggleButton() {
    return GestureDetector(
      onTap: () => setState(() => isMapView = !isMapView),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(
          isMapView ? Icons.view_agenda_rounded : Icons.map_rounded,
          size: 16,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _mapLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          LegendDot(color: AppColors.critical, label: 'ER'),
          SizedBox(width: 8),
          LegendDot(color: AppColors.accent, label: 'Facility'),
        ],
      ),
    );
  }

  Widget buildListSection() {
    if (displayed.isEmpty) {
      final message = searchCenter == null
          ? 'Nothing to show yet.\nShare your location, type a ZIP code, or pick a city.'
          : 'No matching facilities found nearby.\nTry a larger radius or a different search.';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, height: 1.4)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      itemCount: displayed.length,
      itemBuilder: (context, index) {
        final item = displayed[index];
        return ClinicCard(
          clinic: item.clinic,
          distanceMiles: item.miles,
          bestMatch: activeNeed?.isBestMatch(item.clinic) ?? false,
          onDirections: () => openExternalMap(item.clinic),
          onTap: () => _showClinicDetail(item.clinic, item.miles),
        );
      },
    );
  }

  Widget buildMapSection() {
    final center = searchCenter;
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        // Centered on the user when we know where they are, otherwise on Louisiana.
        initialCenter: center ?? const LatLng(30.9, -91.8),
        initialZoom: center == null ? 6.3 : _zoomForRadius(radiusUsed),
        onMapReady: () {
          mapReady = true;
          final c = searchCenter;
          if (c != null) _moveMap(c, radiusUsed);
        },
      ),
      children: [
        TileLayer(
          urlTemplate: _tileUrl,
          subdomains: _useCarto ? const ['a', 'b', 'c', 'd'] : const ['a'],
          userAgentPackageName: 'com.example.la_clinic_finder',
        ),
        // The search radius, drawn as a circle around the user.
        if (center != null)
          CircleLayer(
            circles: [
              CircleMarker(
                point: center,
                radius: radiusUsed * 1609.34, // miles -> meters
                useRadiusInMeter: true,
                color: AppColors.accent.withValues(alpha: 0.06),
                borderColor: AppColors.accent.withValues(alpha: 0.5),
                borderStrokeWidth: 1.5,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            for (final item in displayed)
              if (item.clinic.hasRealLocation)
                Marker(
                  width: 26,
                  height: 26,
                  point: LatLng(item.clinic.latitude, item.clinic.longitude),
                  child: MapMarker(
                    clinic: item.clinic,
                    color: item.clinic.hasER ? AppColors.critical : AppColors.accent,
                    onTap: () => _showClinicDetail(item.clinic, item.miles),
                  ),
                ),
            if (center != null)
              Marker(
                width: 18,
                height: 18,
                point: center,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: AppColors.coverage, width: 4),
                  ),
                ),
              ),
          ],
        ),
        const RichAttributionWidget(
          attributions: [
            TextSourceAttribution(_tileCredit),
          ],
        ),
      ],
    );
  }
}
