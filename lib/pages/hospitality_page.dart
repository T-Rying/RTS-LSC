import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../models/dining_table.dart';
import '../models/environment_config.dart';
import '../services/hospitality_service.dart';
import '../services/log_service.dart';

const Color _primaryColor = Color(0xFF003366);

/// Renders the BC dining-table layout on a phone screen. Users pick an
/// area (e.g. `S0005-RESTAURANT`) and then a layout within that area
/// (e.g. `WEEKDAY`); the canvas draws each table as a rectangle at its
/// design-space coordinates, scaled to fit the screen. Pinch-to-zoom
/// and pan are provided by `InteractiveViewer` so larger restaurants
/// with many tables stay legible.
class HospitalityPage extends StatefulWidget {
  final EnvironmentConfig config;

  const HospitalityPage({super.key, required this.config});

  @override
  State<HospitalityPage> createState() => _HospitalityPageState();
}

class _HospitalityPageState extends State<HospitalityPage> {
  final _service = HospitalityService();
  final _log = LogService.instance;

  List<DiningTable> _tables = const [];
  String? _selectedArea;
  String? _selectedLayout;
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
      final tables = await _service.fetchTables(widget.config);
      if (!mounted) return;
      final areas = _areas(tables);
      final firstArea = areas.isNotEmpty ? areas.first : null;
      final layouts = firstArea == null ? <String>[] : _layouts(tables, firstArea);
      setState(() {
        _tables = tables;
        _selectedArea = firstArea;
        _selectedLayout = layouts.isNotEmpty ? layouts.first : null;
        _loading = false;
      });
    } catch (e) {
      _log.error('Hospitality: fetch failed: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<String> _areas(List<DiningTable> tables) =>
      tables.map((t) => t.areaId).toSet().toList()..sort();

  List<String> _layouts(List<DiningTable> tables, String area) => tables
      .where((t) => t.areaId == area)
      .map((t) => t.layoutCode)
      .toSet()
      .toList()
    ..sort();

  List<DiningTable> _currentTables() {
    if (_selectedArea == null || _selectedLayout == null) return const [];
    return _tables
        .where((t) => t.areaId == _selectedArea && t.layoutCode == _selectedLayout)
        .toList();
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
            const Icon(CupertinoIcons.exclamationmark_triangle, size: 36, color: CupertinoColors.systemOrange),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            CupertinoButton.filled(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }
    if (_tables.isEmpty) {
      return const Center(child: Text('No dining tables returned.'));
    }

    final tables = _currentTables();
    return Column(
      children: [
        _Header(
          areas: _areas(_tables),
          layouts: _selectedArea == null ? const [] : _layouts(_tables, _selectedArea!),
          area: _selectedArea,
          layout: _selectedLayout,
          onPickArea: _pickArea,
          onPickLayout: _pickLayout,
          tableCount: tables.length,
        ),
        Expanded(
          child: tables.isEmpty
              ? const Center(
                  child: Text('No tables for this layout.',
                      style: TextStyle(color: CupertinoColors.systemGrey)),
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

  Future<void> _pickArea() async {
    final areas = _areas(_tables);
    final picked = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Dining area'),
        actions: [
          for (final a in areas)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(ctx, a),
              child: Text(a),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (picked == null) return;
    final layouts = _layouts(_tables, picked);
    setState(() {
      _selectedArea = picked;
      _selectedLayout = layouts.isNotEmpty ? layouts.first : null;
      _tappedTable = null;
    });
  }

  Future<void> _pickLayout() async {
    if (_selectedArea == null) return;
    final layouts = _layouts(_tables, _selectedArea!);
    final picked = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Layout'),
        actions: [
          for (final l in layouts)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(ctx, l),
              child: Text(l),
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
      _selectedLayout = picked;
      _tappedTable = null;
    });
  }
}

class _Header extends StatelessWidget {
  final List<String> areas;
  final List<String> layouts;
  final String? area;
  final String? layout;
  final int tableCount;
  final VoidCallback onPickArea;
  final VoidCallback onPickLayout;

  const _Header({
    required this.areas,
    required this.layouts,
    required this.area,
    required this.layout,
    required this.tableCount,
    required this.onPickArea,
    required this.onPickLayout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: CupertinoColors.systemGroupedBackground,
        border: Border(bottom: BorderSide(color: CupertinoColors.systemGrey4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _PickerButton(
              label: 'Area',
              value: area ?? '—',
              onTap: areas.isEmpty ? null : onPickArea,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _PickerButton(
              label: 'Layout',
              value: layout ?? '—',
              onTap: layouts.isEmpty ? null : onPickLayout,
            ),
          ),
          const SizedBox(width: 10),
          Text('$tableCount tables',
              style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey)),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                        fontSize: 14,
                        color: CupertinoColors.black,
                        fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: 4),
              const Icon(CupertinoIcons.chevron_down, size: 12, color: CupertinoColors.systemGrey),
            ],
          ),
        ],
      ),
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
        // Design-space bounds from the tables in this layout.
        final minX = tables.map((t) => t.x1).reduce(math.min);
        final maxX = tables.map((t) => t.x2).reduce(math.max);
        final minY = tables.map((t) => t.y1).reduce(math.min);
        final maxY = tables.map((t) => t.y2).reduce(math.max);
        final spanX = math.max(1, maxX - minX);
        final spanY = math.max(1, maxY - minY);

        // Pad a bit so tables don't touch the canvas edge.
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
                style: const TextStyle(color: CupertinoColors.white, fontWeight: FontWeight.w700)),
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
