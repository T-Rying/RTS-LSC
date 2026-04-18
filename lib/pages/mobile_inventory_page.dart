import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/environment_config.dart';
import '../services/inventory_service.dart';
import '../services/item_lookup_service.dart';
import '../services/log_service.dart';
import '../services/replication_store.dart';
import 'item_card_page.dart';
import 'product_scanner_page.dart';
import 'replication_data_page.dart';

const Color _primaryColor = Color(0xFF003366);

/// Descriptor for one replicable entity — wires up the SOAP fetch, local
/// storage key, viewer title, and how each row should be summarized.
class _Entity {
  final String key;
  final String displayName;
  final IconData icon;
  final Future<List<Map<String, dynamic>>> Function(InventoryService, EnvironmentConfig) fetch;
  final RowSummarizer summarize;

  const _Entity({
    required this.key,
    required this.displayName,
    required this.icon,
    required this.fetch,
    required this.summarize,
  });
}

final _entities = <_Entity>[
  _Entity(
    key: 'barcodes',
    displayName: 'Barcodes',
    icon: CupertinoIcons.barcode,
    fetch: (svc, cfg) => svc.getBarcodes(cfg),
    summarize: _summarizeBarcode,
  ),
  _Entity(
    key: 'item_categories',
    displayName: 'Item Categories',
    icon: CupertinoIcons.square_stack_3d_up,
    fetch: (svc, cfg) => svc.getItemCategories(cfg),
    summarize: _summarizeItemCategory,
  ),
  _Entity(
    key: 'item_variants',
    displayName: 'Item Variants',
    icon: CupertinoIcons.square_grid_2x2,
    fetch: (svc, cfg) => svc.getItemVariants(cfg),
    summarize: _summarizeItemVariant,
  ),
  _Entity(
    key: 'sales_prices',
    displayName: 'Sales Prices',
    icon: CupertinoIcons.tag,
    fetch: (svc, cfg) => svc.getSalesPrices(cfg),
    summarize: _summarizeSalesPrice,
  ),
  _Entity(
    key: 'item_unit_of_measures',
    displayName: 'Item Units of Measure',
    icon: CupertinoIcons.cube_box,
    fetch: (svc, cfg) => svc.getItemUnitOfMeasures(cfg),
    summarize: _summarizeItemUnitOfMeasure,
  ),
  _Entity(
    key: 'stores',
    displayName: 'Stores',
    icon: CupertinoIcons.building_2_fill,
    fetch: (svc, cfg) => svc.getStores(cfg),
    summarize: _summarizeStore,
  ),
];

(String, String) _summarizeBarcode(Map<String, dynamic> row) {
  final title = _pick(row, const ['Barcode No.']) ?? '(no barcode)';
  final parts = <String>[];
  final item = _pick(row, const ['Item No.']);
  final desc = _pick(row, const ['Description']);
  final variant = _pick(row, const ['Variant Code']);
  final uom = _pick(row, const ['Unit of Measure Code']);
  if (item != null) parts.add(item);
  if (desc != null) parts.add(desc);
  if (variant != null) parts.add('Variant $variant');
  if (uom != null) parts.add(uom);
  return (title, parts.join(' · '));
}

(String, String) _summarizeItemCategory(Map<String, dynamic> row) {
  final title = _pick(row, const ['Code']) ?? '(no code)';
  final desc = _pick(row, const ['Description']) ?? '';
  final parent = _pick(row, const ['Parent Category']);
  final subtitle = [desc, if (parent != null) 'Parent: $parent'].where((s) => s.isNotEmpty).join(' · ');
  return (title, subtitle);
}

(String, String) _summarizeItemVariant(Map<String, dynamic> row) {
  final item = _pick(row, const ['Item No.']) ?? '';
  final code = _pick(row, const ['Code']) ?? '';
  final title = [item, code].where((s) => s.isNotEmpty).join(' · ');
  final desc = _pick(row, const ['Description']) ?? '';
  return (title.isEmpty ? '(no variant)' : title, desc);
}

(String, String) _summarizeSalesPrice(Map<String, dynamic> row) {
  final item = _pick(row, const ['Item No.']) ?? '';
  final price = _pick(row, const ['Unit Price']) ?? _pick(row, const ['Sales Price']) ?? '';
  final currency = _pick(row, const ['Currency Code']);
  final title = [item, if (price.isNotEmpty) price, ?currency]
      .where((s) => s.isNotEmpty)
      .join(' · ');
  final parts = <String>[];
  final variant = _pick(row, const ['Variant Code']);
  final uom = _pick(row, const ['Unit of Measure Code']);
  final salesType = _pick(row, const ['Sales Type']);
  final salesCode = _pick(row, const ['Sales Code']);
  if (variant != null) parts.add('Variant $variant');
  if (uom != null) parts.add(uom);
  if (salesType != null) {
    parts.add(salesCode != null ? '$salesType: $salesCode' : salesType);
  }
  return (title.isEmpty ? '(no price)' : title, parts.join(' · '));
}

(String, String) _summarizeStore(Map<String, dynamic> row) {
  final no = _pick(row, const ['No.']) ?? '(no code)';
  final name = _pick(row, const ['Name']);
  final city = _pick(row, const ['City']);
  final country = _pick(row, const ['Country Code']);
  final parts = <String>[];
  if (name != null) parts.add(name);
  final loc = <String>[];
  if (city != null) loc.add(city);
  if (country != null) loc.add(country);
  if (loc.isNotEmpty) parts.add(loc.join(', '));
  return (no, parts.join(' · '));
}

(String, String) _summarizeItemUnitOfMeasure(Map<String, dynamic> row) {
  final item = _pick(row, const ['Item No.']) ?? '';
  final code = _pick(row, const ['Code']) ?? '';
  final title = [item, code].where((s) => s.isNotEmpty).join(' · ');
  final parts = <String>[];
  final qtyPer = _pick(row, const ['Qty. per Unit of Measure']);
  final description = _pick(row, const ['Description']);
  if (qtyPer != null) parts.add('Qty/UOM $qtyPer');
  if (description != null) parts.add(description);
  return (title.isEmpty ? '(no UOM)' : title, parts.join(' · '));
}

String? _pick(Map<String, dynamic> row, Iterable<String> keys) {
  for (final k in keys) {
    final v = row[k];
    if (v != null && v.toString().trim().isNotEmpty) return v.toString();
  }
  return null;
}

class MobileInventoryPage extends StatefulWidget {
  final EnvironmentConfig config;

  const MobileInventoryPage({super.key, required this.config});

  @override
  State<MobileInventoryPage> createState() => _MobileInventoryPageState();
}

class _MobileInventoryPageState extends State<MobileInventoryPage> {
  SharedPreferences? _prefs;
  final _log = LogService.instance;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() => _prefs = p);
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Mobile Inventory'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _log.share,
          child: const Icon(CupertinoIcons.paperplane),
        ),
      ),
      child: SafeArea(
        child: _prefs == null
            ? const Center(child: CupertinoActivityIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text('Lookup',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _ScanItemCard(prefs: _prefs!),
                  const SizedBox(height: 20),
                  const Text('Replication',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  for (final entity in _entities) ...[
                    _EntityCard(
                      config: widget.config,
                      prefs: _prefs!,
                      entity: entity,
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
      ),
    );
  }
}

class _ScanItemCard extends StatelessWidget {
  final SharedPreferences prefs;
  const _ScanItemCard({required this.prefs});

  Future<void> _scan(BuildContext context) async {
    final scanned = await Navigator.push<String>(
      context,
      CupertinoPageRoute(builder: (_) => const ProductScannerPage()),
    );
    if (scanned == null || !context.mounted) return;

    final card = ItemLookupService(prefs).lookup(scanned);
    if (!context.mounted) return;
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => ItemCardPage(scannedBarcode: scanned, card: card),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CupertinoColors.systemGrey5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: const [
              Icon(CupertinoIcons.barcode_viewfinder, color: _primaryColor, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text('Scan Item',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Scan a product barcode to look up the item from replicated data.',
            style: TextStyle(fontSize: 13, color: CupertinoColors.systemGrey),
          ),
          const SizedBox(height: 14),
          CupertinoButton.filled(
            padding: const EdgeInsets.symmetric(vertical: 10),
            onPressed: () => _scan(context),
            child: const Text('Scan'),
          ),
        ],
      ),
    );
  }
}

class _EntityCard extends StatefulWidget {
  final EnvironmentConfig config;
  final SharedPreferences prefs;
  final _Entity entity;

  const _EntityCard({
    required this.config,
    required this.prefs,
    required this.entity,
  });

  @override
  State<_EntityCard> createState() => _EntityCardState();
}

class _EntityCardState extends State<_EntityCard> {
  final _inventory = InventoryService();
  final _log = LogService.instance;

  late final ReplicationStore _store = ReplicationStore(widget.prefs, widget.entity.key);
  late ReplicationMeta? _meta = _store.meta();
  bool _loading = false;
  String? _error;

  Future<void> _replicate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.entity.fetch(_inventory, widget.config);
      await _store.replace(rows);
      if (!mounted) return;
      setState(() {
        _meta = _store.meta();
        _loading = false;
      });
    } catch (e) {
      _log.error('${widget.entity.displayName} replication failed: $e');
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
        builder: (_) => ReplicationDataPage(
          title: widget.entity.displayName,
          store: _store,
          summarize: widget.entity.summarize,
        ),
      ),
    );
  }

  Future<void> _deleteData() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('Delete ${widget.entity.displayName}?'),
        content: const Text(
          'This will remove the locally stored data. You can replicate it again at any time.',
        ),
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
    await _store.clear();
    if (!mounted) return;
    setState(() {
      _meta = _store.meta();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasData = (_meta?.count ?? 0) > 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CupertinoColors.systemGrey5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(widget.entity.icon, color: _primaryColor, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(widget.entity.displayName,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
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
                  onPressed: _loading ? null : _replicate,
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
          const SizedBox(height: 8),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: 10),
            onPressed: hasData && !_loading ? _deleteData : null,
            child: const Text(
              'Delete Local Data',
              style: TextStyle(color: CupertinoColors.destructiveRed),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(color: CupertinoColors.destructiveRed, fontSize: 13)),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}
