import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/label_design.dart';
import '../services/label_design_store.dart';
import '../services/label_zpl_renderer.dart';
import '../widgets/label_preview.dart';

const Color _primaryColor = Color(0xFF003366);

/// Drag-and-drop label editor. Elements live on the canvas at mm
/// coordinates; the palette at the bottom lets the user drop new
/// elements anywhere on the canvas. Tapping a placed element opens an
/// edit sheet (text / field binding / barcode / delete).
class LabelDesignerPage extends StatefulWidget {
  final SharedPreferences prefs;
  final LabelDesign design;

  const LabelDesignerPage({super.key, required this.prefs, required this.design});

  @override
  State<LabelDesignerPage> createState() => _LabelDesignerPageState();
}

class _LabelDesignerPageState extends State<LabelDesignerPage> {
  late final LabelDesign _design = widget.design.copy();
  late final LabelDesignStore _store = LabelDesignStore(widget.prefs);

  String? _selectedId;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(_design.name, overflow: TextOverflow.ellipsis),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _saving ? null : _save,
          child: _saving
              ? const CupertinoActivityIndicator()
              : const Icon(CupertinoIcons.checkmark_alt_circle),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _Header(
              design: _design,
              onRename: _rename,
              onPickSize: _pickSize,
            ),
            Expanded(child: _canvas()),
            _palette(),
          ],
        ),
      ),
    );
  }

  Widget _canvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return DragTarget<_PaletteItem>(
          onAcceptWithDetails: (details) {
            final box = context.findRenderObject() as RenderBox?;
            if (box == null) return;
            final local = box.globalToLocal(details.offset);
            _addElementAt(details.data, local, constraints.biggest);
          },
          builder: (context, _, _) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: LabelPreview(
                  design: _design,
                  data: demoBinding(),
                  maxWidth: constraints.maxWidth - 32,
                  maxHeight: constraints.maxHeight - 32,
                  selectedElementId: _selectedId,
                  onElementTap: _openElementEditor,
                  onBackgroundTap: () => setState(() => _selectedId = null),
                  onElementDrag: (id, dx, dy) {
                    setState(() {
                      final element = _design.elements.firstWhere((e) => e.id == id);
                      element.xMm = (element.xMm + dx).clamp(0, _design.widthMm - 2);
                      element.yMm = (element.yMm + dy).clamp(0, _design.heightMm - 2);
                      _selectedId = id;
                    });
                  },
                  onElementResize: (id, dx, dy) {
                    setState(() {
                      final element = _design.elements.firstWhere((e) => e.id == id);
                      element.widthMm = (element.widthMm + dx).clamp(
                        3,
                        _design.widthMm - element.xMm,
                      );
                      element.heightMm = (element.heightMm + dy).clamp(
                        2,
                        _design.heightMm - element.yMm,
                      );
                      _selectedId = id;
                    });
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _palette() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: CupertinoColors.systemGrey4)),
        color: CupertinoColors.systemGroupedBackground,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Drag onto the label',
              style: TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)),
          const SizedBox(height: 6),
          SizedBox(
            height: 60,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _paletteChip(const _PaletteItem.text()),
                _paletteChip(const _PaletteItem.barcode('Barcode No.')),
                for (final key in labelFieldKeys) _paletteChip(_PaletteItem.field(key)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _paletteChip(_PaletteItem item) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: LongPressDraggable<_PaletteItem>(
        data: item,
        delay: const Duration(milliseconds: 120),
        feedback: Opacity(opacity: 0.9, child: _chipBody(item, lifted: true)),
        childWhenDragging: Opacity(opacity: 0.3, child: _chipBody(item)),
        child: GestureDetector(
          onTap: () => _addElementAt(item, Offset.zero, Size(_design.widthMm, _design.heightMm)),
          child: _chipBody(item),
        ),
      ),
    );
  }

  Widget _chipBody(_PaletteItem item, {bool lifted = false}) {
    final label = switch (item.kind) {
      _PaletteKind.text => 'Text',
      _PaletteKind.field => item.fieldKey ?? 'Field',
      _PaletteKind.barcode => 'Barcode',
    };
    final icon = switch (item.kind) {
      _PaletteKind.text => CupertinoIcons.textformat,
      _PaletteKind.field => CupertinoIcons.tag,
      _PaletteKind.barcode => CupertinoIcons.barcode,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: lifted ? _primaryColor : CupertinoColors.systemGrey4,
          width: lifted ? 2 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: _primaryColor),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  void _addElementAt(_PaletteItem item, Offset dropOffset, Size canvasSize) {
    final scale = _scaleFor(canvasSize);
    final xMm = scale == 0 ? 4.0 : (dropOffset.dx / scale).clamp(0, _design.widthMm - 10).toDouble();
    final yMm = scale == 0 ? 4.0 : (dropOffset.dy / scale).clamp(0, _design.heightMm - 5).toDouble();

    final isBarcode = item.kind == _PaletteKind.barcode;
    final defaultWidth = isBarcode ? 40.0 : 30.0;
    final defaultHeight = isBarcode ? 12.0 : 4.0;
    final element = LabelElement(
      id: _freshId(),
      type: switch (item.kind) {
        _PaletteKind.text => LabelElementType.text,
        _PaletteKind.field => LabelElementType.field,
        _PaletteKind.barcode => LabelElementType.barcode,
      },
      xMm: xMm,
      yMm: yMm,
      widthMm: defaultWidth.clamp(3, _design.widthMm - xMm).toDouble(),
      heightMm: defaultHeight.clamp(2, _design.heightMm - yMm).toDouble(),
      text: item.kind == _PaletteKind.text ? 'Text' : null,
      fieldKey: item.fieldKey,
    );
    setState(() {
      _design.elements.add(element);
      _selectedId = element.id;
    });
  }

  double _scaleFor(Size canvasSize) {
    final byWidth = (canvasSize.width - 32) / _design.widthMm;
    final byHeight = (canvasSize.height - 32) / _design.heightMm;
    final s = byWidth < byHeight ? byWidth : byHeight;
    return s <= 0 ? 0 : s;
  }

  void _openElementEditor(String id) {
    final element = _design.elements.firstWhere((e) => e.id == id);
    setState(() => _selectedId = id);
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => _ElementEditorSheet(
        element: element,
        onChanged: (updated) {
          setState(() {
            final idx = _design.elements.indexWhere((e) => e.id == id);
            if (idx >= 0) _design.elements[idx] = updated;
          });
        },
        onDelete: () {
          setState(() {
            _design.elements.removeWhere((e) => e.id == id);
            _selectedId = null;
          });
          Navigator.pop(ctx);
        },
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await _store.save(_design);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context, _design);
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: _design.name);
    final result = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Rename design'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: CupertinoTextField(controller: controller, autofocus: true),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      setState(() => _design.name = result);
    }
  }

  Future<void> _pickSize() async {
    final picked = await showCupertinoModalPopup<LabelSize>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Label size'),
        actions: [
          for (final s in LabelSize.presets)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(ctx, s),
              child: Text(s.name),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      _design.widthMm = picked.widthMm;
      _design.heightMm = picked.heightMm;
      for (final element in _design.elements) {
        element.xMm = element.xMm.clamp(0, _design.widthMm - 2);
        element.yMm = element.yMm.clamp(0, _design.heightMm - 2);
        element.widthMm = element.widthMm.clamp(3, _design.widthMm - element.xMm);
        element.heightMm = element.heightMm.clamp(2, _design.heightMm - element.yMm);
      }
    });
  }

  int _counter = 0;
  String _freshId() {
    _counter++;
    return 'el_${DateTime.now().microsecondsSinceEpoch}_$_counter';
  }
}

class _Header extends StatelessWidget {
  final LabelDesign design;
  final VoidCallback onRename;
  final VoidCallback onPickSize;

  const _Header({
    required this.design,
    required this.onRename,
    required this.onPickSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: CupertinoColors.systemGrey5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onRename,
              child: Row(
                children: [
                  const Icon(CupertinoIcons.pencil, size: 16, color: CupertinoColors.systemGrey),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(design.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onPickSize,
            child: Row(
              children: [
                const Icon(CupertinoIcons.fullscreen, size: 16, color: CupertinoColors.systemGrey),
                const SizedBox(width: 4),
                Text('${design.widthMm.toStringAsFixed(0)} × ${design.heightMm.toStringAsFixed(0)} mm',
                    style: const TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ElementEditorSheet extends StatefulWidget {
  final LabelElement element;
  final ValueChanged<LabelElement> onChanged;
  final VoidCallback onDelete;

  const _ElementEditorSheet({
    required this.element,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<_ElementEditorSheet> createState() => _ElementEditorSheetState();
}

class _ElementEditorSheetState extends State<_ElementEditorSheet> {
  late final LabelElement _working = widget.element.copy();
  late final TextEditingController _textController =
      TextEditingController(text: _working.text ?? '');

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged(_working.copy());

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CupertinoColors.systemBackground,
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_typeLabel(_working.type),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          if (_working.type == LabelElementType.text) ...[
            const Text('Text', style: TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)),
            const SizedBox(height: 4),
            CupertinoTextField(
              controller: _textController,
              onChanged: (v) {
                _working.text = v;
                _emit();
              },
            ),
            const SizedBox(height: 14),
          ],
          if (_working.type != LabelElementType.text) ...[
            const Text('Field', style: TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)),
            const SizedBox(height: 4),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 10),
              color: CupertinoColors.systemGrey6,
              onPressed: _pickField,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_working.fieldKey ?? 'Pick a field…',
                    style: const TextStyle(color: CupertinoColors.black)),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Text('Width: ${_working.widthMm.toStringAsFixed(1)} mm',
              style: const TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)),
          CupertinoSlider(
            min: 3,
            max: 150,
            divisions: 294,
            value: _working.widthMm.clamp(3, 150),
            onChanged: (v) {
              setState(() => _working.widthMm = v);
              _emit();
            },
          ),
          const SizedBox(height: 8),
          Text('Height: ${_working.heightMm.toStringAsFixed(1)} mm',
              style: const TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)),
          CupertinoSlider(
            min: 2,
            max: 80,
            divisions: 156,
            value: _working.heightMm.clamp(2, 80),
            onChanged: (v) {
              setState(() => _working.heightMm = v);
              _emit();
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  onPressed: widget.onDelete,
                  child: const Text('Delete', style: TextStyle(color: CupertinoColors.destructiveRed)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CupertinoButton.filled(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickField() async {
    final key = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Pick field'),
        actions: [
          for (final k in labelFieldKeys)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(ctx, k),
              child: Text(k),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (key != null) {
      setState(() => _working.fieldKey = key);
      _emit();
    }
  }

  String _typeLabel(LabelElementType t) => switch (t) {
        LabelElementType.text => 'Text',
        LabelElementType.field => 'Field',
        LabelElementType.barcode => 'Barcode',
      };
}

enum _PaletteKind { text, field, barcode }

class _PaletteItem {
  final _PaletteKind kind;
  final String? fieldKey;

  const _PaletteItem._(this.kind, this.fieldKey);
  const _PaletteItem.text() : this._(_PaletteKind.text, null);
  const _PaletteItem.field(String key) : this._(_PaletteKind.field, key);
  const _PaletteItem.barcode(String key) : this._(_PaletteKind.barcode, key);
}
