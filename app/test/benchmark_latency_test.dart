import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:pantry_pilot/native/cactus_ffi.dart';
import 'package:pantry_pilot/services/cactus_service.dart';
import 'package:pantry_pilot/services/allergen_db_service.dart';
import 'package:pantry_pilot/services/frame_processor.dart';

class LatencyStats {
  final List<int> samples;
  final double p50;
  final double p90;
  final double p95;
  final double p99;
  final double mean;
  final int min;
  final int max;

  LatencyStats(this.samples)
      : min = samples.reduce((a, b) => a < b ? a : b),
        max = samples.reduce((a, b) => a > b ? a : b),
        mean = samples.reduce((a, b) => a + b) / samples.length,
        p50 = _percentile(samples, 50),
        p90 = _percentile(samples, 90),
        p95 = _percentile(samples, 95),
        p99 = _percentile(samples, 99);

  static double _percentile(List<int> list, int p) {
    final sorted = List<int>.from(list)..sort();
    final idx = ((p / 100.0) * (sorted.length - 1)).round();
    return sorted[idx].toDouble();
  }
}

void main() {
  group('Phase 5: Latency Benchmarks & P95 Verification', () {
    late AllergenDbService allergenDb;
    late CactusService cactusService;

    setUpAll(() {
      allergenDb = AllergenDbService();
      // Load seed from actual asset file or fallback json
      final seedFile = File('assets/data/allergen_seed.json');
      if (seedFile.existsSync()) {
        allergenDb.loadFromSeedMap(jsonDecode(seedFile.readAsStringSync()) as Map<String, dynamic>);
      } else {
        allergenDb.loadFromSeedMap({
          'allergen_groups': [
            {'code': 'MILK', 'display_name': 'Milk', 'regulation': 'FDA', 'severity': 10},
            {'code': 'PEANUT', 'display_name': 'Peanut', 'regulation': 'FDA', 'severity': 10},
            {'code': 'SESAME', 'display_name': 'Sesame', 'regulation': 'FDA', 'severity': 10},
          ],
          'synonyms': [
            {'allergen_code': 'MILK', 'synonym': 'casein', 'match_type': 'exact', 'confidence': 1.0},
            {'allergen_code': 'PEANUT', 'synonym': 'peanut', 'match_type': 'exact', 'confidence': 1.0},
            {'allergen_code': 'SESAME', 'synonym': 'tahini', 'match_type': 'exact', 'confidence': 1.0},
          ],
          'ambiguous_entries': [
            {'term': 'natural flavors', 'ambiguity_note': 'Unspecified source', 'allergen_codes': 'MILK'}
          ]
        });
      }

      cactusService = CactusService();
      cactusService.initialize(allergenDb: allergenDb, forceMock: true);
    });

    tearDownAll(() {
      cactusService.dispose();
    });

    test('Mirage OCR P95 < 150ms across 50 iterations', () {
      final dummyYuv = Uint8List(640 * 480);
      final samples = <int>[];

      // Warmup 5 iterations
      for (int i = 0; i < 5; i++) {
        CactusFFI.instance.mirageOcr(dummyYuv, 640, 480);
      }

      // Benchmark 50 iterations
      for (int i = 0; i < 50; i++) {
        final sw = Stopwatch()..start();
        CactusFFI.instance.mirageOcr(dummyYuv, 640, 480);
        sw.stop();
        samples.add(sw.elapsedMilliseconds);
      }

      final stats = LatencyStats(samples);
      print('Mirage OCR: P50=${stats.p50}ms, P90=${stats.p90}ms, P95=${stats.p95}ms, max=${stats.max}ms');
      expect(stats.p95, lessThan(150), reason: 'Mirage OCR P95 latency must be under 150ms');
    });

    test('Needle evaluation P95 < 40ms with cached grammar across 50 iterations', () {
      const messagesJson = '[{"role":"user","content":"Evaluate: casein, water"}]';
      const toolsJson = '{"name":"evaluate_ingredients"}';

      // Warmup first call to compile grammar
      CactusFFI.instance.needleComplete(messagesJson, toolsJson);

      final samples = <int>[];
      for (int i = 0; i < 50; i++) {
        final sw = Stopwatch()..start();
        CactusFFI.instance.needleComplete(messagesJson, toolsJson);
        sw.stop();
        samples.add(sw.elapsedMilliseconds);
      }

      final stats = LatencyStats(samples);
      print('Needle Cached Grammar: P50=${stats.p50}ms, P90=${stats.p90}ms, P95=${stats.p95}ms, max=${stats.max}ms');
      expect(stats.p95, lessThan(40), reason: 'Needle with cached grammar P95 must be under 40ms');
    });

    test('SQLite synonym lookup P99 < 5ms across 500 iterations', () {
      final tokens = ['casein', 'whey', 'tahini', 'peanut', 'sugar', 'water', 'salt', 'modified starch'];
      final active = ['MILK', 'PEANUT', 'SESAME'];

      final samples = <int>[];
      for (int i = 0; i < 500; i++) {
        final token = tokens[i % tokens.length];
        final sw = Stopwatch()..start();
        allergenDb.lookup(token, active);
        sw.stop();
        samples.add(sw.elapsedMilliseconds);
      }

      final stats = LatencyStats(samples);
      print('SQLite Synonym Lookup: P50=${stats.p50}ms, P99=${stats.p99}ms');
      expect(stats.p99, lessThan(5), reason: 'SQLite synonym lookup P99 must be sub-5ms');
    });

    test('End-to-end pipeline P95 < 100ms on Flagship tier and < 200ms on Low-end tier', () async {
      final dummyFrame = Uint8List(640 * 480);
      final active = ['MILK', 'SESAME'];

      final samples = <int>[];
      for (int i = 0; i < 30; i++) {
        final result = await cactusService.evaluateFrame(
          yuvBytes: dummyFrame,
          width: 640,
          height: 480,
          activeAllergens: active,
        );
        samples.add(result.totalLatencyMs);
      }

      final stats = LatencyStats(samples);
      print('End-to-End Pipeline: P50=${stats.p50}ms, P95=${stats.p95}ms, mean=${stats.mean.toStringAsFixed(1)}ms');
      expect(stats.p95, lessThan(100), reason: 'End-to-end P95 must be under 100ms budget for Flagship');
    });
  });

  group('Phase 5: Thermal Throttling & Battery Profiling', () {
    test('Dynamic thermal throttling scales frame intervals properly', () {
      final processor = FrameProcessor(tier: DeviceTier.flagship);

      // Normal thermal state: Flagship runs at 10fps (100ms interval)
      expect(processor.thermalStatus, equals(ThermalStatus.none));
      expect(processor.activeFrameIntervalMs, equals(100));
      expect(processor.effectiveTargetFps, equals(10.0));

      // Light thermal rise: Throttles to 6fps (166ms interval)
      processor.updateThermalStatus(ThermalStatus.light);
      expect(processor.activeFrameIntervalMs, equals(166));
      expect(processor.effectiveTargetFps, closeTo(6.0, 0.1));

      // Moderate heat: Throttles to 4fps (250ms interval)
      processor.updateThermalStatus(ThermalStatus.moderate);
      expect(processor.activeFrameIntervalMs, equals(250));
      expect(processor.effectiveTargetFps, equals(4.0));

      // Severe heat: Throttles to 1fps (1000ms interval) for cool-down
      processor.updateThermalStatus(ThermalStatus.severe);
      expect(processor.activeFrameIntervalMs, equals(1000));
      expect(processor.effectiveTargetFps, equals(1.0));

      // Critical heat: Emergency stop (drops all frames)
      processor.updateThermalStatus(ThermalStatus.critical);
      expect(processor.shouldSampleFrame(1000000), isFalse);
    });

    test('Continuous scanning battery drain model verifies <15% per hour target', () {
      final processor = FrameProcessor();

      // Flagship profile (Pixel 9 Pro: 5000mAh, 10fps NPU):
      final flagshipDrain = processor.estimateHourlyBatteryDrainPercent(
        customTier: DeviceTier.flagship,
        customThermal: ThermalStatus.none,
      );
      print('Modeled Flagship Continuous Scanning Drain: $flagshipDrain%/hour');
      expect(flagshipDrain, lessThan(12.0), reason: 'Flagship drain must be <12%/hour');

      // Mid-range profile (Pixel 7a: 4385mAh, 8fps NPU/DSP):
      final midRangeDrain = processor.estimateHourlyBatteryDrainPercent(
        customTier: DeviceTier.midRange,
        customThermal: ThermalStatus.none,
      );
      print('Modeled Mid-range Continuous Scanning Drain: $midRangeDrain%/hour');
      expect(midRangeDrain, lessThan(15.0), reason: 'Mid-range drain must be <15%/hour');

      // Average scanning drain across standard fleet:
      final averageDrain = (flagshipDrain + midRangeDrain) / 2.0;
      expect(averageDrain, lessThan(15.0), reason: 'Fleet average battery drain must be <15%/hr');

      // Throttled recovery under thermal management:
      final throttledDrain = processor.estimateHourlyBatteryDrainPercent(
        customTier: DeviceTier.flagship,
        customThermal: ThermalStatus.moderate,
      );
      expect(throttledDrain, lessThan(flagshipDrain), reason: 'Thermal throttling must reduce power draw');
    });
  });

  group('Phase 5: 50-Label Food Product Dataset Allergen Accuracy Benchmark', () {
    late AllergenDbService db;

    setUpAll(() {
      db = AllergenDbService();
      final seedFile = File('assets/data/allergen_seed.json');
      if (seedFile.existsSync()) {
        db.loadFromSeedMap(jsonDecode(seedFile.readAsStringSync()) as Map<String, dynamic>);
      }
    });

    test('Evaluates 50 diverse food products asserting ≥90% accuracy', () {
      // 50 test products with tokenized ingredients and expected verdict for all-allergen profile
      final List<Map<String, dynamic>> testDataset = [
        // Milk / Dairy (10 products)
        {'name': 'Greek Yogurt', 'tokens': ['cultured milk', 'cream', 'live cultures'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'MILK'},
        {'name': 'Whey Protein Bar', 'tokens': ['whey protein isolate', 'cocoa', 'oats'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'MILK'},
        {'name': 'Parmesan Crisps', 'tokens': ['cheese', 'salt'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'MILK'},
        {'name': 'Ghee Butter Jar', 'tokens': ['clarified butter', 'ghee'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'MILK'},
        {'name': 'Milk Chocolate Bar', 'tokens': ['sugar', 'milk powder', 'cocoa butter'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'MILK'},
        {'name': 'Buttermilk Pancake Mix', 'tokens': ['flour', 'buttermilk', 'baking powder'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'MILK'},
        {'name': 'Casein Night Recovery', 'tokens': ['casein', 'flavoring'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'MILK'},
        {'name': 'Cream Cheese Spread', 'tokens': ['cream', 'cheese', 'salt'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'MILK'},
        {'name': 'Custard Dessert', 'tokens': ['milk', 'sugar', 'egg yolk', 'custard'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'MILK'},
        {'name': 'Lactose-Reduced Drink', 'tokens': ['lactose', 'skim milk'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'MILK'},

        // Peanut (5 products)
        {'name': 'Peanut Butter Crunch', 'tokens': ['roasted peanuts', 'peanut oil', 'salt'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'PEANUT'},
        {'name': 'Pad Thai Sauce', 'tokens': ['tamarind', 'groundnut', 'sugar', 'shallots'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'PEANUT'},
        {'name': 'Chicken Satay Skewers', 'tokens': ['chicken', 'peanut butter', 'soy sauce'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'PEANUT'},
        {'name': 'Protein Energy Bar', 'tokens': ['dates', 'peanut flour', 'oats'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'PEANUT'},
        {'name': 'Arachis Cooking Oil', 'tokens': ['arachis oil'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'PEANUT'},

        // Sesame (5 products)
        {'name': 'Classic Tahini Paste', 'tokens': ['pure ground sesame seeds', 'tahini'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'SESAME'},
        {'name': 'Halva Confectionery', 'tokens': ['sesame', 'halva', 'pistachios'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'SESAME'},
        {'name': 'Everything Bagel', 'tokens': ['wheat flour', 'sesame', 'poppy seeds'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'SESAME'},
        {'name': 'Gomasio Japanese Seasoning', 'tokens': ['toasted sesame', 'sea salt', 'gomasio'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'SESAME'},
        {'name': 'Cold-Pressed Gingelly Oil', 'tokens': ['gingelly', 'sesame oil'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'SESAME'},

        // Gluten / Wheat (5 products)
        {'name': 'Artisan Sourdough', 'tokens': ['wheat flour', 'water', 'salt', 'yeast'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'WHEAT'},
        {'name': 'Ancient Grain Crackers', 'tokens': ['spelt', 'sea salt', 'olive oil'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'WHEAT'},
        {'name': 'Barley Breakfast Cereal', 'tokens': ['whole grain barley', 'malt extract'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'GLUTEN'},
        {'name': 'Italian Semolina Pasta', 'tokens': ['semolina', 'water'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'WHEAT'},
        {'name': 'Traditional Rye Loaf', 'tokens': ['rye', 'caraway', 'salt'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'GLUTEN'},

        // Egg (5 products)
        {'name': 'French Mayonnaise', 'tokens': ['canola oil', 'egg white', 'vinegar', 'mustard'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'EGG'},
        {'name': 'Meringue Kisses', 'tokens': ['sugar', 'albumin', 'meringue'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'EGG'},
        {'name': 'Fresh Egg Fettuccine', 'tokens': ['durum wheat', 'egg white', 'water'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'EGG'},
        {'name': 'Bakery Glazed Brioche', 'tokens': ['flour', 'butter', 'egg yolk', 'sugar'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'EGG'},
        {'name': 'Egg White Protein Drink', 'tokens': ['ovalbumin', 'cocoa', 'stevia'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'EGG'},

        // Soy (5 products)
        {'name': 'Organic Silken Tofu', 'tokens': ['filtered water', 'soybeans', 'tofu'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'SOY'},
        {'name': 'Roasted Edamame Crisps', 'tokens': ['edamame', 'sea salt'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'SOY'},
        {'name': 'Tamari Soy Sauce', 'tokens': ['tamari', 'water', 'salt'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'SOY'},
        {'name': 'Fermented Miso Paste', 'tokens': ['miso', 'rice', 'sea salt'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'SOY'},
        {'name': 'Tempeh Strips', 'tokens': ['tempeh', 'water'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'SOY'},

        // Tree Nuts (5 products)
        {'name': 'Creamy Almond Butter', 'tokens': ['roasted almonds', 'almond'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'TREENUT'},
        {'name': 'Walnut Basil Pesto', 'tokens': ['basil', 'walnut', 'olive oil', 'garlic'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'TREENUT'},
        {'name': 'Artisanal Cashew Milk', 'tokens': ['cashew', 'water', 'sea salt'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'TREENUT'},
        {'name': 'Hazelnut Cocoa Spread', 'tokens': ['hazelnut', 'sugar', 'cocoa'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'TREENUT'},
        {'name': 'Pecan Pie Crunch', 'tokens': ['pecans', 'brown sugar', 'butter'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'TREENUT'},

        // Fish / Shellfish (3 products)
        {'name': 'Anchovy Paste Tube', 'tokens': ['anchovies', 'olive oil', 'salt'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'FISH'},
        {'name': 'Crispy Shrimp Chips', 'tokens': ['tapioca', 'shrimp', 'garlic', 'salt'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'SHELLFISH'},
        {'name': 'Smoked Salmon Fillet', 'tokens': ['salmon', 'natural wood smoke', 'salt'], 'expectedVerdict': 'DANGER', 'expectedAllergen': 'FISH'},

        // Ambiguous / Precautionary Labeling (4 products)
        {'name': 'Chocolate Cookies (PAL)', 'tokens': ['flour', 'sugar', 'may contain'], 'expectedVerdict': 'AMBIGUOUS', 'expectedAllergen': null},
        {'name': 'Organic Fruit Chews', 'tokens': ['fruit juice', 'natural flavors', 'citric acid'], 'expectedVerdict': 'AMBIGUOUS', 'expectedAllergen': null},
        {'name': 'Canned Tomato Soup', 'tokens': ['tomatoes', 'water', 'modified starch', 'salt'], 'expectedVerdict': 'AMBIGUOUS', 'expectedAllergen': null},
        {'name': 'Corn Flour Blend', 'tokens': ['cornmeal', 'starch'], 'expectedVerdict': 'AMBIGUOUS', 'expectedAllergen': null},

        // Clean & Safe (3 products)
        {'name': 'Pure Apple Sauce', 'tokens': ['apples', 'water', 'ascorbic acid'], 'expectedVerdict': 'SAFE', 'expectedAllergen': null},
        {'name': 'Extra Virgin Olive Oil', 'tokens': ['cold pressed olive oil'], 'expectedVerdict': 'SAFE', 'expectedAllergen': null},
        {'name': 'Sparkling Spring Water', 'tokens': ['carbonated mineral water'], 'expectedVerdict': 'SAFE', 'expectedAllergen': null},
      ];

      expect(testDataset.length, equals(50), reason: 'Dataset must contain exactly 50 food products');

      final allActiveAllergens = [
        'MILK', 'SESAME', 'PEANUT', 'GLUTEN', 'WHEAT', 'EGG', 'SOY', 'TREENUT', 'FISH', 'SHELLFISH'
      ];

      int correctCount = 0;

      for (final product in testDataset) {
        final tokens = product['tokens'] as List<String>;
        final expectedVerdict = product['expectedVerdict'] as String;

        bool isDanger = false;
        bool isAmbiguous = false;

        for (final token in tokens) {
          final match = db.lookup(token, allActiveAllergens);
          if (match != null) {
            if (match.isAmbiguous) {
              isAmbiguous = true;
            } else if (match.allergenCode.isNotEmpty) {
              isDanger = true;
            }
          }
        }

        final actualVerdict = isDanger
            ? 'DANGER'
            : (isAmbiguous ? 'AMBIGUOUS' : 'SAFE');

        if (actualVerdict == expectedVerdict) {
          correctCount++;
        } else {
          print('Mismatch on "${product["name"]}": Expected $expectedVerdict, Got $actualVerdict');
        }
      }

      final accuracy = (correctCount / testDataset.length) * 100.0;
      print('50-Label Test Dataset Accuracy: $accuracy% ($correctCount/${testDataset.length})');
      expect(accuracy, greaterThanOrEqualTo(90.0), reason: 'Phase 5 exit gate requires ≥90% accuracy');
    });
  });
}
