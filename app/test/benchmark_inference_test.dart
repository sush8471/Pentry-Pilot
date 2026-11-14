import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:pantry_pilot/native/cactus_ffi.dart';
import 'package:pantry_pilot/services/cactus_service.dart';
import 'package:pantry_pilot/services/allergen_db_service.dart';
import 'package:pantry_pilot/models/allergen_finding.dart';

// Minimal seed JSON so AllergenDbService can be loaded in tests
const _minimalSeedJson = '''
{
  "allergen_groups": [
    {"code": "MILK", "display_name": "Milk / Dairy", "regulation": "FDA", "severity": 10}
  ],
  "synonyms": [
    {"allergen_code": "MILK", "synonym": "casein", "match_type": "exact", "confidence": 0.99, "source_note": null}
  ],
  "ambiguous_entries": [
    {"term": "natural flavors", "ambiguity_note": "May contain dairy derivatives", "allergen_codes": "MILK"}
  ]
}
''';

void main() {
  group('Phase 1: Cactus Engine & FFI Benchmarks', () {
    late CactusService cactusService;
    late AllergenDbService allergenDb;

    setUp(() {
      allergenDb = AllergenDbService();
      allergenDb.loadFromSeedMap(jsonDecode(_minimalSeedJson) as Map<String, dynamic>);

      cactusService = CactusService();
      cactusService.initialize(allergenDb: allergenDb, forceMock: true);
    });

    tearDown(() {
      cactusService.dispose();
    });

    test('Cactus FFI initializes handles and loads models', () {
      expect(CactusFFI.instance.isInitialized, isTrue);
    });

    test('Mirage OCR latency benchmark returns tokens and bboxes within 150ms target', () {
      final dummyYuv = Uint8List(640 * 480);
      final sw = Stopwatch()..start();
      final ocrJson = CactusFFI.instance.mirageOcr(dummyYuv, 640, 480);
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(150), reason: 'OCR latency must be under 150ms');
      expect(ocrJson.contains('tokens'), isTrue);
      expect(ocrJson.contains('bounding_boxes'), isTrue);
    });

    test('Needle agent evaluation latency benchmark under 50ms with valid JSON schema', () {
      const messagesJson = '[{"role":"user","content":"Evaluate: casein, water"}]';
      const toolsJson = '{"name":"evaluate_ingredients"}';

      final sw = Stopwatch()..start();
      final needleJson = CactusFFI.instance.needleComplete(messagesJson, toolsJson);
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(50), reason: 'Needle evaluation must be under 50ms');
      expect(needleJson.contains('findings'), isTrue);
      expect(needleJson.contains('overall_verdict'), isTrue);
    });

    test('End-to-end frame evaluation returns structured findings with coordinates', () async {
      final dummyFrame = Uint8List(640 * 480);
      final result = await cactusService.evaluateFrame(
        yuvBytes: dummyFrame,
        width: 640,
        height: 480,
        activeAllergens: ['MILK', 'DAIRY'],
      );

      expect(result.overallVerdict, equals('DANGER'));
      expect(result.findings.isNotEmpty, isTrue);

      final caseinFinding = result.findings.firstWhere((f) => f.token == 'casein');
      expect(caseinFinding.status, equals(FindingStatus.danger));
      expect(caseinFinding.matchedAllergen, equals('MILK'));
      expect(caseinFinding.bbox, isNotNull);
      expect(caseinFinding.bbox!.x, greaterThan(0));

      // Ambiguous item check
      final flavorsFinding = result.findings.firstWhere((f) => f.token == 'natural flavors');
      expect(flavorsFinding.status, equals(FindingStatus.ambiguous));

      // DB stats sanity check: casein should have been a DB hit, not Needle
      expect(result.dbHitCount, greaterThan(0));

      // Total latency budget verification (<100ms target on mock/flagship)
      expect(result.totalLatencyMs, lessThan(100));
    });
  });
}
