import 'package:flutter_test/flutter_test.dart';
import 'package:la_clinic_finder/clinic_model.dart';
import 'package:la_clinic_finder/services/care_matcher.dart';
import 'package:la_clinic_finder/services/geo.dart';

Clinic clinic(String name, {double? lat, double? lng, String program = 'LAB-CLIA'}) {
  return Clinic.fromJson({
    'FACILITY NAME': name,
    'PROGRAM TYPE': program,
    'LATITUDE': ?lat,
    'LONGITUDE': ?lng,
  });
}

void main() {
  // Hammond, LA
  const lat = 30.5044, lng = -90.4612;

  group('haversineMiles', () {
    test('same point is zero', () {
      expect(haversineMiles(lat, lng, lat, lng), closeTo(0, 0.001));
    });

    test('Hammond to Baton Rouge is about 40 miles', () {
      expect(haversineMiles(lat, lng, 30.4515, -91.1388), closeTo(40.5, 1.0));
    });
  });

  group('findNearby', () {
    final near = clinic('NEAR GENERAL HOSPITAL', lat: 30.512, lng: -90.478); // ~1 mi
    final mid = clinic('MID HOSPITAL', lat: 30.4515, lng: -91.1388); // ~40 mi
    final unplaced = clinic('NO ZIP HOSPITAL'); // no coordinates
    final all = [mid, unplaced, near];

    test('keeps only clinics inside the radius, nearest first', () {
      final r = findNearby(candidates: all, lat: lat, lng: lng, radiusMiles: 10, minResults: 1);
      expect(r.items.map((i) => i.clinic.name), ['NEAR GENERAL HOSPITAL']);
      expect(r.widened, isFalse);
    });

    test('never includes clinics without a real location', () {
      final r = findNearby(candidates: all, lat: lat, lng: lng, radiusMiles: 100);
      expect(r.items.any((i) => i.clinic.name == 'NO ZIP HOSPITAL'), isFalse);
    });

    test('widens the radius when too few results', () {
      final r = findNearby(candidates: all, lat: lat, lng: lng, radiusMiles: 10, minResults: 2);
      expect(r.widened, isTrue);
      expect(r.radiusUsed, 50);
      expect(r.items.length, 2);
      expect(r.items.first.clinic.name, 'NEAR GENERAL HOSPITAL');
    });
  });

  group('CareMatcher', () {
    test('maps everyday phrases to a kind of care', () {
      expect(CareMatcher.match('broken arm')?.id, 'injury');
      expect(CareMatcher.match('X-ray')?.id, 'xray');
      expect(CareMatcher.match('x ray please')?.id, 'xray');
      expect(CareMatcher.match('cancer treatment')?.id, 'cancer');
      expect(CareMatcher.match('sports physical')?.id, 'checkup');
    });

    test('physical therapy is not confused with a physical exam', () {
      expect(CareMatcher.match('physical therapy')?.id, 'therapy');
    });

    test('plain names do not match a need', () {
      expect(CareMatcher.match('Abbeville General'), isNull);
      expect(CareMatcher.match(''), isNull);
    });

    test('cancer search accepts hospitals and oncology-named clinics', () {
      final need = CareMatcher.match('cancer')!;
      expect(need.accepts(clinic('SOME HOSPITAL', lat: 1, lng: 1)), isTrue);
      expect(need.accepts(clinic('ACADIANA ONCOLOGY', lat: 1, lng: 1)), isTrue);
      expect(need.accepts(clinic('JOES LAB', lat: 1, lng: 1)), isFalse);
    });
  });
}
