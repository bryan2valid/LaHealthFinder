// Builds assets/data/zip_codes.json for every ZIP code used in clinics.json.
//
// Why: the app places each clinic on the map using its ZIP code, and the
// clinics file has no coordinates of its own. Any ZIP missing from
// zip_codes.json means that clinic can't be shown as "nearby".
//
// Run from the project root (the folder with pubspec.yaml), with internet on:
//
//   dart run tools/build_zip_codes.dart
//
// It looks up each missing ZIP once (about 2-4 minutes), keeps the ones
// you already have, and prints any it couldn't find.
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final clinicsFile = File('assets/data/clinics.json');
  final outFile = File('assets/data/zip_codes.json');
  if (!clinicsFile.existsSync()) {
    stderr.writeln('Run this from the project root (assets/data/clinics.json not found).');
    exit(1);
  }

  // 1) Every distinct 5-digit ZIP in the clinics file.
  final clinics = json.decode(clinicsFile.readAsStringSync()) as List<dynamic>;
  final needed = <String>{};
  for (final c in clinics) {
    final zip = (c['ZIP']?.toString() ?? '').trim().split('-').first;
    if (RegExp(r'^\d{5}$').hasMatch(zip)) needed.add(zip);
  }

  // 2) Keep any ZIPs we already have.
  final result = SplayTreeMap<String, Map<String, double>>();
  if (outFile.existsSync()) {
    final existing = json.decode(outFile.readAsStringSync()) as Map<String, dynamic>;
    existing.forEach((zip, v) {
      result[zip] = {
        'latitude': (v['latitude'] as num).toDouble(),
        'longitude': (v['longitude'] as num).toDouble(),
      };
    });
  }

  final todo = needed.where((z) => !result.containsKey(z)).toList()..sort();
  stdout.writeln('${needed.length} ZIPs in clinics.json, ${result.length} already known, ${todo.length} to look up.');

  // 3) Look up the rest, one at a time (polite to the free service).
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  final failed = <String>[];
  var done = 0;
  for (final zip in todo) {
    try {
      final request = await client.getUrl(Uri.parse('https://api.zippopotam.us/us/$zip'));
      final response = await request.close().timeout(const Duration(seconds: 15));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == 200) {
        final place = (json.decode(body)['places'] as List).first;
        result[zip] = {
          'latitude': double.parse(place['latitude'].toString()),
          'longitude': double.parse(place['longitude'].toString()),
        };
      } else {
        failed.add(zip);
      }
    } catch (e) {
      failed.add(zip);
    }
    done++;
    if (done % 25 == 0) stdout.writeln('  $done / ${todo.length}');
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  client.close();

  // 4) Save.
  outFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
  stdout.writeln('Saved ${result.length} ZIP codes to ${outFile.path}');
  if (failed.isNotEmpty) {
    stdout.writeln('${failed.length} could not be found (those clinics stay unlocated): ${failed.take(20).join(', ')}');
  }
  stdout.writeln('Done. Stop the app and run it again to use the new data.');
}
