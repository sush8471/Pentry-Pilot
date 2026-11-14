import 'dart:convert';
import 'dart:typed_data';
import '../native/cactus_ffi.dart';
import '../models/allergen_finding.dart';
import 'text_normalizer.dart';
import 'allergen_db_service.dart';

class CactusEvaluationResult {
  final List<AllergenFinding> findings;
  final String overallVerdict;
  final int ocrLatencyMs;
  final int dbLatencyMs;
  final int needleLatencyMs;
  final int totalLatencyMs;
  /// Tokens short-circuited by DB lookup (didn't need Needle)
  final int dbHitCount;
  /// Tokens forwarded to Needle after DB miss
  final int needleTokenCount;

  const CactusEvaluationResult({
    required this.findings,
    required this.overallVerdict,
    required this.ocrLatencyMs,
    required this.dbLatencyMs,
    required this.needleLatencyMs,
    required this.totalLatencyMs,
    required this.dbHitCount,
    required this.needleTokenCount,
  });
}

class CactusService {
  final CactusFFI _ffi = CactusFFI.instance;
  late final AllergenDbService _allergenDb;
  bool _initialized = false;
  bool get isInitialized => _initialized;

  late String _toolsSchema;

  /// [allergenDb] must already have [AllergenDbService.loadFromSeedMap] called.
  void initialize({
    required AllergenDbService allergenDb,
    String mirageModelPath = 'assets/models/mirage.cact',
    String needleModelPath = 'assets/models/needle.cact',
    bool forceMock = false,
  }) {
    _allergenDb = allergenDb;
    _ffi.init(
      mirageModelPath: mirageModelPath,
      needleModelPath: needleModelPath,
      forceMock: forceMock,
    );
    _toolsSchema = _buildToolSchema();
    _initialized = true;
  }

  /// Evaluates an image frame against dietary profiles.
  ///
  /// Pipeline:
  ///   1. Mirage OCR → raw token strings
  ///   2. TextNormalizer → clean, deduplicated tokens; PAL phrases extracted
  ///   3. AllergenDbService pre-filter:
  ///      - DANGER / AMBIGUOUS from DB → added directly to findings (skips Needle)
  ///      - SAFE or unknown → forwarded to Needle
  ///   4. Needle AI evaluates remaining unknown tokens
  ///   5. Merge DB findings + Needle findings → final result
  Future<CactusEvaluationResult> evaluateFrame({
    required Uint8List yuvBytes,
    required int width,
    required int height,
    required List<String> activeAllergens,
  }) async {
    if (!_initialized) {
      throw StateError('CactusService has not been initialized');
    }

    final totalSw = Stopwatch()..start();

    // ── Step 1: Mirage OCR ───────────────────────────────────────────────────
    final ocrSw = Stopwatch()..start();
    final ocrJson = _ffi.mirageOcr(yuvBytes, width, height);
    ocrSw.stop();

    final ocrData = jsonDecode(ocrJson) as Map<String, dynamic>;
    final rawTokens = (ocrData['tokens'] as List<dynamic>?)?.cast<String>() ?? [];
    final boxesData = ocrData['bounding_boxes'] as List<dynamic>? ?? [];

    final Map<String, BoundingBox> bboxMap = {};
    for (final b in boxesData) {
      final map = b as Map<String, dynamic>;
      final text = map['text'] as String;
      bboxMap[text.toLowerCase()] = BoundingBox.fromJson(map['rect'] as Map<String, dynamic>);
    }

    if (rawTokens.isEmpty) {
      totalSw.stop();
      return CactusEvaluationResult(
        findings: const [],
        overallVerdict: 'SAFE',
        ocrLatencyMs: ocrSw.elapsedMilliseconds,
        dbLatencyMs: 0,
        needleLatencyMs: 0,
        totalLatencyMs: totalSw.elapsedMilliseconds,
        dbHitCount: 0,
        needleTokenCount: 0,
      );
    }

    // ── Step 2: Text Normalization ───────────────────────────────────────────
    final fullText = rawTokens.join(', ');
    final palPhrases = TextNormalizer.detectPalPhrases(fullText);
    final normalizedTokens = TextNormalizer.normalizeAll(rawTokens);

    // PAL phrases → AMBIGUOUS findings immediately (no DB / Needle needed)
    final palFindings = palPhrases.map((phrase) {
      return AllergenFinding(
        token: phrase,
        status: FindingStatus.ambiguous,
        matchedAllergen: null,
        confidence: 0.75,
        bbox: null,
        note: 'Precautionary allergen label detected',
      );
    }).toList();

    // ── Step 3: AllergenDbService pre-filter ─────────────────────────────────
    final dbSw = Stopwatch()..start();
    final List<AllergenFinding> dbFindings = [];
    final List<String> needleTokens = []; // tokens forwarded to Needle

    for (final token in normalizedTokens) {
      final match = _allergenDb.lookup(token, activeAllergens);
      if (match == null) {
        // Not in DB taxonomy at all — let Needle decide
        needleTokens.add(token);
      } else if (match.allergenCode.isEmpty) {
        // _kSafeSentinel — confirmed SAFE by DB, skip Needle
        // (no finding emitted)
      } else {
        // DANGER or AMBIGUOUS — emit finding directly
        dbFindings.add(AllergenFinding(
          token: token,
          status: match.isAmbiguous ? FindingStatus.ambiguous : FindingStatus.danger,
          matchedAllergen: match.allergenCode,
          confidence: match.confidence,
          bbox: bboxMap[token],
          note: match.sourceNote,
        ));
      }
    }
    dbSw.stop();

    // ── Step 4: Needle AI for unknown tokens ─────────────────────────────────
    final List<AllergenFinding> needleFindings = [];
    final needleSw = Stopwatch()..start();

    if (needleTokens.isNotEmpty) {
      final systemPrompt = _buildSystemPrompt(activeAllergens);
      final messages = jsonEncode([
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': 'Ingredients list: ${needleTokens.join(", ")}'},
      ]);

      final needleJson = _ffi.needleComplete(messages, _toolsSchema);
      final needleData = jsonDecode(needleJson) as Map<String, dynamic>;
      final rawFindings = needleData['findings'] as List<dynamic>? ?? [];

      for (final f in rawFindings) {
        final map = f as Map<String, dynamic>;
        final token = (map['token'] as String).toLowerCase();
        final status = map['status'] as String;
        // Filter out SAFE verdicts from Needle — no finding needed
        if (status != 'SAFE') {
          needleFindings.add(AllergenFinding.fromJson(map, bbox: bboxMap[token]));
        }
      }
    }

    needleSw.stop();

    // ── Step 5: Merge & compute overall verdict ──────────────────────────────
    final allFindings = <AllergenFinding>[...palFindings, ...dbFindings, ...needleFindings];

    final overallVerdict = _computeVerdict(allFindings);

    totalSw.stop();

    return CactusEvaluationResult(
      findings: allFindings,
      overallVerdict: overallVerdict,
      ocrLatencyMs: ocrSw.elapsedMilliseconds,
      dbLatencyMs: dbSw.elapsedMilliseconds,
      needleLatencyMs: needleSw.elapsedMilliseconds,
      totalLatencyMs: totalSw.elapsedMilliseconds,
      dbHitCount: dbFindings.length,
      needleTokenCount: needleTokens.length,
    );
  }

  /// Determine overall frame verdict from individual findings.
  String _computeVerdict(List<AllergenFinding> findings) {
    if (findings.any((f) => f.status == FindingStatus.danger)) return 'DANGER';
    if (findings.any((f) => f.status == FindingStatus.ambiguous)) return 'AMBIGUOUS';
    return 'SAFE';
  }

  String _buildSystemPrompt(List<String> activeAllergens) {
    return 'You are an offline allergen safety analyzer. '
        'The user is strictly allergic to: ${activeAllergens.join(", ")}. '
        'Evaluate only the ingredients listed. '
        'DANGER: direct allergen or derivative. '
        'AMBIGUOUS: unverifiable source that may contain allergen. '
        'SAFE: no known allergen risk. '
        'Respond using the evaluate_ingredients tool. JSON only.';
  }

  String _buildToolSchema() {
    return jsonEncode([
      {
        'name': 'evaluate_ingredients',
        'description': 'Evaluate food ingredients against dietary restrictions',
        'parameters': {
          'type': 'object',
          'properties': {
            'findings': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'token': {'type': 'string'},
                  'status': {'type': 'string', 'enum': ['SAFE', 'DANGER', 'AMBIGUOUS']},
                  'matched_allergen': {'type': ['string', 'null']},
                  'confidence': {'type': 'number'},
                },
                'required': ['token', 'status', 'confidence'],
              },
            },
            'overall_verdict': {'type': 'string', 'enum': ['SAFE', 'DANGER', 'AMBIGUOUS']},
          },
          'required': ['findings', 'overall_verdict'],
        },
      }
    ]);
  }

  void dispose() {
    _ffi.dispose();
    _initialized = false;
  }
}
