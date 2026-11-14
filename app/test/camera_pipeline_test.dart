import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:pantry_pilot/services/frame_processor.dart';

void main() {
  group('Phase 2: Camera Pipeline & Frame Processing Unit Tests', () {
    late FrameProcessor processor;

    setUp(() {
      processor = FrameProcessor(
        tier: DeviceTier.midRange, // 8 FPS, 125ms interval
        sharpnessThreshold: 120.0,
        roiCropFactor: 0.70,
      );
    });

    test('Drop-latest backpressure skips frame if previous is still busy', () {
      expect(processor.shouldSampleFrame(1000), isTrue);

      processor.markBusy();
      // Even if sufficient time elapsed, busy state drops frame
      expect(processor.shouldSampleFrame(1200), isFalse);

      processor.markIdle(1200);
      // Wait interval not yet met
      expect(processor.shouldSampleFrame(1250), isFalse);
      // Wait interval met (1200 + 125ms = 1325ms)
      expect(processor.shouldSampleFrame(1330), isTrue);
    });

    test('Device tier rate limiting enforces expected sampling intervals', () {
      final flagship = FrameProcessor(tier: DeviceTier.flagship); // 100ms
      final lowEnd = FrameProcessor(tier: DeviceTier.lowEnd);     // 250ms

      flagship.markIdle(0);
      lowEnd.markIdle(0);

      // At 110ms: flagship permits frame, low-end drops
      expect(flagship.shouldSampleFrame(110), isTrue);
      expect(lowEnd.shouldSampleFrame(110), isFalse);

      // At 260ms: low-end permits frame
      expect(lowEnd.shouldSampleFrame(260), isTrue);
    });

    test('Laplacian sharpness gate rejects blurry frames and passes sharp frames', () {
      const int w = 100;
      const int h = 100;

      // 1. Blurry / Uniform Frame (solid gray or gentle gradient) -> Variance near zero
      final blurryBytes = Uint8List(w * h);
      for (int i = 0; i < blurryBytes.length; i++) {
        blurryBytes[i] = (i % 5).clamp(0, 255);
      }
      final blurryResult = processor.evaluateSharpness(blurryBytes, w, h);
      expect(blurryResult.isSharp, isFalse);
      expect(blurryResult.score, lessThan(120.0));

      // 2. Sharp Frame with high frequency contrast (alternating black/white edges)
      final sharpBytes = Uint8List(w * h);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          sharpBytes[y * w + x] = ((x ~/ 4) % 2 == 0) ? 255 : 0;
        }
      }
      final sharpResult = processor.evaluateSharpness(sharpBytes, w, h);
      expect(sharpResult.isSharp, isTrue);
      expect(sharpResult.score, greaterThan(120.0));
    });

    test('ROI center 70% cropping correctly dimensions cropped buffer', () {
      const int srcW = 200;
      const int srcH = 100;
      const int bytesPerRow = 200;

      final srcYPlane = Uint8List(srcW * srcH);
      // Fill with sharp pattern
      for (int y = 0; y < srcH; y++) {
        for (int x = 0; x < srcW; x++) {
          srcYPlane[y * srcW + x] = (x % 2 == 0) ? 255 : 0;
        }
      }

      final payload = processor.cropAndFilterFrame(
        yPlaneBytes: srcYPlane,
        srcWidth: srcW,
        srcHeight: srcH,
        bytesPerRow: bytesPerRow,
      );

      expect(payload, isNotNull);
      // 70% of 200 = 140, 70% of 100 = 70
      expect(payload!.width, equals(140));
      expect(payload.height, equals(70));
      expect(payload.croppedYBytes.length, equals(140 * 70));
      expect(payload.cropOffsetX, equals((200 - 140) ~/ 2));
      expect(payload.cropOffsetY, equals((100 - 70) ~/ 2));
    });
  });
}

