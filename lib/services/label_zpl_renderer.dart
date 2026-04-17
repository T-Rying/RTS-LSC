import '../models/label_design.dart';
import 'item_lookup_service.dart';

/// Builds a ZPL II string from a [LabelDesign] and a data binding map.
///
/// Coordinates in the design are stored in millimetres; ZPL uses dots,
/// so we convert using the design's DPI (default 203 dpi ≈ 8 dots/mm).
/// Only the common commands are emitted (^XA/^XZ envelope, ^PW page width,
/// ^LL label length, ^FO field origin, ^A0 default font, ^FD field data,
/// ^BC code-128 barcodes, ^FS field separator). That covers the three
/// element types the designer supports today — static text, bound field,
/// bound barcode.
String renderZpl(LabelDesign design, Map<String, String> data, {int quantity = 1}) {
  final dotsPerMm = design.dpi / 25.4;
  int dots(double mm) => (mm * dotsPerMm).round();

  final widthDots = dots(design.widthMm);
  final heightDots = dots(design.heightMm);

  final buf = StringBuffer();
  for (var i = 0; i < quantity.clamp(1, 9999); i++) {
    buf.writeln('^XA');
    buf.writeln('^PW$widthDots');
    buf.writeln('^LL$heightDots');
    buf.writeln('^LH0,0');

    for (final element in design.elements) {
      final x = dots(element.xMm);
      final y = dots(element.yMm);
      final h = dots(element.heightMm).clamp(10, 800);
      buf.writeln('^FO$x,$y');

      switch (element.type) {
        case LabelElementType.text:
          final text = element.text ?? '';
          buf.writeln('^A0N,$h,$h^FD${_zplEscape(text)}^FS');
        case LabelElementType.field:
          final value = data[element.fieldKey] ?? '';
          buf.writeln('^A0N,$h,$h^FD${_zplEscape(value)}^FS');
        case LabelElementType.barcode:
          final value = data[element.fieldKey] ?? '';
          buf.writeln('^BY2,3,$h');
          buf.writeln('^BCN,$h,Y,N,N^FD${_zplEscape(value)}^FS');
      }
    }

    buf.writeln('^XZ');
  }
  return buf.toString();
}

/// Flattens an [ItemCard] into the key space used by [LabelDesign] field
/// bindings. Callers use this at print time so labels can reference data
/// like "Item No." or "Unit Price" regardless of which replicated entity
/// actually holds the value.
Map<String, String> bindItemCard(ItemCard? card) {
  if (card == null) return {};
  String s(dynamic v) => (v ?? '').toString();
  final firstPrice = card.salesPrices.isNotEmpty ? card.salesPrices.first : const {};
  return {
    'Barcode No.': s(card.barcode['Barcode No.']),
    'Item No.': s(card.barcode['Item No.']),
    'Item Description': s(card.barcode['Description']),
    'Variant Code': s(card.variant?['Code'] ?? card.barcode['Variant Code']),
    'Variant Description': s(card.variant?['Description']),
    'Unit of Measure Code': s(card.barcode['Unit of Measure Code']),
    'Unit Price': s(firstPrice['Unit Price']),
    'Currency Code': s(firstPrice['Currency Code']),
    'Item Category Code': s(card.category?['Code'] ?? card.barcode['Item Category Code']),
    'Item Category Description': s(card.category?['Description']),
  };
}

/// Sample data used when the user wants to preview a design without
/// scanning a real barcode.
Map<String, String> demoBinding() => const {
      'Barcode No.': '5901234123457',
      'Item No.': '10000',
      'Item Description': 'Demo item — preview only',
      'Variant Code': 'BLUE',
      'Variant Description': 'Blue variant',
      'Unit of Measure Code': 'PCS',
      'Unit Price': '12.50',
      'Currency Code': 'EUR',
      'Item Category Code': 'DEMO',
      'Item Category Description': 'Demo category',
    };

String _zplEscape(String s) {
  // ZPL treats ^ and ~ as control characters. Also strip newlines so
  // the string stays on one line in the ^FD block.
  return s
      .replaceAll('\\', '\\\\')
      .replaceAll('^', r'\5E')
      .replaceAll('~', r'\7E')
      .replaceAll('\r', ' ')
      .replaceAll('\n', ' ');
}
