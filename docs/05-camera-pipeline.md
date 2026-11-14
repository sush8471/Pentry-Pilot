# 05 — Camera Pipeline

## Overview

The camera pipeline is the first stage of the Pantry Pilot processing chain. Its job is to:
1. Capture live YUV frames from the rear camera
2. Throttle the frame rate to match the AI pipeline capacity
3. Crop to the region of interest (the label area)
4. Gate on image sharpness before spending NPU resources

A poorly implemented camera pipeline is the most common cause of:
- UI jank (processing on the main thread)
- Memory pressure (queuing frames instead of dropping)
- Battery drain (processing more frames than the pipeline can handle)
- Thermal throttling (sustained 100% CPU usage)

---

## Camera Configuration

```dart
// Resolution: medium (720p) for most devices
// Low-end fallback: low (480p) if memory pressure detected
CameraController(
  cameras.first,                    // Rear camera
  ResolutionPreset.medium,          // 1280x720 — balance of OCR quality vs memory
  enableAudio: false,               // Audio not needed; saves power
  imageFormatGroup: ImageFormatGroup.yuv420, // Native Android format
)
```

**Why not `ResolutionPreset.high` or `max`?**
At 1080p, each YUV frame is ~3.1MB. At 720p it's ~1.4MB. The pipeline processes ~8 frames/second → at 1080p that's 25MB/s of raw allocations, causing constant GC pressure. 720p provides sufficient OCR resolution for typical ingredient label fonts (8pt+).

**Adaptive resolution:** On devices with <3GB RAM, automatically downsample to `ResolutionPreset.low` (480p) at runtime.

---

## Drop-Latest Backpressure Pattern

The camera sensor delivers frames at 30fps. Our AI pipeline takes ~100ms per frame → maximum theoretical throughput is 10fps. If we try to process every frame, we build up a queue → growing memory → OOM → crash.

**Solution: Drop-Latest, never queue.**

```dart
bool _isProcessingFrame = false;

void _onCameraImage(CameraImage image) {
  // If pipeline is busy, silently drop this frame
  if (_isProcessingFrame) return;

  _isProcessingFrame = true;
  _processFrame(image).whenComplete(() {
    _isProcessingFrame = false;
  });
}
```

This guarantees:
- Maximum memory: 1 frame in-flight at all times
- No latency buildup: each processed frame is always the most recent
- Smooth HUD: stale frames never cause old results to flash on screen

---

## ROI (Region of Interest) Sampling

When scanning a food label, the user centres it in the viewfinder. We exploit this by cropping to the central 70% of the frame, reducing the pixel area sent to Mirage by ~50%, which proportionally reduces OCR latency.

```dart
Uint8List _cropROI(CameraImage image, {double cropFactor = 0.70}) {
  // YUV_420_888: plane[0] is Y (luma), planes[1] and [2] are UV
  final yPlane = image.planes[0];
  final int srcWidth  = image.width;
  final int srcHeight = image.height;

  // Calculate crop bounds (centred)
  final int cropW = (srcWidth  * cropFactor).toInt();
  final int cropH = (srcHeight * cropFactor).toInt();
  final int offsetX = (srcWidth  - cropW) ~/ 2;
  final int offsetY = (srcHeight - cropH) ~/ 2;

  // Extract Y plane rows within crop bounds
  // (UV planes follow at half resolution — handled by Mirage internally)
  final croppedY = Uint8List(cropW * cropH);
  for (int row = 0; row < cropH; row++) {
    final srcRow = (offsetY + row) * yPlane.bytesPerRow + offsetX;
    croppedY.setRange(row * cropW, (row + 1) * cropW,
                      yPlane.bytes, srcRow);
  }
  return croppedY;
}
```

---

## Sharpness Gate: Laplacian Variance

Sending a blurry frame to Mirage wastes ~74ms of NPU time and returns garbage OCR results. The sharpness gate costs only ~1ms on the CPU and rejects blurry frames early.

**Laplacian variance** measures image sharpness by computing the variance of the Laplacian filter response. A focused image has high variance (sharp edges); a blurry one has low variance (smooth gradients).

```dart
double _computeSharpness(Uint8List grayBytes, int width, int height) {
  // 3×3 Laplacian kernel: [0,1,0; 1,-4,1; 0,1,0]
  double sum = 0.0;
  double sumSq = 0.0;
  int count = 0;

  for (int y = 1; y < height - 1; y++) {
    for (int x = 1; x < width - 1; x++) {
      final int idx = y * width + x;
      final int laplacian =
          -4 * grayBytes[idx]
          + grayBytes[idx - 1]       // left
          + grayBytes[idx + 1]       // right
          + grayBytes[idx - width]   // top
          + grayBytes[idx + width];  // bottom

      sum   += laplacian;
      sumSq += laplacian * laplacian;
      count++;
    }
  }

  final double mean     = sum / count;
  final double variance = (sumSq / count) - (mean * mean);
  return variance;
}

// Usage:
// If variance < 120.0 → reject frame, show "Hold steady" nudge
static const double _sharpnessThreshold = 120.0;
```

**Threshold calibration:**
- Clear, well-lit label: variance ~300–800
- Mildly blurry: variance ~80–150
- Very blurry / in motion: variance ~10–50
- Threshold of 120 rejects clearly blurry frames while accepting slightly imperfect ones

---

## Isolate Architecture

Camera frame processing MUST NOT happen on the main UI isolate. Here's the threading model:

```
Main Isolate (UI Thread)
├── Widget rendering @ 60fps
├── CameraPreview (native HW composited)
├── startImageStream() callback — receives CameraImage
│       └── Checks _isProcessingFrame flag
│       └── If not busy: extracts Uint8List from planes
│       └── Sends via SendPort to Worker Isolate
└── Receives AllergenResult from Worker Isolate → setState()

Worker Isolate (Background Thread)
├── Receives Uint8List frame via ReceivePort
├── ROI crop
├── Sharpness gate
├── [If sharp] → cactusFFI.mirageOcr()  [calls libcactus.so on NPU]
├── Text normalizer
├── SQLite synonym pre-filter
├── [If needed] → cactusFFI.needleComplete()
├── Allergen resolver
└── Sends AllergenResult back to Main Isolate via SendPort
```

**Key:** `TransferableTypedData` is used to pass the `Uint8List` from main → worker without copying the buffer in memory. This avoids the ~1.4MB per-frame allocation overhead that would otherwise cause GC storms.

---

## Frame Sampling Rate by Device Tier

| Device Tier | Chipset Examples | Sampling Rate | Resolution |
|---|---|---|---|
| Flagship | Snapdragon 8 Gen 3+ | 10fps | 720p (medium) |
| Mid-range | Snapdragon 7xx | 8fps | 720p (medium) |
| Low-end | Snapdragon 4xx | 4fps | 480p (low) |

Device tier is detected at startup via `DeviceInfoPlugin` by checking the SoC model string. The sampling rate is baked into the `_isProcessingFrame` debounce: a minimum time gap is enforced between frames even if the pipeline finishes faster.

```dart
// Minimum gap between frames to avoid taxing low-end SoCs
static const Map<DeviceTier, Duration> _minFrameGap = {
  DeviceTier.flagship: Duration(milliseconds: 100),
  DeviceTier.midRange: Duration(milliseconds: 125),
  DeviceTier.lowEnd:   Duration(milliseconds: 250),
};
```

---

## Thermal State Management

Android exposes thermal status via the `PowerManager` Thermal API (API 29+). We monitor this and dynamically back off frame rate when the device heats up:

```dart
// Listen to Android thermal status (via platform channel)
// THERMAL_STATUS_NONE    → normal operation
// THERMAL_STATUS_LIGHT   → reduce to 6fps
// THERMAL_STATUS_MODERATE → reduce to 4fps + show "Device cooling down"
// THERMAL_STATUS_SEVERE  → pause scanning + full "Cooling down" overlay
// THERMAL_STATUS_CRITICAL → emergency stop
```

This prevents the app from causing thermal throttling that slows down other device functions and degrades user experience.

