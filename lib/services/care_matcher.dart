import '../clinic_model.dart';

/// A kind of care someone might search for ("x-ray", "broken arm", ...) and
/// which kinds of facility can reasonably help.
///
/// NOTE: clinics.json has no list of services per facility, so matching is
/// based on facility type and name. It points people to sensible places to
/// start; it can't confirm a given hospital offers a given service.
class CareNeed {
  final String id;
  final String label;
  final String hint;
  final List<String> keywords;
  final Set<FacilityType> types;

  /// Words in a facility name that make it an especially good match
  /// (e.g. "ONCOLOGY" for cancer care), even if its type isn't in [types].
  final List<String> nameBoost;
  final bool requiresER;

  const CareNeed({
    required this.id,
    required this.label,
    required this.hint,
    required this.keywords,
    required this.types,
    this.nameBoost = const [],
    this.requiresER = false,
  });

  bool isBestMatch(Clinic c) {
    final name = c.name.toUpperCase();
    return nameBoost.any(name.contains);
  }

  bool accepts(Clinic c) {
    if (isBestMatch(c)) return true;
    if (!types.contains(c.type)) return false;
    return !requiresER || c.hasER;
  }
}

class CareMatcher {
  CareMatcher._();

  // Order matters: more specific needs come first ("physical therapy" must
  // be checked before the general "physical" / check-up need).
  static const List<CareNeed> needs = [
    CareNeed(
      id: 'therapy',
      label: 'Physical therapy & rehab',
      hint: 'Outpatient physical therapy providers',
      keywords: ['physical therapy', 'rehab', 'rehabilitation', 'pt'],
      types: {FacilityType.therapy},
      nameBoost: ['PHYSICAL THERAPY', 'REHAB'],
    ),
    CareNeed(
      id: 'xray',
      label: 'X-ray & imaging',
      hint: 'Hospitals and health centers, which typically have imaging',
      keywords: ['x-ray', 'xray', 'x ray', 'imaging', 'radiology', 'scan', 'mri', 'ct'],
      types: {FacilityType.hospital, FacilityType.healthCenter},
      nameBoost: ['IMAGING', 'RADIOLOGY'],
    ),
    CareNeed(
      id: 'cancer',
      label: 'Cancer care',
      hint: 'Cancer centers first, then hospitals',
      keywords: ['cancer', 'oncology', 'chemo', 'chemotherapy', 'tumor', 'radiation'],
      types: {FacilityType.hospital},
      nameBoost: ['CANCER', 'ONCOLOGY', 'HEMATOLOGY'],
    ),
    CareNeed(
      id: 'injury',
      label: 'Injuries & broken bones',
      hint: 'Hospitals with an emergency room',
      keywords: [
        'broken', 'fracture', 'sprain', 'injury', 'arm', 'leg', 'wrist',
        'ankle', 'bone', 'emergency', 'er', 'accident',
      ],
      types: {FacilityType.hospital},
      nameBoost: ['ORTHOPEDIC', 'ORTHOPAEDIC', 'EMERGENCY'],
      requiresER: true,
    ),
    CareNeed(
      id: 'mental',
      label: 'Mental health',
      hint: 'Mental and behavioral health providers',
      keywords: ['mental', 'counseling', 'anxiety', 'depression', 'behavioral'],
      types: {FacilityType.mental},
      nameBoost: ['BEHAVIORAL', 'MENTAL'],
    ),
    CareNeed(
      id: 'checkup',
      label: 'Physicals & check-ups',
      hint: 'Community health centers and hospital clinics',
      keywords: ['physical', 'checkup', 'check-up', 'annual', 'primary care', 'doctor', 'vaccine'],
      types: {FacilityType.healthCenter, FacilityType.hospital},
      nameBoost: ['FAMILY', 'PRIMARY CARE'],
    ),
  ];

  /// Returns the first need whose keyword appears in [query], or null.
  static CareNeed? match(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return null;

    // Single words, plus a version without a trailing "s" ("scans" -> "scan").
    final tokens = <String>{};
    for (final t in q.split(RegExp(r'[^a-z0-9\-]+'))) {
      if (t.isEmpty) continue;
      tokens.add(t);
      if (t.endsWith('s')) tokens.add(t.substring(0, t.length - 1));
    }

    for (final need in needs) {
      for (final k in need.keywords) {
        final isPhrase = k.contains(' ') || k.contains('-');
        if (isPhrase ? q.contains(k) : tokens.contains(k)) return need;
      }
    }
    return null;
  }
}
