import 'package:flutter/material.dart';
import '../models/allergen_finding.dart';

/// CustomPainter that renders AR bounding boxes, corner bracket accents,
/// and ingredient name tags over detected food ingredient labels.
class AllergenHudPainter extends CustomPainter {
  final List<AllergenFinding> findings;
  final Size cameraPreviewSize;
  final bool strictMode;

  static const Color colourDanger = Color(0xFFE53935);
  static const Color colourAmbiguous = Color(0xFFFFC107);
  static const Color colourSafe = Color(0xFF43A047);
  static const Color colourLow = Color(0xFF9E9E9E);

  const AllergenHudPainter({
    required this.findings,
    required this.cameraPreviewSize,
    this.strictMode = false,
  });

  @override
  void paint(Canvas canvas, Size screenSize) {
    if (cameraPreviewSize.width == 0 || cameraPreviewSize.height == 0) return;
    if (findings.isEmpty) return;

    // The camera sensor is landscape (width > height), while mobile screen is portrait.
    // For a portrait-locked viewfinder: camera "height" maps to screen "width",
    // and camera "width" maps to screen "height".
    final double scaleX = screenSize.width / cameraPreviewSize.height;
    final double scaleY = screenSize.height / cameraPreviewSize.width;

    for (final finding in findings) {
      final bbox = finding.bbox;
      if (bbox == null) continue;
      if (finding.confidence < 0.3) continue; // Filter out extreme low-confidence noise

      final Color colour = _resolveColour(finding);

      // Transform camera-preview space -> screen space
      final Rect screenRect = Rect.fromLTWH(
        bbox.x * scaleX,
        bbox.y * scaleY,
        bbox.width * scaleX,
        bbox.height * scaleY,
      );

      _paintHighlight(canvas, screenRect, colour, finding.confidence);
      _paintCornerBrackets(canvas, screenRect, colour);
      _paintLabel(canvas, screenRect, finding.token, colour);
    }
  }

  void _paintHighlight(Canvas canvas, Rect rect, Color colour, double confidence) {
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));

    // Semi-transparent fill weighted by confidence
    final fillPaint = Paint()
      ..color = colour.withOpacity(0.25 * confidence.clamp(0.4, 1.0))
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, fillPaint);

    // Border line
    final borderPaint = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawRRect(rrect, borderPaint);
  }

  void _paintCornerBrackets(Canvas canvas, Rect rect, Color colour) {
    const double bracketLen = 8.0;
    final bracketPaint = Paint()
      ..color = colour
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.square;

    // Top-left corner
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(bracketLen, 0), bracketPaint);
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(0, bracketLen), bracketPaint);

    // Top-right corner
    canvas.drawLine(rect.topRight, rect.topRight - const Offset(bracketLen, 0), bracketPaint);
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(0, bracketLen), bracketPaint);

    // Bottom-left corner
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(bracketLen, 0), bracketPaint);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft - const Offset(0, bracketLen), bracketPaint);

    // Bottom-right corner
    canvas.drawLine(rect.bottomRight, rect.bottomRight - const Offset(bracketLen, 0), bracketPaint);
    canvas.drawLine(rect.bottomRight, rect.bottomRight - const Offset(0, bracketLen), bracketPaint);
  }

  void _paintLabel(Canvas canvas, Rect rect, String text, Color colour) {
    final textSpan = TextSpan(
      text: ' ${text.toUpperCase()} ',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10.0,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: rect.width + 80);

    final double labelWidth = textPainter.width + 4;
    final double labelHeight = textPainter.height + 2;
    final double labelY = (rect.top - labelHeight - 3).clamp(4.0, double.infinity);

    // Background tag pill
    final tagRect = Rect.fromLTWH(rect.left, labelY, labelWidth, labelHeight);
    final tagRRect = RRect.fromRectAndRadius(tagRect, const Radius.circular(2));
    final tagPaint = Paint()
      ..color = colour
      ..style = PaintingStyle.fill;
    canvas.drawRRect(tagRRect, tagPaint);

    // Text painted inside tag
    textPainter.paint(canvas, Offset(rect.left + 2, labelY + 1));
  }

  Color _resolveColour(AllergenFinding finding) {
    if (finding.confidence < 0.5) return colourLow;
    switch (finding.status) {
      case FindingStatus.danger:
        return colourDanger;
      case FindingStatus.ambiguous:
        return strictMode ? colourDanger : colourAmbiguous;
      case FindingStatus.safe:
        return colourSafe;
    }
  }

  @override
  bool shouldRepaint(covariant AllergenHudPainter oldDelegate) {
    if (oldDelegate.strictMode != strictMode) return true;
    if (oldDelegate.cameraPreviewSize != cameraPreviewSize) return true;
    if (oldDelegate.findings.length != findings.length) return true;

    for (int i = 0; i < findings.length; i++) {
      if (oldDelegate.findings[i] != findings[i]) return true;
    }
    return false;
  }
}

