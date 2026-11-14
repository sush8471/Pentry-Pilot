import 'package:flutter/material.dart';
import 'package:pantry_pilot/services/cactus_service.dart';
import 'package:pantry_pilot/models/allergen_finding.dart';

/// Overlay widget rendering raw extracted Mirage OCR tokens & pipeline diagnostics
class OcrDebugOverlay extends StatelessWidget {
  final CactusEvaluationResult? latestResult;
  final bool showDiagnostics;

  const OcrDebugOverlay({
    super.key,
    required this.latestResult,
    this.showDiagnostics = true,
  });

  @override
  Widget build(BuildContext context) {
    if (latestResult == null) {
      return const SizedBox.shrink();
    }

    final result = latestResult!;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Latency & Pipeline Metrics Pill
            if (showDiagnostics)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.cyanAccent.withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.speed, color: Colors.cyanAccent, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Mirage OCR: ${result.ocrLatencyMs}ms | Needle: ${result.needleLatencyMs}ms | Total: ${result.totalLatencyMs}ms',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),

            // Extracted Ingredient Tokens Chips
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: result.findings.map((finding) {
                final Color chipColor;
                final IconData icon;

                switch (finding.status) {
                  case FindingStatus.danger:
                    chipColor = Colors.redAccent;
                    icon = Icons.warning_rounded;
                    break;
                  case FindingStatus.ambiguous:
                    chipColor = Colors.amberAccent;
                    icon = Icons.help_outline_rounded;
                    break;
                  case FindingStatus.safe:
                    chipColor = Colors.greenAccent;
                    icon = Icons.check_circle_outline_rounded;
                    break;
                }

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: chipColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: chipColor, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        finding.token,
                        style: TextStyle(
                          color: chipColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (finding.matchedAllergen != null) ...[
                        const SizedBox(width: 4),
                        Text(
                          '(${finding.matchedAllergen})',
                          style: TextStyle(
                            color: chipColor.withOpacity(0.8),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

