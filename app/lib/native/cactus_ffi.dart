import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

/// Opaque handle representing a Cactus model session
typedef CactusHandle = Pointer<Void>;

// C Native Typedefs
typedef _CactusInitC = CactusHandle Function(Pointer<Utf8> modelPath, Bool useNpu);
typedef _CactusInitDart = CactusHandle Function(Pointer<Utf8> modelPath, bool useNpu);

typedef _CactusDestroyC = Void Function(CactusHandle handle);
typedef _CactusDestroyDart = void Function(CactusHandle handle);

typedef _MirageOcrC = Pointer<Utf8> Function(
  CactusHandle handle,
  Pointer<Uint8> yuvBytes,
  Int32 width,
  Int32 height,
);
typedef _MirageOcrDart = Pointer<Utf8> Function(
  CactusHandle handle,
  Pointer<Uint8> yuvBytes,
  int width,
  int height,
);

typedef _NeedleCompleteC = Pointer<Utf8> Function(
  CactusHandle handle,
  Pointer<Utf8> messagesJson,
  Pointer<Utf8> toolsJson,
);
typedef _NeedleCompleteDart = Pointer<Utf8> Function(
  CactusHandle handle,
  Pointer<Utf8> messagesJson,
  Pointer<Utf8> toolsJson,
);

typedef _FreeStringC = Void Function(Pointer<Utf8> ptr);
typedef _FreeStringDart = void Function(Pointer<Utf8> ptr);

/// Native FFI bridge for Cactus Compute runtime (libcactus.so)
/// with safe mock fallback for desktop testing & development.
class CactusFFI {
  static CactusFFI? _instance;
  static CactusFFI get instance => _instance ??= CactusFFI._();

  CactusFFI._();

  DynamicLibrary? _lib;
  _CactusInitDart? _cactusInit;
  _CactusDestroyDart? _cactusDestroy;
  _MirageOcrDart? _mirageOcr;
  _NeedleCompleteDart? _needleComplete;
  _FreeStringDart? _freeString;

  CactusHandle? _mirageHandle;
  CactusHandle? _needleHandle;

  bool _isMock = false;
  bool get isMock => _isMock;
  bool get isInitialized => _mirageHandle != null && _needleHandle != null;

  /// Initialize Cactus runtime with paths to Mirage and Needle weights
  void init({
    required String mirageModelPath,
    required String needleModelPath,
    bool forceMock = false,
  }) {
    if (forceMock || (!Platform.isAndroid && !Platform.isIOS)) {
      _initMock();
      return;
    }

    try {
      if (Platform.isAndroid) {
        _lib = DynamicLibrary.open('libcactus.so');
      } else if (Platform.isIOS) {
        _lib = DynamicLibrary.process();
      }

      if (_lib != null) {
        _cactusInit = _lib!.lookupFunction<_CactusInitC, _CactusInitDart>('cactus_init');
        _cactusDestroy = _lib!.lookupFunction<_CactusDestroyC, _CactusDestroyDart>('cactus_destroy');
        _mirageOcr = _lib!.lookupFunction<_MirageOcrC, _MirageOcrDart>('cactus_mirage_ocr');
        _needleComplete = _lib!.lookupFunction<_NeedleCompleteC, _NeedleCompleteDart>('cactus_needle_complete');
        _freeString = _lib!.lookupFunction<_FreeStringC, _FreeStringDart>('cactus_free_string');

        final mirageUtf8 = mirageModelPath.toNativeUtf8();
        _mirageHandle = _cactusInit!(mirageUtf8, true);
        calloc.free(mirageUtf8);

        final needleUtf8 = needleModelPath.toNativeUtf8();
        _needleHandle = _cactusInit!(needleUtf8, true);
        calloc.free(needleUtf8);

        _isMock = false;
        return;
      }
    } catch (_) {
      // Fallback to mock runtime if native binary not available on host
      _initMock();
    }
  }

  void _initMock() {
    _isMock = true;
    _mirageHandle = Pointer.fromAddress(0x1000);
    _needleHandle = Pointer.fromAddress(0x2000);
  }

  /// Run Mirage OCR on frame buffer
  String mirageOcr(Uint8List yuvBytes, int width, int height) {
    if (_isMock || _mirageOcr == null) {
      // High-fidelity mock response with ingredient tokens and bounding boxes
      return '{"tokens":["water","maltodextrin","casein","sunflower oil","natural flavors","whey"],"bounding_boxes":[{"text":"casein","rect":{"x":120,"y":300,"w":80,"h":24}},{"text":"whey","rect":{"x":210,"y":300,"w":60,"h":24}},{"text":"natural flavors","rect":{"x":120,"y":330,"w":150,"h":24}}],"inference_ms":72}';
    }

    final nativeBytes = calloc<Uint8>(yuvBytes.length);
    nativeBytes.asTypedList(yuvBytes.length).setAll(0, yuvBytes);

    final resPtr = _mirageOcr!(_mirageHandle!, nativeBytes, width, height);
    final resultStr = resPtr.toDartString();

    _freeString!(resPtr);
    calloc.free(nativeBytes);
    return resultStr;
  }

  /// Run Needle constrained agent evaluation
  String needleComplete(String messagesJson, String toolsJson) {
    if (_isMock || _needleComplete == null) {
      // Deterministic mock schema-compliant response
      return '{"findings":[{"token":"casein","status":"DANGER","matched_allergen":"MILK","confidence":0.99},{"token":"whey","status":"DANGER","matched_allergen":"MILK","confidence":0.98},{"token":"natural flavors","status":"AMBIGUOUS","matched_allergen":"MILK","confidence":0.65},{"token":"water","status":"SAFE","matched_allergen":null,"confidence":1.0},{"token":"sunflower oil","status":"SAFE","matched_allergen":null,"confidence":0.95}],"overall_verdict":"DANGER"}';
    }

    final msgPtr = messagesJson.toNativeUtf8();
    final toolPtr = toolsJson.toNativeUtf8();

    final resPtr = _needleComplete!(_needleHandle!, msgPtr, toolPtr);
    final resultStr = resPtr.toDartString();

    _freeString!(resPtr);
    calloc.free(msgPtr);
    calloc.free(toolPtr);
    return resultStr;
  }

  void dispose() {
    if (!_isMock && _cactusDestroy != null) {
      if (_mirageHandle != null) _cactusDestroy!(_mirageHandle!);
      if (_needleHandle != null) _cactusDestroy!(_needleHandle!);
    }
    _mirageHandle = null;
    _needleHandle = null;
  }
}

