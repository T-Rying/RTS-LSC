import 'package:flutter/cupertino.dart';

import '../models/label_design.dart';

/// Renders a [LabelDesign] to an on-screen canvas approximating how it
/// will print. Sizes are in millimetres; the widget picks a scale so the
/// label fits the available width. Used by both the designer (live edit)
/// and the print job page (demo preview when there is no printer).
class LabelPreview extends StatelessWidget {
  final LabelDesign design;
  final Map<String, String> data;
  final double maxWidth;
  final double maxHeight;
  final String? selectedElementId;
  final void Function(String elementId, double dxMm, double dyMm)? onElementDrag;
  final ValueChanged<String>? onElementTap;
  final VoidCallback? onBackgroundTap;

  const LabelPreview({
    super.key,
    required this.design,
    required this.data,
    this.maxWidth = 360,
    this.maxHeight = 500,
    this.selectedElementId,
    this.onElementDrag,
    this.onElementTap,
    this.onBackgroundTap,
  });

  @override
  Widget build(BuildContext context) {
    final scale = _pickScale();
    final width = design.widthMm * scale;
    final height = design.heightMm * scale;

    return GestureDetector(
      onTap: onBackgroundTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: CupertinoColors.white,
          border: Border.all(color: CupertinoColors.systemGrey3),
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            for (final element in design.elements)
              _positioned(element, scale),
          ],
        ),
      ),
    );
  }

  double _pickScale() {
    final byWidth = maxWidth / design.widthMm;
    final byHeight = maxHeight / design.heightMm;
    return byWidth < byHeight ? byWidth : byHeight;
  }

  Widget _positioned(LabelElement element, double scale) {
    final left = element.xMm * scale;
    final top = element.yMm * scale;
    final heightPx = element.heightMm * scale;
    final selected = element.id == selectedElementId;

    Widget child;
    switch (element.type) {
      case LabelElementType.text:
        child = _textBox(element.text ?? '', heightPx, selected);
      case LabelElementType.field:
        final value = data[element.fieldKey] ?? '<${element.fieldKey ?? '?'}>';
        child = _textBox(value, heightPx, selected, isField: true);
      case LabelElementType.barcode:
        final value = data[element.fieldKey] ?? '<${element.fieldKey ?? '?'}>';
        child = _barcodeBox(value, heightPx, scale, selected);
    }

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onTap: () => onElementTap?.call(element.id),
        onPanUpdate: onElementDrag == null
            ? null
            : (d) => onElementDrag!(
                  element.id,
                  d.delta.dx / scale,
                  d.delta.dy / scale,
                ),
        child: child,
      ),
    );
  }

  Widget _textBox(String text, double heightPx, bool selected, {bool isField = false}) {
    final fontSize = heightPx.clamp(8, 80).toDouble();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: isField ? const Color(0x1A003366) : null,
        border: Border.all(
          color: selected ? const Color(0xFF003366) : CupertinoColors.systemGrey3,
          width: selected ? 2 : 1,
        ),
      ),
      child: Text(
        text.isEmpty ? ' ' : text,
        style: TextStyle(
          fontSize: fontSize,
          color: CupertinoColors.black,
          height: 1.0,
        ),
        maxLines: 1,
        overflow: TextOverflow.visible,
        softWrap: false,
      ),
    );
  }

  Widget _barcodeBox(String value, double heightPx, double scale, bool selected) {
    final width = (value.length * 6.0).clamp(80.0, 260.0);
    return Container(
      width: width,
      height: heightPx + 12,
      decoration: BoxDecoration(
        border: Border.all(
          color: selected ? const Color(0xFF003366) : CupertinoColors.systemGrey3,
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: CustomPaint(
              size: Size(width, heightPx),
              painter: _BarcodeStripePainter(value),
            ),
          ),
          Text(value, style: const TextStyle(fontSize: 9)),
        ],
      ),
    );
  }
}

/// Pseudo-Code128 stripe pattern for visual preview only — not a valid
/// barcode. The printer renders the real code-128 symbol from the ZPL
/// ^BC command at print time.
class _BarcodeStripePainter extends CustomPainter {
  final String value;

  _BarcodeStripePainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = CupertinoColors.black;
    final hash = value.codeUnits.fold<int>(0, (a, c) => (a * 31 + c) & 0xFFFF);
    final bars = 40;
    final barWidth = size.width / bars;
    for (var i = 0; i < bars; i++) {
      if (((hash >> (i % 16)) ^ i) & 1 == 1) {
        canvas.drawRect(
          Rect.fromLTWH(i * barWidth, 0, barWidth * 0.6, size.height),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarcodeStripePainter oldDelegate) =>
      oldDelegate.value != value;
}
