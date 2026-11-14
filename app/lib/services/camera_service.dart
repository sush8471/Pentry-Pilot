import 'dart:async';
import 'package:camera/camera.dart';
import 'package:pantry_pilot/services/frame_processor.dart';
import 'package:pantry_pilot/services/cactus_service.dart';
import 'package:pantry_pilot/services/allergen_db_service.dart';

/// Camera streaming states
enum CameraScanState {
  uninitialized,
  initializing,
  scanning,
  holdingSteady, // Blurry frame detected
  paused,
  error,
}

/// Service managing the live CameraController stream and coupling to FrameProcessor & CactusService
class CameraPipelineService {
  final FrameProcessor _frameProcessor;
  final CactusService _cactusService;
  final AllergenDbService? _allergenDb;

  CameraController? _cameraController;
  CameraScanState _state = CameraScanState.uninitialized;

  final StreamController<CactusEvaluationResult> _resultsController =
      StreamController<CactusEvaluationResult>.broadcast();
  final StreamController<CameraScanState> _stateController =
      StreamController<CameraScanState>.broadcast();

  Stream<CactusEvaluationResult> get resultsStream => _resultsController.stream;
  Stream<CameraScanState> get stateStream => _stateController.stream;
  CameraScanState get state => _state;
  CameraController? get cameraController => _cameraController;

  List<String> _activeAllergens = const ['MILK', 'GLUTEN', 'SESAME', 'PEANUT'];

  CameraPipelineService({
    FrameProcessor? frameProcessor,
    CactusService? cactusService,
    AllergenDbService? allergenDb,
  })  : _frameProcessor = frameProcessor ?? FrameProcessor(),
        _cactusService = cactusService ?? CactusService(),
        _allergenDb = allergenDb;

  void updateActiveAllergens(List<String> allergens) {
    _activeAllergens = allergens;
  }

  void setThermalStatus(ThermalStatus status) {
    _frameProcessor.updateThermalStatus(status);
  }

  FrameProcessor get frameProcessor => _frameProcessor;

  void _setState(CameraScanState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  /// Initialize camera with target ResolutionPreset (default: medium / 720p)
  Future<void> initializeCamera({
    List<CameraDescription>? initialCameras,
    ResolutionPreset resolution = ResolutionPreset.medium,
  }) async {
    _setState(CameraScanState.initializing);
    try {
      if (!_cactusService.isInitialized) {
        final db = _allergenDb ?? AllergenDbService();
        _cactusService.initialize(
          allergenDb: db,
          forceMock: true,
        );
      }

      final cameras = initialCameras ?? await availableCameras();
      if (cameras.isEmpty) {
        _setState(CameraScanState.error);
        return;
      }

      // Select back-facing camera
      final rearCamera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        rearCamera,
        resolution,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();
      _setState(CameraScanState.scanning);

      await _cameraController!.startImageStream(_handleCameraImage);
    } catch (_) {
      _setState(CameraScanState.error);
    }
  }

  /// Internal handler for each raw camera frame arriving from the sensor
  void _handleCameraImage(CameraImage image) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // 1. Drop-latest throttling & device tier interval check
    if (!_frameProcessor.shouldSampleFrame(nowMs)) {
      return;
    }

    _frameProcessor.markBusy();

    // 2. Extract Y (luma) plane
    final yPlane = image.planes[0];
    final yBytes = yPlane.bytes;

    // 3. Crop 70% center ROI & evaluate sharpness
    final processed = _frameProcessor.cropAndFilterFrame(
      yPlaneBytes: yBytes,
      srcWidth: image.width,
      srcHeight: image.height,
      bytesPerRow: yPlane.bytesPerRow,
    );

    if (processed == null) {
      // Blurry frame or low variance detected
      _setState(CameraScanState.holdingSteady);
      _frameProcessor.markIdle(DateTime.now().millisecondsSinceEpoch);
      return;
    }

    if (_state == CameraScanState.holdingSteady) {
      _setState(CameraScanState.scanning);
    }

    // 4. Feed cropped sharp frame to Cactus Mirage OCR + Needle Agent
    _cactusService
        .evaluateFrame(
      yuvBytes: processed.croppedYBytes,
      width: processed.width,
      height: processed.height,
      activeAllergens: _activeAllergens,
    )
        .then((result) {
      _resultsController.add(result);
    }).catchError((_) {
      // Ignored for resilience
    }).whenComplete(() {
      _frameProcessor.markIdle(DateTime.now().millisecondsSinceEpoch);
    });
  }

  /// Stop live streaming and release camera hardware
  Future<void> dispose() async {
    if (_cameraController != null) {
      if (_cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }
      await _cameraController!.dispose();
    }
    await _resultsController.close();
    await _stateController.close();
    _setState(CameraScanState.uninitialized);
  }
}

