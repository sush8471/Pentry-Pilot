import 'package:flutter/material.dart';
import '../models/allergen_finding.dart';

/// The bottom floating HUD badge summarizing scan results:
/// 🔴 DANGER | 🟡 CHECK LABEL | 🟢 ALL CLEAR | ⚪ SCANNING
class VerdictBadge extends StatefulWidget {
  final List<AllergenFinding> findings;
  final String overallVerdict;
  final bool isScanning;
  final VoidCallback? onTapDetails;

  const VerdictBadge({
    super.key,
    required this.findings,
    required this.overallVerdict,
    this.isScanning = true,
    this.onTapDetails,
  });

  @override
  State<VerdictBadge> createState() => _VerdictBadgeState();
}

class _VerdictBadgeState extends State<VerdictBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.overallVerdict == 'DANGER') {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant VerdictBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.overallVerdict == 'DANGER' && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (widget.overallVerdict != 'DANGER' && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final verdict = widget.overallVerdict.toUpperCase();
    final dangerFindings = widget.findings
        .where((f) => f.status == FindingStatus.danger)
        .toList();
    final ambiguousFindings = widget.findings
        .where((f) => f.status == FindingStatus.ambiguous)
        .toList();

    Color bgColor;
    Color accentColor;
    IconData icon;
    String title;
    String subtitle;

    switch (verdict) {
      case 'DANGER':
        bgColor = const Color(0xFFB71C1C).withOpacity(0.92);
        accentColor = const Color(0xFFFF5252);
        icon = Icons.warning_rounded;
        title = 'ALLERGEN DETECTED';
        final items = dangerFindings
            .map((f) => f.matchedAllergen != null
                ? '${f.token} (${f.matchedAllergen})'
                : f.token)
            .join(' · ');
        subtitle = items.isNotEmpty ? items : 'Harmful ingredient identified';
        break;

      case 'AMBIGUOUS':
        bgColor = const Color(0xFFF57F17).withOpacity(0.92);
        accentColor = const Color(0xFFFFD54F);
        icon = Icons.help_outline_rounded;
        title = 'CHECK INGREDIENTS';
        final items = ambiguousFindings.map((f) => f.token).join(' · ');
        subtitle = items.isNotEmpty ? items : 'Unclear or derivative sources detected';
        break;

      case 'SAFE':
        if (widget.findings.isEmpty) {
          bgColor = const Color(0xFF263238).withOpacity(0.85);
          accentColor = const Color(0xFF90A4AE);
          icon = Icons.camera_alt_outlined;
          title = widget.isScanning ? 'POINT AT INGREDIENTS' : 'READY TO SCAN';
          subtitle = 'Align camera with the nutrition/ingredients list';
        } else {
          bgColor = const Color(0xFF1B5E20).withOpacity(0.92);
          accentColor = const Color(0xFF69F0AE);
          icon = Icons.check_circle_rounded;
          title = 'ALL CLEAR';
          subtitle = 'No allergens found for active profile';
        }
        break;

      default:
        bgColor = const Color(0xFF263238).withOpacity(0.85);
        accentColor = const Color(0xFF90A4AE);
        icon = Icons.search_rounded;
        title = 'ANALYZING';
        subtitle = 'Reading camera stream...';
    }

    return ScaleTransition(
      scale: verdict == 'DANGER' ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTapDetails,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accentColor.withOpacity(0.6), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withOpacity(0.2),
                  blurRadius: 16,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    shape: BoxShape.circle,
                    border: Border.all(color: accentColor.withOpacity(0.5)),
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (widget.findings.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white.withOpacity(0.7),
                    size: 22,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

