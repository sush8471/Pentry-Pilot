import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/allergen_finding.dart';
import '../services/cactus_service.dart';

class ScanningState {
  final List<AllergenFinding> findings;
  final String overallVerdict;
  final bool isScanning;
  final bool showDebugOverlay;
  final String? blurNudgeMessage;
  final int ocrLatencyMs;
  final int dbLatencyMs;
  final int needleLatencyMs;
  final int totalLatencyMs;
  final int dbHitCount;
  final int needleTokenCount;

  const ScanningState({
    this.findings = const [],
    this.overallVerdict = 'SAFE',
    this.isScanning = true,
    this.showDebugOverlay = false,
    this.blurNudgeMessage,
    this.ocrLatencyMs = 0,
    this.dbLatencyMs = 0,
    this.needleLatencyMs = 0,
    this.totalLatencyMs = 0,
    this.dbHitCount = 0,
    this.needleTokenCount = 0,
  });

  ScanningState copyWith({
    List<AllergenFinding>? findings,
    String? overallVerdict,
    bool? isScanning,
    bool? showDebugOverlay,
    String? blurNudgeMessage,
    bool clearBlurNudge = false,
    int? ocrLatencyMs,
    int? dbLatencyMs,
    int? needleLatencyMs,
    int? totalLatencyMs,
    int? dbHitCount,
    int? needleTokenCount,
  }) {
    return ScanningState(
      findings: findings ?? this.findings,
      overallVerdict: overallVerdict ?? this.overallVerdict,
      isScanning: isScanning ?? this.isScanning,
      showDebugOverlay: showDebugOverlay ?? this.showDebugOverlay,
      blurNudgeMessage: clearBlurNudge ? null : (blurNudgeMessage ?? this.blurNudgeMessage),
      ocrLatencyMs: ocrLatencyMs ?? this.ocrLatencyMs,
      dbLatencyMs: dbLatencyMs ?? this.dbLatencyMs,
      needleLatencyMs: needleLatencyMs ?? this.needleLatencyMs,
      totalLatencyMs: totalLatencyMs ?? this.totalLatencyMs,
      dbHitCount: dbHitCount ?? this.dbHitCount,
      needleTokenCount: needleTokenCount ?? this.needleTokenCount,
    );
  }
}

class ScanningNotifier extends StateNotifier<ScanningState> {
  ScanningNotifier() : super(const ScanningState());

  void updateEvaluationResult(CactusEvaluationResult result) {
    if (!state.isScanning) return;
    state = state.copyWith(
      findings: result.findings,
      overallVerdict: result.overallVerdict,
      ocrLatencyMs: result.ocrLatencyMs,
      dbLatencyMs: result.dbLatencyMs,
      needleLatencyMs: result.needleLatencyMs,
      totalLatencyMs: result.totalLatencyMs,
      dbHitCount: result.dbHitCount,
      needleTokenCount: result.needleTokenCount,
      clearBlurNudge: true,
    );
  }

  void setBlurNudge(String? message) {
    if (message == null) {
      state = state.copyWith(clearBlurNudge: true);
    } else {
      state = state.copyWith(blurNudgeMessage: message);
    }
  }

  void toggleScanning() {
    state = state.copyWith(isScanning: !state.isScanning);
  }

  void setScanning(bool scanning) {
    state = state.copyWith(isScanning: scanning);
  }

  void toggleDebugOverlay() {
    state = state.copyWith(showDebugOverlay: !state.showDebugOverlay);
  }

  void clearFindings() {
    state = state.copyWith(
      findings: const [],
      overallVerdict: 'SAFE',
      clearBlurNudge: true,
    );
  }
}

final scanningProvider = StateNotifierProvider<ScanningNotifier, ScanningState>((ref) {
  return ScanningNotifier();
});

