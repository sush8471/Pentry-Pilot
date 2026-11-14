import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/cactus_service.dart';
import '../services/camera_service.dart';
import '../services/allergen_db_service.dart';
import '../services/frame_processor.dart';
import 'scanning_provider.dart';
import 'profile_provider.dart';

/// Provider for AllergenDbService, loaded from allergen_seed.json
final allergenDbProvider = FutureProvider<AllergenDbService>((ref) async {
  final db = AllergenDbService();
  try {
    final seedString = await rootBundle.loadString('assets/data/allergen_seed.json');
    final seedMap = jsonDecode(seedString) as Map<String, dynamic>;
    db.loadFromSeedMap(seedMap);
  } catch (_) {
    // Fallback if asset loading fails in headless test
  }
  return db;
});

/// Global provider for initialized CactusService
final cactusServiceProvider = FutureProvider<CactusService>((ref) async {
  final allergenDb = await ref.watch(allergenDbProvider.future);
  final cactus = CactusService();
  cactus.initialize(allergenDb: allergenDb, forceMock: true);
  return cactus;
});

/// Global provider for the camera pipeline
final cameraPipelineProvider = FutureProvider<CameraPipelineService>((ref) async {
  final cactusService = await ref.watch(cactusServiceProvider.future);
  final allergenDb = await ref.watch(allergenDbProvider.future);

  final pipeline = CameraPipelineService(
    frameProcessor: FrameProcessor(),
    cactusService: cactusService,
    allergenDb: allergenDb,
  );

  // Sync active allergens from profileProvider
  final profileState = ref.read(profileProvider);
  if (profileState.activeProfile != null) {
    pipeline.updateActiveAllergens(profileState.activeProfile!.activeAllergenCodes);
  }

  // Listen to profile changes
  ref.listen(profileProvider, (previous, next) {
    if (next.activeProfile != null) {
      pipeline.updateActiveAllergens(next.activeProfile!.activeAllergenCodes);
    }
  });

  // Forward evaluation results to scanningProvider
  pipeline.resultsStream.listen((result) {
    ref.read(scanningProvider.notifier).updateEvaluationResult(result);
  });

  // Forward blur/holding-steady states to scanningProvider
  pipeline.stateStream.listen((state) {
    if (state == CameraScanState.holdingSteady) {
      ref.read(scanningProvider.notifier).setBlurNudge('Hold steady for clear label scan');
    } else if (state == CameraScanState.scanning) {
      ref.read(scanningProvider.notifier).setBlurNudge(null);
    }
  });

  ref.onDispose(() {
    pipeline.dispose();
  });

  return pipeline;
});

