# 06 — AR HUD Rendering

## Design Philosophy

The HUD is a pure information overlay. It should be:
- **Invisible when nothing is detected** — no UI chrome, just the camera feed
- **Instant on verdict change** — results appear on the vsync immediately after Needle returns
- **Non-intrusive** — gestures pass through the overlay to the camera preview
- **Readable at arm's length** — labels are legible on a 5" screen in sunlight

---

## Stack Layout

```dart
Scaffold(
  body: Stack(
    fit: StackFit.expand,
    children: [
      // Layer 1: Camera feed (hardware composited by Android SurfaceView)
      CameraPreview(_cameraController),

      // Layer 2: Allergen highlight overlay — IgnorePointer lets taps through
      IgnorePointer(
        child: RepaintBoundary(          // Isolates repaints from camera layer
          child: CustomPaint(
            painter: AllergenHudPainter(
              findings: _findings,
              cameraPreviewSize: _controller.value.previewSize!,
            ),
          ),
        ),
      ),

      // Layer 3: Status badge (bottom-centre, always visible)
      Positioned(
        bottom: 48, left: 16, right: 16,
        child: VerdictBadge(findings: _findings),
      ),

      // Layer 4: Contextual nudges (blur warning, torch suggestion)
      if (_showNudge)
        BlurNudgeOverlay(message: _nudgeMessage),
    ],
  ),
)
```

**Why `RepaintBoundary` around the painter?**
Flutter's render tree normally propagates invalidation up to the nearest `RepaintBoundary`. Without it, every `setState()` in the parent widget would trigger a repaint of the entire `Stack` including the camera preview — causing frame drops. With `RepaintBoundary`, only the `CustomPaint` layer repaints.

---

## Coordinate Space Transformation

The camera sensor reports bounding boxes in **camera-preview space** (e.g., 1280×720 for a 720p stream). The screen renders in **logical pixel space** (e.g., 393×852 on a Pixel 8). The transform accounts for:

1. The camera preview's native orientation (landscape sensor, portrait screen)
2. The aspect ratio crop (the camera preview is typically `BoxFit.cover`)

```dart
// In AllergenHudPainter.paint():
@override
void paint(Canvas canvas, Size screenSize) {
  // Camera sensor is landscape (width > height), screen is portrait
  // After rotation: camera "width" maps to screen "height"
  final double scaleX = screenSize.width  / cameraPreviewSize.height;
  final double scaleY = screenSize.height / cameraPreviewSize.width;

  for (final finding in findings) {
    final bbox = finding.boundingBox;
    if (bbox == null) continue;

    // Transform from camera-space to screen-space
    final Rect screenRect = Rect.fromLTWH(
      bbox.x * scaleX,
      bbox.y * scaleY,
      bbox.width  * scaleX,
      bbox.height * scaleY,
    );

    _paintFinding(canvas, screenRect, finding);
  }
}
```

> **Note on device rotation:** The app is locked to portrait orientation (`preferredOrientations: [DeviceOrientation.portraitUp]`) to simplify the coordinate transform. Landscape support can be added in v2.

---

## Colour Coding System

| Status | Colour | Hex | Usage |
|---|---|---|---|
| DANGER | Red | `#E53935` | Confirmed allergen match (confidence ≥ 0.8) |
| AMBIGUOUS | Amber | `#FFC107` | Possible alias, context-dependent, or unknown |
| SAFE | Green | `#43A047` | No allergen match found |
| LOW_CONFIDENCE | Grey | `#9E9E9E` | Needle confidence < 0.5; shown faintly |

**Strict mode:** When the user enables "Strict mode" in their profile, AMBIGUOUS tokens are rendered in Red (treated as DANGER). The colour is overridden in the painter based on the profile setting.

---

## `AllergenHudPainter` — Full Implementation

```dart
class AllergenHudPainter extends CustomPainter {
  final List<AllergenFinding> findings;
  final Size cameraPreviewSize;
  final bool strictMode;

  static const _colourDanger    = Color(0xFFE53935);
  static const _colourAmbiguous = Color(0xFFFFC107);
  static const _colourSafe      = Color(0xFF43A047);
  static const _colourLow       = Color(0xFF9E9E9E);

  const AllergenHudPainter({
    required this.findings,
    required this.cameraPreviewSize,
    this.strictMode = false,
  });

  @override
  void paint(Canvas canvas, Size screenSize) {
    final double scaleX = screenSize.width  / cameraPreviewSize.height;
    final double scaleY = screenSize.height / cameraPreviewSize.width;

    for (final finding in findings) {
      final bbox = finding.boundingBox;
      if (bbox == null) continue;
      if (finding.confidence < 0.3) continue; // Skip very low confidence

      final colour = _resolveColour(finding);
      final rect = Rect.fromLTWH(
        bbox.x * scaleX, bbox.y * scaleY,
        bbox.width * scaleX, bbox.height * scaleY,
      );

      _paintHighlight(canvas, rect, colour, finding.confidence);
      _paintLabel(canvas, rect, finding.token, colour);
    }
  }

  void _paintHighlight(Canvas canvas, Rect rect, Color colour, double alpha) {
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));

    // Semi-transparent fill
    canvas.drawRRect(rrect, Paint()
      ..color = colour.withOpacity(0.25 * alpha));

    // Solid border
    canvas.drawRRect(rrect, Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8);

    // Corner accent brackets (HUD style)
    _paintCornerBrackets(canvas, rect, colour);
  }

  void _paintCornerBrackets(Canvas canvas, Rect rect, Color colour) {
    const double len = 8.0;
    final paint = Paint()..color = colour..strokeWidth = 2.0;
    // 4 corners × 2 lines each = 8 drawLine calls
    final corners = [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight];
    for (final corner in corners) {
      final dx = corner == rect.topLeft || corner == rect.bottomLeft ? len : -len;
      final dy = corner == rect.topLeft || corner == rect.topRight ? len : -len;
      canvas.drawLine(corner, corner.translate(dx, 0), paint);
      canvas.drawLine(corner, corner.translate(0, dy), paint);
    }
  }

  void _paintLabel(Canvas canvas, Rect rect, String text, Color colour) {
    final tp = TextPainter(
      text: TextSpan(
        text: ' ${text.toUpperCase()} ',
        style: TextStyle(
          color: Colors.white,
          fontSize: 9.0,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          backgroundColor: colour,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: rect.width + 40);

    final labelY = rect.top - tp.height - 2;
    tp.paint(canvas, Offset(rect.left, labelY.clamp(0, double.infinity)));
  }

  Color _resolveColour(AllergenFinding finding) {
    if (finding.confidence < 0.5) return _colourLow;
    return switch (finding.status) {
      FindingStatus.danger    => _colourDanger,
      FindingStatus.ambiguous => strictMode ? _colourDanger : _colourAmbiguous,
      FindingStatus.safe      => _colourSafe,
    };
  }

  @override
  bool shouldRepaint(covariant AllergenHudPainter old) =>
      old.findings != findings || old.strictMode != strictMode;
}
```

---

## Verdict Badge Widget

The badge provides a summary verdict at the bottom of the screen. It uses an animated colour transition to draw attention when DANGER is detected.

```
┌─────────────────────────────────────────────────────┐
│  🔴  ALLERGEN DETECTED                              │
│      casein (Dairy) · tahini (Sesame)               │
└─────────────────────────────────────────────────────┘
```

States:
- **Idle** (no label detected): Invisible / very faint "Point camera at label"
- **Scanning**: Pulsing white ring animation
- **🟢 ALL CLEAR**: Green pill, "Safe for your profile"
- **🟡 CHECK LABEL**: Amber pill, lists AMBIGUOUS tokens
- **🔴 DANGER**: Red pill with pulse animation, lists matched allergens

---

## Frame Rate Budget

| Component | Budget | Actual |
|---|---|---|
| Camera preview (hardware) | — | 30fps native |
| HUD CustomPainter repaint | <1ms | ~0.4ms |
| Verdict badge animation | — | 60fps interpolated |
| `shouldRepaint()` check | <0.1ms | — |

The `RepaintBoundary` + `IgnorePointer` combination ensures the HUD overlay adds less than 1ms to the frame budget. The camera preview itself is hardware-composited and unaffected by Flutter's render pipeline.

