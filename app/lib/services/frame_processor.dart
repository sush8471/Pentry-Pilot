import 'dart:typed_data';

/// Sharpness evaluation result from Laplacian kernel
class SharpnessResult {
  final double score;
  final bool isSharp;

  const SharpnessResult({
    required this.score,
    required this.isSharp,
  });
}

/// Structured payload containing preprocessed frame data ready for Mirage OCR
class ProcessedFramePayload {
  final Uint8List croppedYBytes;
  final int width;
  final int height;
  final double sharpnessScore;
  final int srcWidth;
  final int srcHeight;
  final int cropOffsetX;
  final int cropOffsetY;

  const ProcessedFramePayload({
    required this.croppedYBytes,
    required this.width,
    required this.height,
    required this.sharpnessScore,
    required this.srcWidth,
    required this.srcHeight,
    required this.cropOffsetX,
    required this.cropOffsetY,
  });
}

/// Device performance tiers for adaptive camera throttling
enum DeviceTier {
  flagship(targetFps: 10, minFrameIntervalMs: 100),
  midRange(targetFps: 8, minFrameIntervalMs: 125),
  lowEnd(targetFps: 4, minFrameIntervalMs: 250);

  final int targetFps;
  final int minFrameIntervalMs;

  const DeviceTier({
    required this.targetFps,
    required this.minFrameIntervalMs,
  });
}

/// Device thermal throttling states adhering to Android PowerManager.ThermalStatus
enum ThermalStatus {
  none,      // Normal operating conditions
  light,     // Slight warming; throttle to 6fps
  moderate,  // Moderate heating; throttle to 4fps
  severe,    // High temperature; throttle to 1fps or pause
  critical;  // Emergency shutdown/cool-down
}

/// Core frame processor handling:
/// 1. Drop-latest backpressure guard
/// 2. Adaptive interval rate limiting by device tier
/// 3. Dynamic thermal throttling back-off
/// 4. Center ROI 70% cropping
/// 5. 3x3 Laplacian variance sharpness filtering
/// 6. Battery profiling & power draw modeling
class FrameProcessor {
  final DeviceTier tier;
  final double sharpnessThreshold;
  final double roiCropFactor;

  bool _isProcessing = false;
  int _lastProcessedTimestamp = 0;
  ThermalStatus _thermalStatus = ThermalStatus.none;

  bool get isProcessing => _isProcessing;
  ThermalStatus get thermalStatus => _thermalStatus;

  FrameProcessor({
    this.tier = DeviceTier.midRange,
    this.sharpnessThreshold = 120.0,
    this.roiCropFactor = 0.70,
  });

  /// Updates thermal status from platform monitor
  void updateThermalStatus(ThermalStatus status) {
    _thermalStatus = status;
  }

  /// Active frame interval taking into account device tier and thermal throttling
  int get activeFrameIntervalMs {
    switch (_thermalStatus) {
      case ThermalStatus.critical:
        return 60000; // Emergency halt (pause)
      case ThermalStatus.severe:
        return 1000;  // 1fps emergency cool-down
      case ThermalStatus.moderate:
        return 250;   // Throttled to 4fps
      case ThermalStatus.light:
        return 166;   // Throttled to 6fps
      case ThermalStatus.none:
        return tier.minFrameIntervalMs;
    }
  }

  /// Effective target FPS under current thermal conditions
  double get effectiveTargetFps => 1000.0 / activeFrameIntervalMs;

  /// Check whether an incoming frame should be sampled or dropped immediately
  bool shouldSampleFrame(int currentTimestampMs) {
    if (_isProcessing) return false;
    if (_thermalStatus == ThermalStatus.critical) return false;
    final elapsed = currentTimestampMs - _lastProcessedTimestamp;
    return elapsed >= activeFrameIntervalMs;
  }

  /// Estimates hourly battery drain percentage for continuous scanning
  ///
  /// Assumptions:
  /// - Standard battery capacity: 5000mAh (Flagship/Low-end), 4385mAh (Mid-range)
  /// - Screen at 50% brightness + camera hardware: ~280-320mA
  /// - NPU inference per frame: ~15-22mA
  /// - CPU fallback inference per frame: ~85mA
  double estimateHourlyBatteryDrainPercent({
    DeviceTier? customTier,
    ThermalStatus? customThermal,
  }) {
    final t = customTier ?? tier;
    final therm = customThermal ?? _thermalStatus;

    if (therm == ThermalStatus.critical) {
      return 1.2; // Idle background drain only (~60mA on 5000mAh)
    }

    final double fps;
    switch (therm) {
      case ThermalStatus.critical:
        fps = 0.0;
        break;
      case ThermalStatus.severe:
        fps = 1.0;
        break;
      case ThermalStatus.moderate:
        fps = 4.0;
        break;
      case ThermalStatus.light:
        fps = 6.0;
        break;
      case ThermalStatus.none:
        fps = t.targetFps.toDouble();
        break;
    }

    final double batteryCapacityMah;
    final double baseDrawMa;
    final double drawPerFpsMa;

    switch (t) {
      case DeviceTier.flagship:
        batteryCapacityMah = 5000.0;
        baseDrawMa = 280.0; // Display 50% + ISP
        drawPerFpsMa = 15.0; // Dedicated NPU
        break;
      case DeviceTier.midRange:
        batteryCapacityMah = 4385.0;
        baseDrawMa = 300.0;
        drawPerFpsMa = 20.0; // Efficient NPU/DSP
        break;
      case DeviceTier.lowEnd:
        batteryCapacityMah = 5000.0;
        baseDrawMa = 330.0;
        drawPerFpsMa = 70.0; // CPU fallback
        break;
    }

    final double totalCurrentMa = baseDrawMa + (fps * drawPerFpsMa);
    final double hourlyDrain = (totalCurrentMa / batteryCapacityMah) * 100.0;
    return double.parse(hourlyDrain.toStringAsFixed(1));
  }

  /// Mark the pipeline as busy
  void markBusy() {
    _isProcessing = true;
  }

  /// Mark the pipeline as ready for the next frame
  void markIdle(int currentTimestampMs) {
    _lastProcessedTimestamp = currentTimestampMs;
    _isProcessing = false;
  }

  /// Evaluates image sharpness using 3x3 Laplacian kernel variance on Y-plane (luma)
  SharpnessResult evaluateSharpness(Uint8List grayBytes, int width, int height) {
    if (width < 3 || height < 3) {
      return const SharpnessResult(score: 0.0, isSharp: false);
    }

    double sum = 0.0;
    double sumSq = 0.0;
    int count = 0;

    // Convolve with 3x3 Laplacian filter [0, 1, 0; 1, -4, 1; 0, 1, 0]
    for (int y = 1; y < height - 1; y++) {
      final int rowIdx = y * width;
      for (int x = 1; x < width - 1; x++) {
        final int idx = rowIdx + x;
        final int laplacian = -4 * grayBytes[idx] +
            grayBytes[idx - 1] +
            grayBytes[idx + 1] +
            grayBytes[idx - width] +
            grayBytes[idx + width];

        sum += laplacian;
        sumSq += laplacian * laplacian;
        count++;
      }
    }

    if (count == 0) return const SharpnessResult(score: 0.0, isSharp: false);

    final double mean = sum / count;
    final double variance = (sumSq / count) - (mean * mean);
    final bool isSharp = variance >= sharpnessThreshold;

    return SharpnessResult(score: variance, isSharp: isSharp);
  }

  /// Crops the center region of interest from the raw Y plane
  ProcessedFramePayload? cropAndFilterFrame({
    required Uint8List yPlaneBytes,
    required int srcWidth,
    required int srcHeight,
    required int bytesPerRow,
  }) {
    final int cropW = (srcWidth * roiCropFactor).toInt();
    final int cropH = (srcHeight * roiCropFactor).toInt();
    final int offsetX = (srcWidth - cropW) ~/ 2;
    final int offsetY = (srcHeight - cropH) ~/ 2;

    final Uint8List croppedY = Uint8List(cropW * cropH);

    for (int row = 0; row < cropH; row++) {
      final int srcRowStart = (offsetY + row) * bytesPerRow + offsetX;
      final int destRowStart = row * cropW;
      croppedY.setRange(
        destRowStart,
        destRowStart + cropW,
        yPlaneBytes,
        srcRowStart,
      );
    }

    final sharpness = evaluateSharpness(croppedY, cropW, cropH);

    if (!sharpness.isSharp) {
      return null; // Rejected by sharpness gate
    }

    return ProcessedFramePayload(
      croppedYBytes: croppedY,
      width: cropW,
      height: cropH,
      sharpnessScore: sharpness.score,
      srcWidth: srcWidth,
      srcHeight: srcHeight,
      cropOffsetX: offsetX,
      cropOffsetY: offsetY,
    );
  }
}

