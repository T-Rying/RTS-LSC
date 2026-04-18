import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../models/dining_area_layout.dart';
import '../models/dining_table.dart';
import '../models/environment_config.dart';
import '../services/hospitality_service.dart';
import '../services/log_service.dart';

const Color _primaryColor = Color(0xFF003366);

/// Renders the BC dining-table layout on a phone screen. Three filters
/// cascade: **Restaurant** (derived from the prefix of `Dining_Area_ID`
/// before the first dash) → **Area** (the suffix after the dash) →
/// **Layout** (e.g. `WEEKDAY` / `WEEKEND`). The canvas draws each
/// table rectangle at its design-space coordinates, scaled to fit;
/// `InteractiveViewer` handles pinch-zoom and pan.
///
/// Alongside the table positions from `DiningTableLayout`, the page
/// also pulls `DiningAreaLayout` metadata (capacity, in-use counts,
/// description) and shows a summary card above the canvas.
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
  String? _area;
  String? _layoutCode;
  bool _loading = true;
  String? _error;
  DiningTable? _tappedTable;

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
      final layout = await _service.fetchLayout(widget.config);
      if (!mounted) return;
      _layout = layout;
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

  void _selectInitialFilters() {
    final restaurants = _restaurants();
    _restaurant = restaurants.isNotEmpty ? restaurants.first : null;
    final areas = _areasForRestaurant(_restaurant);
    _area = areas.isNotEmpty ? areas.first : null;
    final layouts = _layoutsFor(_restaurant, _area);
    _layoutCode = layouts.isNotEmpty ? layouts.first : null;
    _tappedTable = null;
  }

  // --- derived filter lists (union of both endpoints so all layouts
  //     are visible even if they don't yet have drawn tables) ---

  Iterable<String> _allAreaIds() sync* {
    final layout = _layout;
    if (layout == null) return;
    yield* layout.tables.map((t) => t.areaId);
    yield* layout.areaLayouts.map((m) => m.areaId);
  }

  List<String> _restaurants() =>
      _allAreaIds().map((id) => splitDiningAreaId(id).restaurant).toSet().toList()
        ..sort();

  List<String> _areasForRestaurant(String? restaurant) {
    if (restaurant == null) return const [];
    return _allAreaIds()
        .where((id) => splitDiningAreaId(id).restaurant == restaurant)
        .map((id) => splitDiningAreaId(id).area)
        .toSet()
        .toList()
      ..sort();
  }

  List<String> _layoutsFor(String? restaurant, String? area) {
    final layout = _layout;
    if (layout == null || restaurant == null || area == null) return const [];
    final areaId = _composeAreaId(restaurant, area);
    final codes = <String>{};
    for (final t in layout.tables) {
      if (t.areaId == areaId) codes.add(t.layoutCode);
    }
    for (final m in layout.areaLayouts) {
      if (m.areaId == areaId) codes.add(m.layoutCode);
    }
    return codes.toList()..sort();
  }

  String _composeAreaId(String restaurant, String area) =>
      restaurant == area ? restaurant : '$restaurant-$area';

  String? _selectedAreaId() {
    if (_restaurant == null || _area == null) return null;
    return _composeAreaId(_restaurant!, _area!);
  }

  List<DiningTable> _currentTables() {
    final layout = _layout;
    final areaId = _selectedAreaId();
    if (layout == null || areaId == null || _layoutCode == null) return const [];
    return layout.tables
        .where((t) => t.areaId == areaId && t.layoutCode == _layoutCode)
        .toList();
  }

  DiningAreaLayout? _currentMeta() {
    final layout = _layout;
    final areaId = _selectedAreaId();
    if (layout == null || areaId == null || _layoutCode == null) return null;
    return layout.metaFor(areaId, _layoutCode!);
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
    if (_layout == null || _layout!.tables.isEmpty && _layout!.areaLayouts.isEmpty) {
      return const Center(child: Text('No dining data returned.'));
    }

    final tables = _currentTables();
    final meta = _currentMeta();
    return Column(
      children: [
        _FiltersBar(
          restaurants: _restaurants(),
          areas: _areasForRestaurant(_restaurant),
          layouts: _layoutsFor(_restaurant, _area),
          restaurant: _restaurant,
          area: _area,
          layoutCode: _layoutCode,
          onPickRestaurant: _pickRestaurant,
          onPickArea: _pickArea,
          onPickLayout: _pickLayout,
        ),
        if (meta != null) _MetaCard(meta: meta, tableCount: tables.length),
        Expanded(
          child: tables.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No drawn tables for this layout.\n'
                      'The area metadata is still shown above.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: CupertinoColors.systemGrey),
                    ),
                  ),
                )
              : _Canvas(
                  tables: tables,
                  selectedTable: _tappedTable,
                  onTapTable: (t) => setState(() => _tappedTable = t),
                ),
        ),
        if (_tappedTable != null) _TableDetails(table: _tappedTable!),
      ],
    );
  }

  Future<void> _pickRestaurant() async {
    final restaurants = _restaurants();
    final picked = await _pickFromSheet('Restaurant', restaurants);
    if (picked == null) return;
    setState(() {
      _restaurant = picked;
      final areas = _areasForRestaurant(_restaurant);
      _area = areas.isNotEmpty ? areas.first : null;
      final layouts = _layoutsFor(_restaurant, _area);
      _layoutCode = layouts.isNotEmpty ? layouts.first : null;
      _tappedTable = null;
    });
  }

  Future<void> _pickArea() async {
    final areas = _areasForRestaurant(_restaurant);
    final picked = await _pickFromSheet('Area', areas);
    if (picked == null) return;
    setState(() {
      _area = picked;
      final layouts = _layoutsFor(_restaurant, _area);
      _layoutCode = layouts.isNotEmpty ? layouts.first : null;
      _tappedTable = null;
    });
  }

  Future<void> _pickLayout() async {
    final layouts = _layoutsFor(_restaurant, _area);
    final picked = await _pickFromSheet('Layout', layouts);
    if (picked == null) return;
    setState(() {
      _layoutCode = picked;
      _tappedTable = null;
    });
  }

  Future<String?> _pickFromSheet(String title, List<String> options) {
    return showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(title),
        actions: [
          for (final o in options)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(ctx, o),
              child: Text(o),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }
}

class _FiltersBar extends StatelessWidget {
  final List<String> restaurants;
  final List<String> areas;
  final List<String> layouts;
  final String? restaurant;
  final String? area;
  final String? layoutCode;
  final VoidCallback onPickRestaurant;
  final VoidCallback onPickArea;
  final VoidCallback onPickLayout;

  const _FiltersBar({
    required this.restaurants,
    required this.areas,
    required this.layouts,
    required this.restaurant,
    required this.area,
    required this.layoutCode,
    required this.onPickRestaurant,
    required this.onPickArea,
    required this.onPickLayout,
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
            child: _PickerButton(
              label: 'Restaurant',
              value: restaurant ?? '—',
              onTap: restaurants.isEmpty ? null : onPickRestaurant,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _PickerButton(
              label: 'Area',
              value: area ?? '—',
              onTap: areas.isEmpty ? null : onPickArea,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _PickerButton(
              label: 'Layout',
              value: layoutCode ?? '—',
              onTap: layouts.isEmpty ? null : onPickLayout,
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
          if (description.isNotEmpty) ...[
            Text(description,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
          ],
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
  final ValueChanged<DiningTable> onTapTable;

  const _Canvas({
    required this.tables,
    required this.selectedTable,
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
  final bool selected;
  final VoidCallback onTap;

  const _TableTile({
    required this.table,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? _primaryColor : _primaryColor.withValues(alpha: 0.12),
          border: Border.all(color: _primaryColor, width: selected ? 2 : 1),
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
                color: selected ? CupertinoColors.white : _primaryColor,
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

  const _TableDetails({required this.table});

  @override
  Widget build(BuildContext context) {
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
              color: _primaryColor,
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
                Text('Table ${table.tableNo}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('${table.areaId} · ${table.layoutCode}',
                    style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey)),
                Text(
                  '${table.width} × ${table.height} design units',
                  style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
