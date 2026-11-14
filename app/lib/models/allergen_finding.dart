enum FindingStatus {
  danger,
  ambiguous,
  safe;

  static FindingStatus fromString(String status) {
    switch (status.toUpperCase()) {
      case 'DANGER':
        return FindingStatus.danger;
      case 'AMBIGUOUS':
        return FindingStatus.ambiguous;
      case 'SAFE':
      default:
        return FindingStatus.safe;
    }
  }
}

class BoundingBox {
  final double x;
  final double y;
  final double width;
  final double height;

  const BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory BoundingBox.fromJson(Map<String, dynamic> json) {
    return BoundingBox(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['w'] as num).toDouble(),
      height: (json['h'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'w': width,
    'h': height,
  };
}

class AllergenFinding {
  final String token;
  final FindingStatus status;
  final String? matchedAllergen;
  final double confidence;
  /// Bounding box from Mirage OCR for HUD overlay positioning.
  final BoundingBox? bbox;
  /// Optional note (e.g. PAL text, source note from DB taxonomy).
  final String? note;

  const AllergenFinding({
    required this.token,
    required this.status,
    this.matchedAllergen,
    required this.confidence,
    this.bbox,
    this.note,
  });

  factory AllergenFinding.fromJson(Map<String, dynamic> json, {BoundingBox? bbox}) {
    return AllergenFinding(
      token: json['token'] as String,
      status: FindingStatus.fromString(json['status'] as String),
      matchedAllergen: json['matched_allergen'] as String?,
      confidence: (json['confidence'] as num).toDouble(),
      bbox: bbox,
      note: json['note'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'token': token,
    'status': status.name.toUpperCase(),
    if (matchedAllergen != null) 'matched_allergen': matchedAllergen,
    'confidence': confidence,
    if (bbox != null) 'bbox': bbox!.toJson(),
    if (note != null) 'note': note,
  };
}
