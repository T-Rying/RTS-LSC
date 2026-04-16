import 'package:flutter/cupertino.dart';
import '../services/barcode_repository.dart';

class BarcodeListPage extends StatefulWidget {
  final BarcodeRepository repo;

  const BarcodeListPage({super.key, required this.repo});

  @override
  State<BarcodeListPage> createState() => _BarcodeListPageState();
}

class _BarcodeListPageState extends State<BarcodeListPage> {
  late List<Map<String, dynamic>> _all;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _all = widget.repo.load();
  }

  List<Map<String, dynamic>> get _filtered {
    if (_query.isEmpty) return _all;
    final q = _query.toLowerCase();
    return _all.where((row) {
      return row.values.any((v) => v != null && v.toString().toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text('Barcodes (${_all.length})'),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: CupertinoSearchTextField(
                placeholder: 'Search',
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            if (list.isEmpty)
              const Expanded(
                child: Center(
                  child: Text('No rows',
                      style: TextStyle(color: CupertinoColors.systemGrey)),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (context, i) =>
                      Container(height: 1, color: CupertinoColors.systemGrey5),
                  itemBuilder: (context, i) => _BarcodeRow(row: list[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BarcodeRow extends StatelessWidget {
  final Map<String, dynamic> row;
  const _BarcodeRow({required this.row});

  (String, String) _summary() {
    String? pick(Iterable<String> keys) {
      for (final k in keys) {
        final v = row[k];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString();
      }
      return null;
    }

    final title = pick(const ['Barcode No.', 'barcode', 'BarcodeNo']) ?? '(no barcode)';
    final parts = <String>[];
    final item = pick(const ['Item No.', 'itemNo', 'ItemNo']);
    final desc = pick(const ['Description', 'description']);
    final variant = pick(const ['Variant Code']);
    final uom = pick(const ['Unit of Measure Code']);
    if (item != null) parts.add(item);
    if (desc != null) parts.add(desc);
    if (variant != null) parts.add('Variant $variant');
    if (uom != null) parts.add(uom);
    return (title, parts.join(' · '));
  }

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = _summary();
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      onPressed: () => _showDetail(context),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.label,
                    )),
                if (subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle,
                        style: const TextStyle(fontSize: 13, color: CupertinoColors.systemGrey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          ),
          const Icon(CupertinoIcons.chevron_forward, size: 16, color: CupertinoColors.systemGrey3),
        ],
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: CupertinoColors.systemBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Details',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  for (final entry in row.entries) ...[
                    Text(entry.key,
                        style: const TextStyle(
                            fontSize: 12, color: CupertinoColors.systemGrey)),
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 10),
                      child: Text(entry.value?.toString() ?? '',
                          style: const TextStyle(fontSize: 14)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
