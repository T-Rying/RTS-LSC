import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/label_design.dart';
import '../services/label_design_store.dart';
import 'label_designer_page.dart';

const Color _primaryColor = Color(0xFF003366);

/// Lists saved label designs and offers create / import / export / delete.
/// Tapping a design opens the designer.
class LabelDesignsPage extends StatefulWidget {
  final SharedPreferences prefs;

  const LabelDesignsPage({super.key, required this.prefs});

  @override
  State<LabelDesignsPage> createState() => _LabelDesignsPageState();
}

class _LabelDesignsPageState extends State<LabelDesignsPage> {
  late final LabelDesignStore _store = LabelDesignStore(widget.prefs);
  late List<LabelDesign> _designs;
  String? _status;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() => _designs = _store.list());
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Label Designs'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _import,
              child: const Icon(CupertinoIcons.tray_arrow_down),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _createNew,
              child: const Icon(CupertinoIcons.add),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_designs.isEmpty)
              const Text(
                'No designs yet. Tap + to create one, or the inbox icon to import.',
                style: TextStyle(color: CupertinoColors.systemGrey, fontSize: 14),
              ),
            for (final design in _designs) ...[
              _DesignRow(
                design: design,
                onTap: () => _openDesigner(design),
                onExport: () => _export(design),
                onDelete: () => _delete(design),
              ),
              const SizedBox(height: 10),
            ],
            if (_status != null) ...[
              const SizedBox(height: 12),
              Text(_status!,
                  style: const TextStyle(color: CupertinoColors.systemGrey, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _createNew() async {
    final size = await showCupertinoModalPopup<LabelSize>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('New label — pick a size'),
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
    if (size == null || !mounted) return;
    final design = LabelDesign.empty(size: size);
    await _store.save(design);
    if (!mounted) return;
    _reload();
    _openDesigner(design);
  }

  Future<void> _openDesigner(LabelDesign design) async {
    await Navigator.push<LabelDesign>(
      context,
      CupertinoPageRoute(
        builder: (_) => LabelDesignerPage(prefs: widget.prefs, design: design),
      ),
    );
    if (!mounted) return;
    _reload();
  }

  Future<void> _export(LabelDesign design) async {
    final json = _store.exportDesign(design);
    try {
      final dir = await getTemporaryDirectory();
      final safeName = design.name.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
      final file = File('${dir.path}/label_$safeName.json');
      await file.writeAsString(json);
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Label design: ${design.name}',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Export failed: $e');
    }
  }

  Future<void> _import() async {
    final controller = TextEditingController();
    final result = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Import design'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Paste the exported JSON here.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 6),
              CupertinoTextField(
                controller: controller,
                autofocus: true,
                maxLines: 6,
                minLines: 3,
                placeholder: '{"id":"…","name":"…","widthMm":…,…}',
              ),
              const SizedBox(height: 6),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () async {
                  final data = await Clipboard.getData('text/plain');
                  if (data?.text != null) controller.text = data!.text!;
                },
                child: const Text('Paste from clipboard'),
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (result == null || result.trim().isEmpty) return;
    try {
      final imported = await _store.importDesignJson(result);
      if (!mounted) return;
      setState(() => _status = 'Imported "${imported.name}".');
      _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Import failed: $e');
    }
  }

  Future<void> _delete(LabelDesign design) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('Delete ${design.name}?'),
        content: const Text('This cannot be undone.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _store.delete(design.id);
    if (!mounted) return;
    _reload();
  }
}

class _DesignRow extends StatelessWidget {
  final LabelDesign design;
  final VoidCallback onTap;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  const _DesignRow({
    required this.design,
    required this.onTap,
    required this.onExport,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: CupertinoColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: CupertinoColors.systemGrey5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(CupertinoIcons.square_stack, color: _primaryColor, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(design.name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                Text('${design.widthMm.toStringAsFixed(0)} × ${design.heightMm.toStringAsFixed(0)} mm',
                    style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey)),
              ],
            ),
            const SizedBox(height: 6),
            Text('${design.elements.length} element${design.elements.length == 1 ? '' : 's'} · updated ${_ago(design.updatedAt)}',
                style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    onPressed: onExport,
                    child: const Text('Export'),
                  ),
                ),
                Expanded(
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    onPressed: onDelete,
                    child: const Text('Delete',
                        style: TextStyle(color: CupertinoColors.destructiveRed)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _ago(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours} h ago';
    return '${diff.inDays} d ago';
  }
}
