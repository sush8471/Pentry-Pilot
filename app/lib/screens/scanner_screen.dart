import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/allergen_finding.dart';
import '../services/cactus_service.dart';
import '../providers/scanning_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/camera_provider.dart';
import '../widgets/allergen_hud_painter.dart';
import '../widgets/verdict_badge.dart';
import '../widgets/blur_nudge_overlay.dart';
import '../widgets/ocr_debug_overlay.dart';
import 'profile_screen.dart';

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> with WidgetsBindingObserver {
  bool _cameraPermissionGranted = false;
  bool _torchOn = false;
  CameraController? _controller;
  Size _previewSize = const Size(720, 1280);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestPermissionAndInitCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _requestPermissionAndInitCamera();
    }
  }

  Future<void> _requestPermissionAndInitCamera() async {
    final status = await Permission.camera.request();
    if (!mounted) return;

    if (status.isGranted) {
      setState(() => _cameraPermissionGranted = true);
      try {
        final pipeline = await ref.read(cameraPipelineProvider.future);
        await pipeline.initializeCamera();
        if (mounted && pipeline.cameraController != null) {
          setState(() {
            _controller = pipeline.cameraController;
            if (_controller!.value.previewSize != null) {
              _previewSize = Size(
                _controller!.value.previewSize!.height,
                _controller!.value.previewSize!.width,
              );
            }
          });
        }
      } catch (_) {
        // Handled: Desktop mock or emulator with no physical camera
      }
    } else {
      setState(() => _cameraPermissionGranted = false);
    }
  }

  Future<void> _toggleTorch() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final newMode = _torchOn ? FlashMode.off : FlashMode.torch;
      await _controller!.setFlashMode(newMode);
      setState(() => _torchOn = !_torchOn);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scanningState = ref.watch(scanningProvider);
    final profileState = ref.watch(profileProvider);
    final activeProfile = profileState.activeProfile;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Layer 1: Camera Preview / Fallback ──────────────────────────────
          if (_controller != null && _controller!.value.isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: CameraPreview(_controller!),
              ),
            )
          else
            _buildCameraPlaceholder(),

          // ── Layer 2: 70% Center ROI Guide Frame ───────────────────────────
          _buildCenterRoiGuide(),

          // ── Layer 3: AR HUD Highlighting Overlay ─────────────────────────
          IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size.infinite,
                painter: AllergenHudPainter(
                  findings: scanningState.findings,
                  cameraPreviewSize: _previewSize,
                  strictMode: activeProfile?.strictMode ?? false,
                ),
              ),
            ),
          ),

          // ── Layer 4: Top Navigation & Utility Controls ────────────────────
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Profile Switcher Chip
                    InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ProfileScreen()),
                        );
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.65),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.person_pin, color: Colors.greenAccent, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              activeProfile?.name ?? 'No Profile',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 18),
                          ],
                        ),
                      ),
                    ),

                    // Right utility actions
                    Row(
                      children: [
                        // Flashlight / Torch
                        IconButton(
                          icon: Icon(
                            _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                            color: _torchOn ? Colors.amberAccent : Colors.white70,
                          ),
                          onPressed: _toggleTorch,
                          tooltip: 'Toggle Flashlight',
                        ),
                        // Developer Debug Overlay Toggle
                        IconButton(
                          icon: Icon(
                            scanningState.showDebugOverlay
                                ? Icons.bug_report_rounded
                                : Icons.bug_report_outlined,
                            color: scanningState.showDebugOverlay
                                ? Colors.cyanAccent
                                : Colors.white70,
                          ),
                          onPressed: () {
                            ref.read(scanningProvider.notifier).toggleDebugOverlay();
                          },
                          tooltip: 'Toggle Performance HUD',
                        ),
                        // Pause / Resume Scanning
                        IconButton(
                          icon: Icon(
                            scanningState.isScanning
                                ? Icons.pause_circle_outline_rounded
                                : Icons.play_circle_fill_rounded,
                            color: scanningState.isScanning
                                ? Colors.white70
                                : Colors.greenAccent,
                          ),
                          onPressed: () {
                            ref.read(scanningProvider.notifier).toggleScanning();
                          },
                          tooltip: scanningState.isScanning ? 'Pause Scan' : 'Resume Scan',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Layer 5: Blur / Hold-Steady Nudge ─────────────────────────────
          if (scanningState.blurNudgeMessage != null)
            Positioned(
              top: 100,
              left: 20,
              right: 20,
              child: BlurNudgeOverlay(message: scanningState.blurNudgeMessage!),
            ),

          // ── Layer 6: Performance Diagnostics Overlay (if enabled) ────────
          if (scanningState.showDebugOverlay)
            Positioned(
              top: 140,
              left: 16,
              right: 16,
              child: OcrDebugOverlay(
                latestResult: CactusEvaluationResult(
                  findings: scanningState.findings,
                  overallVerdict: scanningState.overallVerdict,
                  ocrLatencyMs: scanningState.ocrLatencyMs,
                  dbLatencyMs: scanningState.dbLatencyMs,
                  needleLatencyMs: scanningState.needleLatencyMs,
                  totalLatencyMs: scanningState.totalLatencyMs,
                  dbHitCount: scanningState.dbHitCount,
                  needleTokenCount: scanningState.needleTokenCount,
                ),
              ),
            ),

          // ── Layer 7: Bottom Verdict Badge HUD ─────────────────────────────
          Positioned(
            bottom: 40,
            left: 16,
            right: 16,
            child: VerdictBadge(
              findings: scanningState.findings,
              overallVerdict: scanningState.overallVerdict,
              isScanning: scanningState.isScanning,
              onTapDetails: () => _showFindingsDetailsSheet(context, scanningState),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPlaceholder() {
    return Container(
      color: const Color(0xFF0D0F12),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _cameraPermissionGranted ? Icons.camera_alt : Icons.no_photography,
              size: 54,
              color: Colors.white24,
            ),
            const SizedBox(height: 16),
            Text(
              _cameraPermissionGranted
                  ? 'Initializing Camera Pipeline...'
                  : 'Camera permission required to scan labels',
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
            if (!_cameraPermissionGranted) ...[
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _requestPermissionAndInitCamera,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent),
                child: const Text('Grant Camera Access', style: TextStyle(color: Colors.black)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCenterRoiGuide() {
    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final boxWidth = constraints.maxWidth * 0.82;
          final boxHeight = constraints.maxHeight * 0.45;

          return Container(
            width: boxWidth,
            height: boxHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
            ),
            child: Stack(
              children: [
                // Top-left bracket
                Positioned(
                  top: 0,
                  left: 0,
                  child: _buildCornerGuide(true, true),
                ),
                // Top-right bracket
                Positioned(
                  top: 0,
                  right: 0,
                  child: _buildCornerGuide(true, false),
                ),
                // Bottom-left bracket
                Positioned(
                  bottom: 0,
                  left: 0,
                  child: _buildCornerGuide(false, true),
                ),
                // Bottom-right bracket
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: _buildCornerGuide(false, false),
                ),
                // Hint label
                Positioned(
                  bottom: 10,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Align Ingredients Within Frame',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCornerGuide(bool isTop, bool isLeft) {
    const len = 20.0;
    const thickness = 3.0;
    const color = Colors.greenAccent;

    return SizedBox(
      width: len,
      height: len,
      child: CustomPaint(
        painter: _CornerBracketPainter(
          isTop: isTop,
          isLeft: isLeft,
          color: color,
          length: len,
          thickness: thickness,
        ),
      ),
    );
  }

  void _showFindingsDetailsSheet(BuildContext context, ScanningState scanningState) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1B1E23),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Detected Ingredients',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${scanningState.totalLatencyMs}ms total latency',
                      style: const TextStyle(color: Colors.cyanAccent, fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (scanningState.findings.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No allergen risks detected in current frame.',
                      style: TextStyle(color: Colors.white60),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: scanningState.findings.length,
                    separatorBuilder: (_, __) => const Divider(color: Colors.white10),
                    itemBuilder: (ctx, i) {
                      final f = scanningState.findings[i];
                      final isDanger = f.status == FindingStatus.danger;
                      final isAmbiguous = f.status == FindingStatus.ambiguous;

                      final color = isDanger
                          ? Colors.redAccent
                          : isAmbiguous
                              ? Colors.amberAccent
                              : Colors.greenAccent;

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          isDanger
                              ? Icons.warning_rounded
                              : isAmbiguous
                                  ? Icons.help_outline_rounded
                                  : Icons.check_circle_outline_rounded,
                          color: color,
                        ),
                        title: Text(
                          f.token.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          f.matchedAllergen != null
                              ? 'Matched: ${f.matchedAllergen} (${(f.confidence * 100).toInt()}% conf)'
                              : f.note ?? 'No specific allergen code',
                          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: color, width: 1),
                          ),
                          child: Text(
                            f.status.name.toUpperCase(),
                            style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CornerBracketPainter extends CustomPainter {
  final bool isTop;
  final bool isLeft;
  final Color color;
  final double length;
  final double thickness;

  _CornerBracketPainter({
    required this.isTop,
    required this.isLeft,
    required this.color,
    required this.length,
    required this.thickness,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke;

    final path = Path();
    if (isTop && isLeft) {
      path.moveTo(0, length);
      path.lineTo(0, 0);
      path.lineTo(length, 0);
    } else if (isTop && !isLeft) {
      path.moveTo(size.width - length, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, length);
    } else if (!isTop && isLeft) {
      path.moveTo(0, size.height - length);
      path.lineTo(0, size.height);
      path.lineTo(length, size.height);
    } else {
      path.moveTo(size.width - length, size.height);
      path.lineTo(size.width, size.height);
      path.lineTo(size.width, size.height - length);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
