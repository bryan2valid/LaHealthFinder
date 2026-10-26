/// What kind of place a record is. Derived from the LDH "PROGRAM TYPE" column
/// and the facility name, because the dataset has no explicit hospital flag.
enum FacilityType { hospital, healthCenter, therapy, xray, mental, lab }

extension FacilityTypeLabel on FacilityType {
  String get label {
    switch (this) {
      case FacilityType.hospital:
        return 'Hospital';
      case FacilityType.healthCenter:
        return 'Health center';
      case FacilityType.therapy:
        return 'Therapy';
      case FacilityType.xray:
        return 'Mobile X-ray';
      case FacilityType.mental:
        return 'Mental health';
      case FacilityType.lab:
        return 'Lab / clinic';
    }
  }
}

class Clinic {
  final String name;
  final String parish;
  final String address;
  final String city;
  final double latitude;
  final double longitude;
  final String phone;
  final String? website;
  final double? rating; // null = no rating data available yet
  final String traumaLevel;
  final FacilityType type;
  final bool isStrokeCenter;
  final bool hasER;
  final bool offersMentalHealth;
  final bool servesVeterans;
  final String languagesSpoken;

  /// True only when the ZIP code was found in assets/data/zip_codes.json.
  /// When false, latitude/longitude are 0 and the clinic is never used in
  /// distance searches (previously these were all pinned to downtown Hammond,
  /// which made them look "nearby" for anyone in that area).
  final bool hasRealLocation;

  Clinic({
    required this.name,
    required this.parish,
    required this.address,
    required this.city,
    required this.latitude,
    required this.longitude,
    required this.phone,
    this.website,
    this.rating,
    required this.traumaLevel,
    required this.type,
    required this.isStrokeCenter,
    required this.hasER,
    required this.offersMentalHealth,
    required this.servesVeterans,
    required this.languagesSpoken,
    required this.hasRealLocation,
  });

  factory Clinic.fromJson(Map<String, dynamic> json) {
    final facilityName = (json['FACILITY NAME'] ?? '').toString().toUpperCase();
    final programType = (json['PROGRAM TYPE'] ?? '').toString().toUpperCase();

    final isMentalHealth = programType.contains('MENTAL') ||
        facilityName.contains('MENTAL') ||
        facilityName.contains('BEHAVIORAL');
    final isVA = facilityName.contains('VETERAN') ||
        facilityName.contains(' VA ') ||
        facilityName.contains('VA MEDICAL');
    final type = _classify(facilityName, programType, isMentalHealth);

    // Real coordinates are attached by the ZIP lookup in main.dart.
    final rawLat = json['LATITUDE'];
    final rawLng = json['LONGITUDE'];
    final hasRealLocation = rawLat is num && rawLng is num;

    return Clinic(
      name: json['FACILITY NAME'] ?? 'Unknown Clinic',
      parish: json['PARISH'] ?? 'Unknown',
      address: json['ADDRESS'] ?? '',
      city: json['CITY'] ?? '',
      latitude: hasRealLocation ? rawLat.toDouble() : 0.0,
      longitude: hasRealLocation ? rawLng.toDouble() : 0.0,
      hasRealLocation: hasRealLocation,
      phone: json['TELEPHONE']?.toString() ?? 'N/A',
      website: json['WEBSITE'] as String?,
      rating: (json['RATING'] as num?)?.toDouble(),
      traumaLevel: json['TRAUMA LEVEL'] ?? 'None',
      type: type,
      // Inferred from the name/program type, not verified data.
      isStrokeCenter: false,
      hasER: type == FacilityType.hospital,
      offersMentalHealth: isMentalHealth,
      servesVeterans: isVA,
      languagesSpoken: 'English',
    );
  }

  static FacilityType _classify(String name, String program, bool mental) {
    if (name.contains('HOSPITAL') ||
        name.contains('MEDICAL CENTER') ||
        name.contains('EMERGENCY')) {
      return FacilityType.hospital;
    }
    if (program.contains('X-RAY')) return FacilityType.xray;
    if (program.contains('FEDERALLY QUALIFIED')) return FacilityType.healthCenter;
    if (program.contains('PHYSICAL THERAPY')) return FacilityType.therapy;
    if (mental) return FacilityType.mental;
    return FacilityType.lab;
  }
}
