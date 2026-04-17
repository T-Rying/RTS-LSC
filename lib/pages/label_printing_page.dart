import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/log_service.dart';
import '../services/zebra_printer_service.dart';
import 'label_designs_page.dart';
import 'label_print_job_page.dart';

const Color _primaryColor = Color(0xFF003366);
const String _selectedPrinterKey = 'label_printing.selected_printer';

class LabelPrintingPage extends StatefulWidget {
  const LabelPrintingPage({super.key});

  @override
  State<LabelPrintingPage> createState() => _LabelPrintingPageState();
}

class _LabelPrintingPageState extends State<LabelPrintingPage> {
  final _printerService = ZebraPrinterService();
  final _log = LogService.instance;

  SharedPreferences? _prefs;
  ZebraPrinter? _selected;
  List<ZebraPrinter> _discovered = const [];
  bool _scanning = false;
  bool _printing = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        _prefs = p;
        _selected = _loadSelected(p);
      });
    });
  }

  ZebraPrinter? _loadSelected(SharedPreferences p) {
    final raw = p.getString(_selectedPrinterKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return ZebraPrinter.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistSelected(ZebraPrinter? printer) async {
    final p = _prefs;
    if (p == null) return;
    if (printer == null) {
      await p.remove(_selectedPrinterKey);
    } else {
      await p.setString(_selectedPrinterKey, jsonEncode(printer.toJson()));
    }
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
      _info = null;
    });
    try {
      final printers = await _printerService.discover();
      if (!mounted) return;
      setState(() {
        _discovered = printers;
        _scanning = false;
        _info = printers.isEmpty
            ? 'No printers found. Make sure the printer is on the same Wi-Fi network.'
            : 'Found ${printers.length} printer${printers.length == 1 ? '' : 's'}.';
      });
    } catch (e) {
      _log.error('Label Printing: scan failed: $e');
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _error = 'Scan failed: $e';
      });
    }
  }

  Future<void> _select(ZebraPrinter printer) async {
    await _persistSelected(printer);
    if (!mounted) return;
    setState(() {
      _selected = printer;
      _info = 'Selected ${printer.name}.';
    });
  }

  Future<void> _printTest() async {
    final printer = _selected;
    if (printer == null) return;
    setState(() {
      _printing = true;
      _error = null;
      _info = null;
    });
    try {
      await _printerService.printTestLabel(printer);
      if (!mounted) return;
      setState(() {
        _printing = false;
        _info = 'Test label sent to ${printer.name}.';
      });
    } catch (e) {
      _log.error('Label Printing: print failed: $e');
      if (!mounted) return;
      setState(() {
        _printing = false;
        _error = 'Print failed: $e';
      });
    }
  }

  Future<void> _clearSelected() async {
    await _persistSelected(null);
    if (!mounted) return;
    setState(() {
      _selected = null;
      _info = 'Cleared selected printer.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Label Printing'),
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
                  _SelectedPrinterCard(
                    printer: _selected,
                    busy: _printing,
                    onPrintTest: _selected == null || _printing ? null : _printTest,
                    onClear: _selected == null ? null : _clearSelected,
                  ),
                  const SizedBox(height: 20),
                  const Text('Design & Print',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _NavRow(
                    icon: CupertinoIcons.square_stack,
                    title: 'Label Designs',
                    subtitle: 'Create, import, or export label layouts.',
                    onTap: () => Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => LabelDesignsPage(prefs: _prefs!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _NavRow(
                    icon: CupertinoIcons.printer,
                    title: 'Print Label',
                    subtitle: 'Scan an item, pick a design, print or demo.',
                    onTap: () => Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => LabelPrintJobPage(prefs: _prefs!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Discovery',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _ScanCard(scanning: _scanning, onScan: _scanning ? null : _scan),
                  const SizedBox(height: 12),
                  for (final p in _discovered) ...[
                    _PrinterRow(
                      printer: p,
                      selected: p == _selected,
                      onTap: () => _select(p),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_info != null) ...[
                    const SizedBox(height: 12),
                    Text(_info!,
                        style: const TextStyle(color: CupertinoColors.systemGrey, fontSize: 13)),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: const TextStyle(
                            color: CupertinoColors.destructiveRed, fontSize: 13)),
                  ],
                ],
              ),
      ),
    );
  }
}

class _SelectedPrinterCard extends StatelessWidget {
  final ZebraPrinter? printer;
  final bool busy;
  final VoidCallback? onPrintTest;
  final VoidCallback? onClear;

  const _SelectedPrinterCard({
    required this.printer,
    required this.busy,
    required this.onPrintTest,
    required this.onClear,
  });

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
              Icon(CupertinoIcons.printer, color: _primaryColor, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text('Selected Printer',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (printer == null)
            const Text(
              'No printer selected. Scan the network and pick one below.',
              style: TextStyle(fontSize: 13, color: CupertinoColors.systemGrey),
            )
          else ...[
            Text(printer!.name,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text('${printer!.host}:${printer!.port}',
                style: const TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: CupertinoButton.filled(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  onPressed: onPrintTest,
                  child: busy
                      ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                      : const Text('Print Test Label'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  onPressed: onClear,
                  child: const Text('Clear'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScanCard extends StatelessWidget {
  final bool scanning;
  final VoidCallback? onScan;

  const _ScanCard({required this.scanning, required this.onScan});

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
              Icon(CupertinoIcons.wifi, color: _primaryColor, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text('Scan Network',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Looks for Zebra printers that advertise themselves on the local network (mDNS / Bonjour).',
            style: TextStyle(fontSize: 13, color: CupertinoColors.systemGrey),
          ),
          const SizedBox(height: 14),
          CupertinoButton.filled(
            padding: const EdgeInsets.symmetric(vertical: 10),
            onPressed: onScan,
            child: scanning
                ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                : const Text('Scan'),
          ),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _NavRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
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
        child: Row(
          children: [
            Icon(icon, color: _primaryColor, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey)),
                ],
              ),
            ),
            const Icon(CupertinoIcons.chevron_right, size: 18, color: CupertinoColors.systemGrey3),
          ],
        ),
      ),
    );
  }
}

class _PrinterRow extends StatelessWidget {
  final ZebraPrinter printer;
  final bool selected;
  final VoidCallback onTap;

  const _PrinterRow({required this.printer, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: CupertinoColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _primaryColor : CupertinoColors.systemGrey5,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            const Icon(CupertinoIcons.printer, color: _primaryColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(printer.name,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text('${printer.host}:${printer.port}',
                      style: const TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)),
                ],
              ),
            ),
            if (selected)
              const Icon(CupertinoIcons.check_mark_circled_solid, color: _primaryColor),
          ],
        ),
      ),
    );
  }
}
