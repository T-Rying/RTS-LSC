import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dining_area_layout.dart';
import '../models/dining_table.dart';
import '../models/dining_table_status.dart';
import '../models/environment_config.dart';
import '../models/hospitality_type.dart';
import '../services/hospitality_service.dart';
import '../services/log_service.dart';
import '../services/replication_store.dart';

const Color _primaryColor = Color(0xFF003366);

/// Visual styling for a live `Dining_Table_Status` value. Matched
/// case-insensitively with fallback to a neutral grey so unknown
/// values from future LS Central releases still render sensibly.
class _StatusStyle {
  final Color fill;
  final Color border;
  final Color text;
  final String label;
  const _StatusStyle(this.fill, this.border, this.text, this.label);
}

_StatusStyle _styleForStatus(DiningTableStatus? s) {
  final raw = (s?.status ?? '').trim();
  if (raw.isEmpty) {
    return _StatusStyle(
      CupertinoColors.systemGrey5,
      CupertinoColors.systemGrey2,
      CupertinoColors.systemGrey,
      'Unknown',
    );
  }
  switch (raw.toLowerCase()) {
    case 'free':
    case 'available':
      return const _StatusStyle(
        Color(0xFFE4F6E7), Color(0xFF2F9E44), Color(0xFF1F6F32), 'Free',
      );
    case 'occupied':
    case 'seated':
    case 'ordered':
      return const _StatusStyle(
        Color(0xFFFDE1E1), Color(0xFFD14343), Color(0xFF8E1E1E), 'Seated',
      );
    case 'reserved':
      return const _StatusStyle(
        Color(0xFFE0ECFF), Color(0xFF2E5AAC), Color(0xFF1C3B73), 'Reserved',
      );
    case 'bill':
    case 'bill printed':
    case 'bill-printed':
      return const _StatusStyle(
        Color(0xFFFFEBD4), Color(0xFFD27D1A), Color(0xFF7B4308), 'Bill',
      );
    case 'dirty':
    case 'needs cleaning':
    case 'needscleaning':
    case 'cleaning':
      return const _StatusStyle(
        Color(0xFFFFF4C2), Color(0xFFB58900), Color(0xFF6B4F00), 'Needs cleaning',
      );
    case 'closed':
    case 'out of service':
      return const _StatusStyle(
        Color(0xFFE5E5E5), Color(0xFF8A8A8A), Color(0xFF4A4A4A), 'Closed',
      );
    default:
      return _StatusStyle(
        CupertinoColors.systemGrey5,
        CupertinoColors.systemGrey2,
        CupertinoColors.systemGrey,
        raw,
      );
  }
}

/// Hospitality view — driven by the `HospitalityTypes` OData entity.
///
/// Navigation is a two-step cascade:
///   1. **Restaurant** (e.g. `S0005`, `S0008`, `T0100`) — unique
///      `Restaurant_No` values from the hospitality types list.
///   2. **Hospitality type** (e.g. `RESTAURANT · Restaurant Downstairs`)
///      — the types defined for that restaurant, ordered by their
///      configured Sequence.
///
/// Once a type is chosen the page shows:
///   - A configuration card (service type, service flow, order id,
///     layout view, queue counter, max guests).
///   - If the type has a `Dining_Area_ID` + `Current_Din_Area_Layout_Code`
///     — the matching `DiningAreaLayout` metadata (description, capacity,
///     in-use / available / combined counts) and the graphical canvas
///     drawn from `DiningTableLayout`.
///   - If it doesn't (counter / drive-thru / delivery) — a note
///     explaining why there is no floor plan for this type.
///
/// `InteractiveViewer` handles pinch-zoom and pan on the canvas so
/// larger restaurants stay legible on a phone screen.
class HospitalityPage extends StatefulWidget {
  final EnvironmentConfig config;

  const HospitalityPage({super.key, required this.config});

  @override
  State<HospitalityPage> createState() => _HospitalityPageState();
}

class _HospitalityPageState extends State<HospitalityPage> {
  final _service = HospitalityService();
  final _log = LogService.instance;

  HospitalityLayout? _layout;
  String? _restaurant;
  HospitalityType? _type;
  bool _loading = true;
  bool _updatingStatus = false;
  String? _error;
  DiningTable? _tappedTable;

  /// Targets we offer from a Free table. Must match the LS Central
  /// `Dining_Table_Status` option enum exactly — BC rejects unknown
  /// values with `Application_InvalidOptionEnumValue`. The stock
  /// enum on LS Central Cronus is: Free, Seated, Occupied,
  /// To Be Cleaned. "Seated" is the normal waiter transition; keeping
  /// "Occupied" as an alternative for back-office use.
  static const List<String> _statusTargets = ['Seated', 'Occupied'];

  /// Restaurant_No → real store name, sourced from the locally
  /// replicated Store buffer (`ReplicationStore(prefs, 'stores')`).
  /// Empty until the user replicates Stores in Mobile Inventory; when
  /// empty we fall back to deriving names from hospitality types.
  Map<String, String> _storeNames = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final storeNames = _readStoreNames(prefs);
      final layout = await _service.fetchLayout(widget.config);
      if (!mounted) return;
      _layout = layout;
      _storeNames = storeNames;
      _selectInitialFilters();
      setState(() => _loading = false);
    } catch (e) {
      _log.error('Hospitality: fetch failed: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Reads the replicated Store table (if any) and builds a lookup of
  /// `No.` → `Name`. Empty rows are skipped so missing-name entries
  /// fall through to the hospitality-type-derived fallback.
  static Map<String, String> _readStoreNames(SharedPreferences prefs) {
    final rows = ReplicationStore(prefs, 'stores').load();
    final names = <String, String>{};
    for (final row in rows) {
      final no = row['No.']?.toString().trim();
      final name = row['Name']?.toString().trim();
      if (no != null && no.isNotEmpty && name != null && name.isNotEmpty) {
        names[no] = name;
      }
    }
    return names;
  }

  void _selectInitialFilters() {
    final layout = _layout;
    if (layout == null) return;
    final restaurants = layout.restaurants();
    _restaurant = restaurants.isNotEmpty ? restaurants.first : null;
    final types = _restaurant == null ? <HospitalityType>[] : layout.typesFor(_restaurant!);
    _type = types.isNotEmpty ? types.first : null;
    _tappedTable = null;
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Hospitality'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _loading ? null : _load,
          child: const Icon(CupertinoIcons.refresh),
        ),
      ),
      child: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CupertinoActivityIndicator());
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(CupertinoIcons.exclamationmark_triangle,
                size: 36, color: CupertinoColors.systemOrange),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            CupertinoButton.filled(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }
    final layout = _layout;
    if (layout == null || layout.types.isEmpty) {
      return const Center(child: Text('No hospitality types returned.'));
    }

    final type = _type;
    final tables = (type == null || !type.hasDiningArea)
        ? const <DiningTable>[]
        : layout.tablesFor(type.diningAreaId, type.currentLayoutCode);
    final meta = (type == null || !type.hasDiningArea)
        ? null
        : layout.metaFor(type.diningAreaId, type.currentLayoutCode);
    final DiningTableStatus? tappedStatus = _tappedTable == null
        ? null
        : layout.statusFor(_tappedTable!.areaId, _tappedTable!.tableNo);

    return Column(
      children: [
        _FiltersBar(
          restaurants: layout.restaurants(),
          types: _restaurant == null ? const [] : layout.typesFor(_restaurant!),
          restaurant: _restaurant,
          restaurantLabel: _restaurant == null
              ? null
              : layout.restaurantLabel(_restaurant!, storeNames: _storeNames),
          type: type,
          onPickRestaurant: _pickRestaurant,
          onPickType: _pickType,
        ),
        if (type != null) _TypeCard(type: type),
        if (type != null && type.hasDiningArea && meta != null)
          _MetaCard(meta: meta, tableCount: tables.length),
        Expanded(
          child: _canvasArea(type, tables, layout),
        ),
        if (_tappedTable != null)
          _TableDetails(
            table: _tappedTable!,
            status: tappedStatus,
            busy: _updatingStatus,
            onChangeStatus: (tappedStatus != null && tappedStatus.isFree)
                ? () => _changeStatus(_tappedTable!, tappedStatus)
                : null,
          ),
      ],
    );
  }

  Widget _canvasArea(
      HospitalityType? type, List<DiningTable> tables, HospitalityLayout layout) {
    if (type == null) {
      return const SizedBox.shrink();
    }
    if (!type.hasDiningArea) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(CupertinoIcons.square_stack, size: 36, color: CupertinoColors.systemGrey3),
              const SizedBox(height: 10),
              Text(
                'No graphical floor plan for this type.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: CupertinoColors.systemGrey),
              ),
              const SizedBox(height: 4),
              Text(
                type.serviceType.isEmpty
                    ? 'This hospitality type uses an order-list-style view.'
                    : '${type.serviceType} · ${type.layoutView}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey),
              ),
            ],
          ),
        ),
      );
    }
    if (tables.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No drawn tables for the current layout.\n'
            'Area metadata is shown above.',
            textAlign: TextAlign.center,
            style: TextStyle(color: CupertinoColors.systemGrey),
          ),
        ),
      );
    }
    return _Canvas(
      tables: tables,
      selectedTable: _tappedTable,
      statusLookup: (t) => layout.statusFor(t.areaId, t.tableNo),
      onTapTable: (t) => setState(() => _tappedTable = t),
    );
  }

  Future<void> _pickRestaurant() async {
    final layout = _layout;
    if (layout == null) return;
    final restaurants = layout.restaurants();
    final picked = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Restaurant'),
        actions: [
          for (final code in restaurants)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(ctx, code),
              child: Text(layout.restaurantLabel(code, storeNames: _storeNames)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (picked == null) return;
    final types = layout.typesFor(picked);
    setState(() {
      _restaurant = picked;
      _type = types.isNotEmpty ? types.first : null;
      _tappedTable = null;
    });
  }

  Future<void> _changeStatus(DiningTable table, DiningTableStatus status) async {
    if (_updatingStatus) return;
    if (!status.isFree) return;
    final picked = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text('Change table ${table.tableNo}'),
        message: const Text('Only free tables can be changed from the app.'),
        actions: [
          for (final target in _statusTargets)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(ctx, target),
              child: Text(target),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _updatingStatus = true);
    try {
      await _service.updateTableStatus(
        widget.config,
        areaId: status.areaId,
        tableNo: status.tableNo,
        etag: status.etag,
        newStatus: picked,
      );
      if (!mounted) return;
      await _load();
    } catch (e) {
      _log.error('Hospitality: status change failed: $e');
      if (!mounted) return;
      setState(() => _updatingStatus = false);
      await showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text("Couldn't change status"),
          content: Text(
            '$e\n\n'
            'The standard Dining Tables page may have the status field '
            'marked as read-only. In that case a page extension or a '
            'codeunit wrapper is needed to change status from the app.',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _pickType() async {
    final layout = _layout;
    if (layout == null || _restaurant == null) return;
    final types = layout.typesFor(_restaurant!);
    final picked = await showCupertinoModalPopup<HospitalityType>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Hospitality type'),
        actions: [
          for (final t in types)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(ctx, t),
              child: Text(t.displayLabel),
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
      _type = picked;
      _tappedTable = null;
    });
  }

}

class _FiltersBar extends StatelessWidget {
  final List<String> restaurants;
  final List<HospitalityType> types;
  final String? restaurant;
  final String? restaurantLabel;
  final HospitalityType? type;
  final VoidCallback onPickRestaurant;
  final VoidCallback onPickType;

  const _FiltersBar({
    required this.restaurants,
    required this.types,
    required this.restaurant,
    required this.restaurantLabel,
    required this.type,
    required this.onPickRestaurant,
    required this.onPickType,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: const BoxDecoration(
        color: CupertinoColors.systemGroupedBackground,
        border: Border(bottom: BorderSide(color: CupertinoColors.systemGrey4)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: _PickerButton(
              label: 'Restaurant',
              value: restaurantLabel ?? restaurant ?? '—',
              onTap: restaurants.isEmpty ? null : onPickRestaurant,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: _PickerButton(
              label: 'Hospitality type',
              value: type == null ? '—' : type!.displayLabel,
              onTap: types.isEmpty ? null : onPickType,
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerButton extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _PickerButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: CupertinoColors.white,
      onPressed: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: CupertinoColors.systemGrey)),
          const SizedBox(height: 2),
          Row(
            children: [
              Flexible(
                child: Text(value,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.black,
                        fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: 4),
              const Icon(CupertinoIcons.chevron_down,
                  size: 11, color: CupertinoColors.systemGrey),
            ],
          ),
        ],
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final HospitalityType type;

  const _TypeCard({required this.type});

  @override
  Widget build(BuildContext context) {
    final rows = <MapEntry<String, String>>[
      MapEntry('Service', type.serviceType),
      if (type.serviceFlowId.isNotEmpty)
        MapEntry('Service flow', type.serviceFlowId),
      if (type.orderId.isNotEmpty) MapEntry('Order id', type.orderId),
      if (type.layoutView.isNotEmpty) MapEntry('Layout view', type.layoutView),
      if (type.queueCounterCode.isNotEmpty)
        MapEntry('Queue counter', type.queueCounterCode),
      if (type.maxGuestsPerOrder > 0)
        MapEntry('Max guests', '${type.maxGuestsPerOrder}'),
      if (type.accessToOtherRestaurant.isNotEmpty)
        MapEntry('Cross-restaurant', type.accessToOtherRestaurant),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        border: Border.all(color: CupertinoColors.systemGrey5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  type.description.isEmpty ? type.salesType : type.description,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(type.salesType,
                    style: const TextStyle(
                        fontSize: 11,
                        color: _primaryColor,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final e in rows) _stat(e.key, e.value),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label:',
            style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey)),
        const SizedBox(width: 4),
        Text(value,
            style: const TextStyle(
                fontSize: 12, color: CupertinoColors.black, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _MetaCard extends StatelessWidget {
  final DiningAreaLayout meta;
  final int tableCount;

  const _MetaCard({required this.meta, required this.tableCount});

  @override
  Widget build(BuildContext context) {
    final description = meta.description.trim();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        border: Border.all(color: CupertinoColors.systemGrey5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  description.isEmpty
                      ? '${meta.areaId} · ${meta.layoutCode}'
                      : description,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${meta.areaId} · ${meta.layoutCode}',
                style: const TextStyle(fontSize: 11, color: CupertinoColors.systemGrey),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _stat('Capacity', '${meta.totalCapacity}'),
              _stat('Tables', '${meta.inUseDiningTables}'),
              _stat('Available', '${meta.availableDiningTables}'),
              if (meta.combinedTables > 0) _stat('Combined', '${meta.combinedTables}'),
              _stat('Drawn', '$tableCount'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label:',
            style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey)),
        const SizedBox(width: 4),
        Text(value,
            style: const TextStyle(
                fontSize: 12, color: CupertinoColors.black, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _Canvas extends StatelessWidget {
  final List<DiningTable> tables;
  final DiningTable? selectedTable;
  final DiningTableStatus? Function(DiningTable) statusLookup;
  final ValueChanged<DiningTable> onTapTable;

  const _Canvas({
    required this.tables,
    required this.selectedTable,
    required this.statusLookup,
    required this.onTapTable,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minX = tables.map((t) => t.x1).reduce(math.min);
        final maxX = tables.map((t) => t.x2).reduce(math.max);
        final minY = tables.map((t) => t.y1).reduce(math.min);
        final maxY = tables.map((t) => t.y2).reduce(math.max);
        final spanX = math.max(1, maxX - minX);
        final spanY = math.max(1, maxY - minY);

        const pad = 16.0;
        final availW = constraints.maxWidth - pad * 2;
        final availH = constraints.maxHeight - pad * 2;
        final scale = math.min(availW / spanX, availH / spanY);
        final canvasW = spanX * scale;
        final canvasH = spanY * scale;

        return Container(
          color: const Color(0xFFF3F5F9),
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 6,
            boundaryMargin: const EdgeInsets.all(200),
            child: Center(
              child: SizedBox(
                width: canvasW,
                height: canvasH,
                child: Stack(
                  children: [
                    for (final t in tables)
                      Positioned(
                        left: (t.x1 - minX) * scale,
                        top: (t.y1 - minY) * scale,
                        width: t.width * scale,
                        height: t.height * scale,
                        child: _TableTile(
                          table: t,
                          status: statusLookup(t),
                          selected: selectedTable != null &&
                              selectedTable!.tableNo == t.tableNo &&
                              selectedTable!.areaId == t.areaId &&
                              selectedTable!.layoutCode == t.layoutCode,
                          onTap: () => onTapTable(t),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TableTile extends StatelessWidget {
  final DiningTable table;
  final DiningTableStatus? status;
  final bool selected;
  final VoidCallback onTap;

  const _TableTile({
    required this.table,
    required this.status,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final style = _styleForStatus(status);
    final fill = selected ? style.border : style.fill;
    final textColor = selected ? CupertinoColors.white : style.text;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: fill,
          border: Border.all(color: style.border, width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Text(
              '${table.tableNo}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TableDetails extends StatelessWidget {
  final DiningTable table;
  final DiningTableStatus? status;
  final bool busy;
  final VoidCallback? onChangeStatus;

  const _TableDetails({
    required this.table,
    required this.status,
    required this.busy,
    required this.onChangeStatus,
  });

  @override
  Widget build(BuildContext context) {
    final style = _styleForStatus(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: CupertinoColors.white,
        border: Border(top: BorderSide(color: CupertinoColors.systemGrey4)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: style.border,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text('${table.tableNo}',
                style: const TextStyle(
                    color: CupertinoColors.white, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Table ${table.tableNo}',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: style.fill,
                        border: Border.all(color: style.border),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        style.label,
                        style: TextStyle(
                            fontSize: 11,
                            color: style.text,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle(status, table),
                  style: const TextStyle(
                      fontSize: 12, color: CupertinoColors.systemGrey),
                ),
                if (status != null &&
                    status!.statusWithError.isNotEmpty &&
                    status!.statusWithError.trim() != status!.status.trim())
                  Text(
                    status!.statusWithError,
                    style: const TextStyle(
                        fontSize: 12, color: CupertinoColors.systemOrange),
                  ),
              ],
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: CupertinoActivityIndicator(),
            )
          else if (onChangeStatus != null)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              color: _primaryColor,
              onPressed: onChangeStatus,
              child: const Text(
                'Change status',
                style: TextStyle(fontSize: 13, color: CupertinoColors.white),
              ),
            ),
        ],
      ),
    );
  }

  static String _subtitle(DiningTableStatus? s, DiningTable t) {
    final parts = <String>['${t.areaId} · ${t.layoutCode}'];
    if (s != null) {
      if (s.seatCapacity > 0) parts.add('${s.seatCapacity} seats');
      if (s.sectionCode.isNotEmpty) parts.add(s.sectionCode);
      if (s.shape.isNotEmpty) parts.add(s.shape);
    }
    return parts.join(' · ');
  }
}
