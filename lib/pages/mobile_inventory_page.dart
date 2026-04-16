import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/environment_config.dart';
import '../services/barcode_repository.dart';
import '../services/inventory_service.dart';
import '../services/log_service.dart';
import 'barcode_list_page.dart';

const Color _primaryColor = Color(0xFF003366);

class MobileInventoryPage extends StatefulWidget {
  final EnvironmentConfig config;

  const MobileInventoryPage({super.key, required this.config});

  @override
  State<MobileInventoryPage> createState() => _MobileInventoryPageState();
}

class _MobileInventoryPageState extends State<MobileInventoryPage> {
  final _inventory = InventoryService();
  final _log = LogService.instance;

  BarcodeRepository? _repo;
  BarcodeReplicationMeta? _meta;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final repo = BarcodeRepository(prefs);
    if (!mounted) return;
    setState(() {
      _repo = repo;
      _meta = repo.meta();
    });
  }

  Future<void> _replicateBarcodes() async {
    if (_repo == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _inventory.getBarcodes(widget.config);
      await _repo!.replace(rows);
      if (!mounted) return;
      setState(() {
        _meta = _repo!.meta();
        _loading = false;
      });
    } catch (e) {
      _log.error('Barcode replication failed: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _openViewer() {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => BarcodeListPage(repo: _repo!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasData = (_meta?.count ?? 0) > 0;

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Mobile Inventory')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _SectionTitle('Replication'),
            const SizedBox(height: 8),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(CupertinoIcons.barcode, color: _primaryColor, size: 22),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text('Barcodes',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                      ),
                      if (hasData)
                        Text('${_meta!.count} rows',
                            style: const TextStyle(color: CupertinoColors.systemGrey, fontSize: 13)),
                    ],
                  ),
                  if (_meta?.lastReplicatedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Last replicated: ${_formatTime(_meta!.lastReplicatedAt!)}',
                        style: const TextStyle(color: CupertinoColors.systemGrey, fontSize: 13),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: CupertinoButton.filled(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          onPressed: _loading ? null : _replicateBarcodes,
                          child: _loading
                              ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                              : Text(hasData ? 'Re-replicate' : 'Replicate'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          onPressed: hasData && !_loading ? _openViewer : null,
                          child: const Text('View Data'),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: const TextStyle(color: CupertinoColors.destructiveRed, fontSize: 13)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);
  @override
  Widget build(BuildContext context) =>
      Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600));
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CupertinoColors.systemGrey5),
      ),
      child: child,
    );
  }
}
