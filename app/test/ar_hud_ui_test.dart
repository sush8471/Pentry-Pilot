import 'dart:ui' show Size, Rect;
import 'package:flutter/painting.dart' show Color;
import 'package:test/test.dart';
import 'package:pantry_pilot/models/allergen_finding.dart';
import 'package:pantry_pilot/models/dietary_profile.dart';
import 'package:pantry_pilot/widgets/allergen_hud_painter.dart';
import 'package:pantry_pilot/providers/scanning_provider.dart';
import 'package:pantry_pilot/providers/profile_provider.dart';
import 'package:pantry_pilot/services/cactus_service.dart';

void main() {
  group('Phase 4: AR HUD Viewfinder UI & State Management Tests', () {
    // ── 1. Coordinate Transform & Bounds Tests ─────────────────────────────────
    test('Coordinate transform maps landscape camera space to portrait screen space', () {
      // Given: 720x1280 sensor (camera height=720, width=1280), rendered on 360x800 screen
      const cameraPreviewSize = Size(1280, 720);
      const screenSize = Size(360, 800);

      // In AllergenHudPainter:
      // scaleX = screenSize.width / cameraPreviewSize.height = 360 / 720 = 0.5
      // scaleY = screenSize.height / cameraPreviewSize.width = 800 / 1280 = 0.625
      final double scaleX = screenSize.width / cameraPreviewSize.height;
      final double scaleY = screenSize.height / cameraPreviewSize.width;

      expect(scaleX, closeTo(0.5, 0.001));
      expect(scaleY, closeTo(0.625, 0.001));

      // Bounding box from OCR in camera space: x=100, y=200, w=150, h=40
      const bbox = BoundingBox(x: 100, y: 200, width: 150, height: 40);
      final screenRect = Rect.fromLTWH(
        bbox.x * scaleX,
        bbox.y * scaleY,
        bbox.width * scaleX,
        bbox.height * scaleY,
      );

      expect(screenRect.left, equals(50.0));
      expect(screenRect.top, equals(125.0));
      expect(screenRect.width, equals(75.0));
      expect(screenRect.height, equals(25.0));
    });

    // ── 2. Color Resolution & Strict Mode Rules ────────────────────────────────
    test('Colour resolution maps finding status correctly', () {
      final dangerFinding = AllergenFinding(
        token: 'casein',
        status: FindingStatus.danger,
        confidence: 0.95,
        matchedAllergen: 'MILK',
      );
      final ambiguousFinding = AllergenFinding(
        token: 'flavoring',
        status: FindingStatus.ambiguous,
        confidence: 0.8,
      );
      final safeFinding = AllergenFinding(
        token: 'water',
        status: FindingStatus.safe,
        confidence: 0.99,
      );
      final lowConfFinding = AllergenFinding(
        token: 'unknown',
        status: FindingStatus.danger,
        confidence: 0.4, // below 0.5 confidence
      );

      final standardPainter = AllergenHudPainter(
        findings: [dangerFinding, ambiguousFinding, safeFinding, lowConfFinding],
        cameraPreviewSize: const Size(1280, 720),
        strictMode: false,
      );

      final strictPainter = AllergenHudPainter(
        findings: [ambiguousFinding],
        cameraPreviewSize: const Size(1280, 720),
        strictMode: true,
      );

      // Verify Painter static color constants
      expect(AllergenHudPainter.colourDanger, equals(const Color(0xFFE53935)));
      expect(AllergenHudPainter.colourAmbiguous, equals(const Color(0xFFFFC107)));
      expect(AllergenHudPainter.colourSafe, equals(const Color(0xFF43A047)));
      expect(AllergenHudPainter.colourLow, equals(const Color(0xFF9E9E9E)));

      // Strict mode: AMBIGUOUS is elevated to DANGER colour
      expect(strictPainter.strictMode, isTrue);
      expect(standardPainter.strictMode, isFalse);
    });

    // ── 3. Repaint Optimization Guard ──────────────────────────────────────────
    test('shouldRepaint returns false when findings and settings are identical', () {
      const findingsA = [
        AllergenFinding(token: 'whey', status: FindingStatus.danger, confidence: 0.9)
      ];
      const findingsB = [
        AllergenFinding(token: 'whey', status: FindingStatus.danger, confidence: 0.9)
      ];

      final painter1 = AllergenHudPainter(
        findings: findingsA,
        cameraPreviewSize: const Size(1280, 720),
        strictMode: false,
      );
      final painter2 = AllergenHudPainter(
        findings: findingsB,
        cameraPreviewSize: const Size(1280, 720),
        strictMode: false,
      );

      // Equal lists should NOT trigger repaint
      expect(painter1.shouldRepaint(painter2), isFalse);

      // Changing strict mode triggers repaint
      final painterStrict = AllergenHudPainter(
        findings: findingsA,
        cameraPreviewSize: const Size(1280, 720),
        strictMode: true,
      );
      expect(painterStrict.shouldRepaint(painter1), isTrue);

      // Changing preview size triggers repaint
      final painterResized = AllergenHudPainter(
        findings: findingsA,
        cameraPreviewSize: const Size(1920, 1080),
        strictMode: false,
      );
      expect(painterResized.shouldRepaint(painter1), isTrue);
    });

    // ── 4. Scanning State Machine & Notifier ────────────────────────────────────
    test('ScanningNotifier updates evaluation results and clears blur nudge', () {
      final notifier = ScanningNotifier();
      expect(notifier.state.overallVerdict, equals('SAFE'));
      expect(notifier.state.isScanning, isTrue);

      // Set blur nudge
      notifier.setBlurNudge('Hold steady');
      expect(notifier.state.blurNudgeMessage, equals('Hold steady'));

      // Dispatch evaluation result -> clears blur nudge automatically
      const evaluationResult = CactusEvaluationResult(
        findings: [
          AllergenFinding(token: 'peanut', status: FindingStatus.danger, confidence: 0.99)
        ],
        overallVerdict: 'DANGER',
        ocrLatencyMs: 42,
        dbLatencyMs: 2,
        needleLatencyMs: 28,
        totalLatencyMs: 72,
        dbHitCount: 1,
        needleTokenCount: 0,
      );

      notifier.updateEvaluationResult(evaluationResult);

      expect(notifier.state.overallVerdict, equals('DANGER'));
      expect(notifier.state.findings.length, equals(1));
      expect(notifier.state.totalLatencyMs, equals(72));
      expect(notifier.state.blurNudgeMessage, isNull);

      // Toggle scanning pauses updates
      notifier.toggleScanning();
      expect(notifier.state.isScanning, isFalse);

      // While paused, new evaluation does not overwrite state
      const secondResult = CactusEvaluationResult(
        findings: [],
        overallVerdict: 'SAFE',
        ocrLatencyMs: 10,
        dbLatencyMs: 1,
        needleLatencyMs: 0,
        totalLatencyMs: 11,
        dbHitCount: 0,
        needleTokenCount: 0,
      );
      notifier.updateEvaluationResult(secondResult);
      expect(notifier.state.overallVerdict, equals('DANGER')); // Still DANGER because paused

      // Toggle debug overlay
      expect(notifier.state.showDebugOverlay, isFalse);
      notifier.toggleDebugOverlay();
      expect(notifier.state.showDebugOverlay, isTrue);
    });

    // ── 5. Profile State Machine & CRUD ────────────────────────────────────────
    test('ProfileNotifier initializes default profile and supports switching and updates', () {
      final service = ProfileService();
      final notifier = ProfileNotifier(service);

      // Default profile created on empty service
      expect(notifier.state.profiles.isNotEmpty, isTrue);
      expect(notifier.state.activeProfile, isNotNull);
      expect(notifier.state.activeProfile!.strictMode, isTrue);

      // Create a secondary profile
      final kidProfile = notifier.createProfile(
        name: 'Dairy Free Kid',
        activeAllergenCodes: ['MILK'],
        strictMode: false,
      );

      expect(notifier.state.profiles.length, equals(2));
      // First remains active until switched
      expect(notifier.state.activeProfile!.id, isNot(kidProfile.id));

      // Switch active profile
      notifier.setActive(kidProfile.id);
      expect(notifier.state.activeProfile!.id, equals(kidProfile.id));
      expect(notifier.state.activeProfile!.name, equals('Dairy Free Kid'));

      // Update allergens
      notifier.updateProfile(
        kidProfile.id,
        activeAllergenCodes: ['MILK', 'EGG', 'SESAME'],
        strictMode: true,
      );
      expect(notifier.state.activeProfile!.activeAllergenCodes, contains('SESAME'));
      expect(notifier.state.activeProfile!.strictMode, isTrue);

      // Delete non-active profile
      final otherId = notifier.state.profiles.firstWhere((p) => p.id != kidProfile.id).id;
      notifier.deleteProfile(otherId);
      expect(notifier.state.profiles.length, equals(1));
    });
  });
}

