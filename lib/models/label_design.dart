/// Label designer data model. Coordinates and sizes are stored in
/// millimetres so a design renders the same regardless of DPI or
/// preview scale; ZPL output converts to dots at print time.
enum LabelElementType { text, field, barcode }

class LabelElement {
  String id;
  LabelElementType type;
  double xMm;
  double yMm;
  double heightMm;
  String? text;
  String? fieldKey;

  LabelElement({
    required this.id,
    required this.type,
    required this.xMm,
    required this.yMm,
    required this.heightMm,
    this.text,
    this.fieldKey,
  });

  LabelElement copy() => LabelElement(
        id: id,
        type: type,
        xMm: xMm,
        yMm: yMm,
        heightMm: heightMm,
        text: text,
        fieldKey: fieldKey,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'xMm': xMm,
        'yMm': yMm,
        'heightMm': heightMm,
        if (text != null) 'text': text,
        if (fieldKey != null) 'fieldKey': fieldKey,
      };

  factory LabelElement.fromJson(Map<String, dynamic> j) => LabelElement(
        id: j['id'] as String? ?? _newId(),
        type: LabelElementType.values.firstWhere(
          (t) => t.name == (j['type'] as String? ?? ''),
          orElse: () => LabelElementType.text,
        ),
        xMm: (j['xMm'] as num?)?.toDouble() ?? 0,
        yMm: (j['yMm'] as num?)?.toDouble() ?? 0,
        heightMm: (j['heightMm'] as num?)?.toDouble() ?? 4,
        text: j['text'] as String?,
        fieldKey: j['fieldKey'] as String?,
      );
}

class LabelDesign {
  String id;
  String name;
  double widthMm;
  double heightMm;
  int dpi;
  List<LabelElement> elements;
  DateTime createdAt;
  DateTime updatedAt;

  LabelDesign({
    required this.id,
    required this.name,
    required this.widthMm,
    required this.heightMm,
    this.dpi = 203,
    List<LabelElement>? elements,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : elements = elements ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  LabelDesign copy() => LabelDesign(
        id: id,
        name: name,
        widthMm: widthMm,
        heightMm: heightMm,
        dpi: dpi,
        elements: elements.map((e) => e.copy()).toList(),
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'widthMm': widthMm,
        'heightMm': heightMm,
        'dpi': dpi,
        'elements': elements.map((e) => e.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'schemaVersion': 1,
      };

  factory LabelDesign.fromJson(Map<String, dynamic> j) => LabelDesign(
        id: j['id'] as String? ?? _newId(),
        name: j['name'] as String? ?? 'Untitled',
        widthMm: (j['widthMm'] as num?)?.toDouble() ?? 50,
        heightMm: (j['heightMm'] as num?)?.toDouble() ?? 25,
        dpi: (j['dpi'] as num?)?.toInt() ?? 203,
        elements: ((j['elements'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(LabelElement.fromJson)
            .toList(),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );

  factory LabelDesign.empty({String? name, required LabelSize size}) => LabelDesign(
        id: _newId(),
        name: name ?? 'Untitled label',
        widthMm: size.widthMm,
        heightMm: size.heightMm,
      );
}

class LabelSize {
  final String name;
  final double widthMm;
  final double heightMm;

  const LabelSize(this.name, this.widthMm, this.heightMm);

  static const List<LabelSize> presets = [
    LabelSize('50 × 25 mm (small)', 50, 25),
    LabelSize('50 × 75 mm', 50, 75),
    LabelSize('70 × 50 mm', 70, 50),
    LabelSize('100 × 50 mm', 100, 50),
    LabelSize('100 × 75 mm', 100, 75),
    LabelSize('100 × 150 mm (shipping)', 100, 150),
  ];
}

/// The canonical set of field keys a label can bind to. These are the
/// values populated by [bindItemCard] at print time.
const List<String> labelFieldKeys = [
  'Barcode No.',
  'Item No.',
  'Item Description',
  'Variant Code',
  'Variant Description',
  'Unit of Measure Code',
  'Unit Price',
  'Currency Code',
  'Item Category Code',
  'Item Category Description',
];

int _idCounter = 0;

String _newId() {
  _idCounter++;
  return '${DateTime.now().microsecondsSinceEpoch}_$_idCounter';
}
