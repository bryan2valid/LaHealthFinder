import 'dart:math' as math;
import '../clinic_model.dart';

const double _earthRadiusMiles = 3958.8;

/// Great-circle ("as the crow flies") distance between two lat/lng points,
/// in miles, using the haversine formula.
double haversineMiles(double lat1, double lng1, double lat2, double lng2) {
  double rad(double deg) => deg * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final sLat = math.sin(dLat / 2);
  final sLng = math.sin(dLng / 2);
  final a = sLat * sLat + math.cos(rad(lat1)) * math.cos(rad(lat2)) * sLng * sLng;
  return 2 * _earthRadiusMiles * math.asin(math.sqrt(a));
}

/// A clinic paired with its distance from the search point. `miles` is null
/// when there is no search point (no GPS and no ZIP entered).
class NearbyClinic {
  final Clinic clinic;
  final double? miles;
  const NearbyClinic(this.clinic, this.miles);
}

class NearbyResult {
  final List<NearbyClinic> items;

  /// The radius that was actually used (can be larger than requested).
  final double radiusUsed;

  /// True when the requested radius had too few results and we widened it.
  final bool widened;

  const NearbyResult(this.items, this.radiusUsed, this.widened);
}

/// Finds the clinics closest to a point.
///
/// 1. Measure every candidate once (clinics with no known location are skipped).
/// 2. Sort by distance, nearest first.
/// 3. Keep everything inside [radiusMiles]. If that gives fewer than
///    [minResults], widen through [expandTo] (25 -> 50 -> 100 mi) until there
///    are enough, so rural users don't get an empty screen.
/// 4. Cap the list at [maxResults] so the list and map stay fast.
NearbyResult findNearby({
  required Iterable<Clinic> candidates,
  required double lat,
  required double lng,
  required double radiusMiles,
  List<double> expandTo = const [25, 50, 100],
  int minResults = 5,
  int maxResults = 50,
}) {
  final measured = <NearbyClinic>[];
  for (final c in candidates) {
    if (!c.hasRealLocation) continue;
    measured.add(NearbyClinic(c, haversineMiles(lat, lng, c.latitude, c.longitude)));
  }
  measured.sort((a, b) => a.miles!.compareTo(b.miles!));

  final radii = <double>[radiusMiles, ...expandTo.where((r) => r > radiusMiles)];
  for (final r in radii) {
    // The list is sorted, so everything within r is a prefix of it.
    final within = measured.takeWhile((m) => m.miles! <= r).toList();
    if (within.length >= minResults || r == radii.last) {
      return NearbyResult(within.take(maxResults).toList(), r, r != radiusMiles);
    }
  }
  return NearbyResult(const [], radiusMiles, false);
}
