import 'package:barcode_widget/barcode_widget.dart' as bw;
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
  final void Function(String elementId, double dxMm, double dyMm)? onElementResize;
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
    this.onElementResize,
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
    final widthPx = element.widthMm * scale;
    final heightPx = element.heightMm * scale;
    final selected = element.id == selectedElementId;

    Widget body;
    switch (element.type) {
      case LabelElementType.text:
        body = _textBox(element.text ?? '', widthPx, heightPx, selected);
      case LabelElementType.field:
        final value = data[element.fieldKey] ?? '<${element.fieldKey ?? '?'}>';
        body = _textBox(value, widthPx, heightPx, selected, isField: true);
      case LabelElementType.barcode:
        final value = data[element.fieldKey] ?? '<${element.fieldKey ?? '?'}>';
        body = _barcodeBox(
          value,
          widthPx,
          heightPx,
          selected,
          element.barcodeFormat ?? BarcodeFormat.code128,
        );
    }

    final tappable = GestureDetector(
      onTap: () => onElementTap?.call(element.id),
      onPanUpdate: onElementDrag == null
          ? null
          : (d) => onElementDrag!(
                element.id,
                d.delta.dx / scale,
                d.delta.dy / scale,
              ),
      child: body,
    );

    if (!selected || onElementResize == null) {
      return Positioned(left: left, top: top, child: tappable);
    }

    return Positioned(
      left: left,
      top: top,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          tappable,
          Positioned(
            right: -8,
            bottom: -8,
            child: GestureDetector(
              onPanUpdate: (d) => onElementResize!(
                element.id,
                d.delta.dx / scale,
                d.delta.dy / scale,
              ),
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: Color(0xFF003366),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.arrow_up_left_arrow_down_right,
                  size: 12,
                  color: CupertinoColors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _textBox(String text, double widthPx, double heightPx, bool selected, {bool isField = false}) {
    final innerWidth = (widthPx - 4).clamp(10, 2000);
    final innerHeight = (heightPx - 2).clamp(6, 400);
    final fontSize = _fitFontSize(text.isEmpty ? ' ' : text, innerWidth.toDouble(), innerHeight.toDouble());
    return Container(
      width: widthPx.clamp(10, 2000),
      height: heightPx.clamp(6, 400),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      decoration: BoxDecoration(
        color: isField ? const Color(0x1A003366) : null,
        border: Border.all(
          color: selected ? const Color(0xFF003366) : CupertinoColors.systemGrey3,
          width: selected ? 2 : 1,
        ),
      ),
      child: ClipRect(
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text.isEmpty ? ' ' : text,
            style: TextStyle(
              fontSize: fontSize,
              color: CupertinoColors.black,
              height: _lineHeightFactor,
            ),
            overflow: TextOverflow.clip,
            softWrap: true,
          ),
        ),
      ),
    );
  }

  /// Binary-searches for the largest font size where `text` wraps within
  /// `maxWidth` and still fits inside `maxHeight`.
  double _fitFontSize(String text, double maxWidth, double maxHeight) {
    if (maxWidth <= 0 || maxHeight <= 0) return 6;
    double lo = 5;
    double hi = maxHeight.clamp(5, 200).toDouble();
    // Expand hi a little so single short strings can get bigger than the box height
    hi = (hi < 8) ? 8 : hi;
    while (hi - lo > 0.5) {
      final mid = (lo + hi) / 2;
      if (_textFits(text, mid, maxWidth, maxHeight)) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  bool _textFits(String text, double fontSize, double maxWidth, double maxHeight) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, height: _lineHeightFactor),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    return painter.height <= maxHeight && painter.width <= maxWidth + 0.5;
  }

  static const double _lineHeightFactor = 1.15;

  Widget _barcodeBox(
    String value,
    double widthPx,
    double heightPx,
    bool selected,
    BarcodeFormat format,
  ) {
    final safeWidth = widthPx.clamp(20, 2000).toDouble();
    final safeHeight = heightPx.clamp(10, 400).toDouble();
    return Container(
      width: safeWidth,
      height: safeHeight,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        border: Border.all(
          color: selected ? const Color(0xFF003366) : CupertinoColors.systemGrey3,
          width: selected ? 2 : 1,
        ),
      ),
      child: bw.BarcodeWidget(
        data: value.isEmpty ? ' ' : value,
        barcode: _toBarcode(format),
        width: safeWidth - 4,
        height: safeHeight - 4,
        drawText: true,
        style: const TextStyle(fontSize: 9, color: CupertinoColors.black),
        color: CupertinoColors.black,
        errorBuilder: (ctx, error) => Center(
          child: Text(
            'Invalid for ${format.displayName}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 9,
              color: CupertinoColors.destructiveRed,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  static bw.Barcode _toBarcode(BarcodeFormat f) {
    switch (f) {
      case BarcodeFormat.ean13:
        return bw.Barcode.ean13();
      case BarcodeFormat.ean8:
        return bw.Barcode.ean8();
      case BarcodeFormat.upcA:
        return bw.Barcode.upcA();
      case BarcodeFormat.code128:
        return bw.Barcode.code128();
      case BarcodeFormat.code39:
        return bw.Barcode.code39();
      case BarcodeFormat.qr:
        return bw.Barcode.qrCode();
    }
  }
}
