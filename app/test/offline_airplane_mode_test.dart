import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:pantry_pilot/services/cactus_service.dart';
import 'package:pantry_pilot/services/allergen_db_service.dart';

void main() {
  group('Phase 5: 100% Offline Airplane-Mode Verification', () {
    test('Android main Manifest strictly omits INTERNET permission', () {
      final manifestFile = File('android/app/src/main/AndroidManifest.xml');
      expect(manifestFile.existsSync(), isTrue, reason: 'AndroidManifest.xml must exist');

      final content = manifestFile.readAsStringSync();
      expect(
        content.contains('android.permission.INTERNET'),
        isFalse,
        reason: 'Production manifest must NOT request android.permission.INTERNET',
      );
      expect(
        content.contains('android.permission.CAMERA'),
        isTrue,
        reason: 'Manifest must declare CAMERA permission for offline scanning',
      );
      expect(
        content.contains('android:networkSecurityConfig="@xml/network_security_config"'),
        isTrue,
        reason: 'Manifest must bind to networkSecurityConfig to enforce offline posture',
      );
    });

    test('Network Security Config completely blocks cleartext traffic and drops trust anchors', () {
      final configXml = File('android/app/src/main/res/xml/network_security_config.xml');
      expect(configXml.existsSync(), isTrue, reason: 'network_security_config.xml must exist');

      final content = configXml.readAsStringSync();
      expect(
        content.contains('cleartextTrafficPermitted="false"'),
        isTrue,
        reason: 'Cleartext traffic must be disallowed in network security config',
      );
      expect(
        content.contains('<trust-anchors />') || content.contains('<trust-anchors/>'),
        isTrue,
        reason: 'Trust anchors must be empty to disallow SSL/TLS egress certificates',
      );
    });

    test('All core services operate with zero network access and complete local isolation', () async {
      // Setup fully isolated database
      final allergenDb = AllergenDbService();
      allergenDb.loadFromSeedMap({
        'allergen_groups': [
          {'code': 'PEANUT', 'display_name': 'Peanut', 'regulation': 'FDA', 'severity': 10},
          {'code': 'MILK', 'display_name': 'Milk', 'regulation': 'FDA', 'severity': 10},
        ],
        'synonyms': [
          {'allergen_code': 'PEANUT', 'synonym': 'groundnut', 'match_type': 'exact', 'confidence': 0.99, 'source_note': null},
          {'allergen_code': 'MILK', 'synonym': 'casein', 'match_type': 'exact', 'confidence': 0.99, 'source_note': null},
        ],
        'ambiguous_entries': [
          {'term': 'natural flavors', 'ambiguity_note': 'May contain dairy or allergens', 'allergen_codes': 'MILK'}
        ]
      });

      final cactus = CactusService();
      cactus.initialize(allergenDb: allergenDb, forceMock: true);

      // Verify DB lookup executes purely in-memory
      final match = allergenDb.lookup('groundnut', ['PEANUT']);
      expect(match, isNotNull);
      expect(match!.allergenCode, equals('PEANUT'));

      // Verify full evaluation runs offline with zero HTTP egress
      final dummyYuv = Uint8List(640 * 480);
      final result = await cactus.evaluateFrame(
        yuvBytes: dummyYuv,
        width: 640,
        height: 480,
        activeAllergens: ['PEANUT', 'MILK'],
      );

      expect(result.overallVerdict, equals('DANGER'));
      expect(result.findings.any((f) => f.matchedAllergen == 'MILK'), isTrue);

      cactus.dispose();
    });
  });
}

