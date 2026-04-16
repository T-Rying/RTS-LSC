import 'package:flutter/cupertino.dart';
import '../services/replication_store.dart';

typedef RowSummarizer = (String, String) Function(Map<String, dynamic>);

/// Generic searchable viewer over a ReplicationStore. Each entity supplies
/// its own [summarize] to choose the title/subtitle for each row.
class ReplicationDataPage extends StatefulWidget {
  final String title;
  final ReplicationStore store;
  final RowSummarizer summarize;

  const ReplicationDataPage({
    super.key,
    required this.title,
    required this.store,
    required this.summarize,
  });

  @override
  State<ReplicationDataPage> createState() => _ReplicationDataPageState();
}

class _ReplicationDataPageState extends State<ReplicationDataPage> {
  late List<Map<String, dynamic>> _all;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _all = widget.store.load();
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
        middle: Text('${widget.title} (${_all.length})'),
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
                  itemBuilder: (context, i) => _DataRow(
                    row: list[i],
                    summarize: widget.summarize,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  final Map<String, dynamic> row;
  final RowSummarizer summarize;

  const _DataRow({required this.row, required this.summarize});

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = summarize(row);
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
