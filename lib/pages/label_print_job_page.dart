import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/label_design.dart';
import '../services/item_lookup_service.dart';
import '../services/label_design_store.dart';
import '../services/label_zpl_renderer.dart';
import '../services/log_service.dart';
import '../services/zebra_printer_service.dart';
import '../widgets/label_preview.dart';
import 'product_scanner_page.dart';

const Color _primaryColor = Color(0xFF003366);
const String _selectedPrinterKey = 'label_printing.selected_printer';

/// End-to-end print workflow: scan an item, pick a saved label design,
/// choose a quantity, then print. If no printer is selected (or the
/// print fails) the user can see a demo rendering of the label instead.
class LabelPrintJobPage extends StatefulWidget {
  final SharedPreferences prefs;

  const LabelPrintJobPage({super.key, required this.prefs});

  @override
  State<LabelPrintJobPage> createState() => _LabelPrintJobPageState();
}

class _LabelPrintJobPageState extends State<LabelPrintJobPage> {
  late final LabelDesignStore _designs = LabelDesignStore(widget.prefs);
  late final ItemLookupService _lookup = ItemLookupService(widget.prefs);
  final _printer = ZebraPrinterService();
  final _log = LogService.instance;

  String? _scannedBarcode;
  ItemCard? _itemCard;
  LabelDesign? _selectedDesign;
  int _quantity = 1;
  bool _busy = false;
  String? _status;
  String? _error;

  ZebraPrinter? _loadSelectedPrinter() {
    final raw = widget.prefs.getString(_selectedPrinterKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return ZebraPrinter.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedPrinter = _loadSelectedPrinter();
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Print Label')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _ScanCard(
              barcode: _scannedBarcode,
              card: _itemCard,
              onScan: _scan,
              onClear: _scannedBarcode == null ? null : _clearScan,
            ),
            const SizedBox(height: 16),
            _DesignPickerCard(
              designs: _designs.list(),
              selected: _selectedDesign,
              onPick: (d) => setState(() => _selectedDesign = d),
            ),
            const SizedBox(height: 16),
            _QuantityCard(
              quantity: _quantity,
              onChanged: (v) => setState(() => _quantity = v),
            ),
            const SizedBox(height: 16),
            if (_selectedDesign != null) ...[
              const Text('Preview',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Center(
                child: LabelPreview(
                  design: _selectedDesign!,
                  data: _currentBinding(),
                  maxWidth: MediaQuery.of(context).size.width - 40,
                  maxHeight: 320,
                ),
              ),
              const SizedBox(height: 16),
            ],
            _ActionsCard(
              printer: selectedPrinter,
              busy: _busy,
              canPrint: _selectedDesign != null,
              onPrint: () => _print(selectedPrinter),
              onDemoPrint: _selectedDesign == null ? null : _demoPrint,
            ),
            if (_status != null) ...[
              const SizedBox(height: 12),
              Text(_status!,
                  style: const TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(fontSize: 13, color: CupertinoColors.destructiveRed)),
            ],
          ],
        ),
      ),
    );
  }

  Map<String, String> _currentBinding() {
    if (_itemCard != null) return bindItemCard(_itemCard);
    return demoBinding();
  }

  Future<void> _scan() async {
    final scanned = await Navigator.push<String>(
      context,
      CupertinoPageRoute(builder: (_) => const ProductScannerPage()),
    );
    if (scanned == null || !mounted) return;
    final card = _lookup.lookup(scanned);
    setState(() {
      _scannedBarcode = scanned;
      _itemCard = card;
      _status = card == null
          ? 'Barcode not found in replicated data. Preview uses demo values.'
          : null;
      _error = null;
    });
  }

  void _clearScan() {
    setState(() {
      _scannedBarcode = null;
      _itemCard = null;
      _status = null;
    });
  }

  Future<void> _print(ZebraPrinter? printer) async {
    final design = _selectedDesign;
    if (design == null) return;
    if (printer == null) {
      setState(() {
        _error = null;
        _status = 'No printer selected. Showing a demo render instead.';
      });
      await _demoPrint();
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
      _error = null;
    });
    try {
      final zpl = renderZpl(design, _currentBinding(), quantity: _quantity);
      await _printer.printZpl(printer, zpl);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Sent $_quantity label${_quantity == 1 ? '' : 's'} to ${printer.name}.';
      });
    } catch (e) {
      _log.error('Label print failed: $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Print failed: $e — showing a demo render instead.';
      });
      await _demoPrint();
    }
  }

  Future<void> _demoPrint() async {
    final design = _selectedDesign;
    if (design == null) return;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => _DemoSheet(
        design: design,
        data: _currentBinding(),
        quantity: _quantity,
      ),
    );
  }
}

class _ScanCard extends StatelessWidget {
  final String? barcode;
  final ItemCard? card;
  final VoidCallback onScan;
  final VoidCallback? onClear;

  const _ScanCard({
    required this.barcode,
    required this.card,
    required this.onScan,
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
              Icon(CupertinoIcons.barcode_viewfinder, color: _primaryColor, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text('Scan Item',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (barcode == null)
            const Text(
              'Scan a barcode so its data fills in your label fields. You can also skip this to preview with demo values.',
              style: TextStyle(fontSize: 13, color: CupertinoColors.systemGrey),
            )
          else ...[
            Text('Barcode: $barcode',
                style: const TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)),
            if (card != null) ...[
              const SizedBox(height: 4),
              Text('${card!.barcode['Item No.'] ?? ''} · ${card!.barcode['Description'] ?? ''}',
                  style: const TextStyle(fontSize: 13)),
            ] else
              const Text(
                'Not found in replicated data — preview will use demo values.',
                style: TextStyle(fontSize: 13, color: CupertinoColors.systemOrange),
              ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: CupertinoButton.filled(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  onPressed: onScan,
                  child: const Text('Scan'),
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

class _DesignPickerCard extends StatelessWidget {
  final List<LabelDesign> designs;
  final LabelDesign? selected;
  final ValueChanged<LabelDesign> onPick;

  const _DesignPickerCard({
    required this.designs,
    required this.selected,
    required this.onPick,
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
              Icon(CupertinoIcons.square_stack, color: _primaryColor, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text('Design',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (designs.isEmpty)
            const Text('No designs yet. Create one in the designer first.',
                style: TextStyle(fontSize: 13, color: CupertinoColors.systemGrey))
          else
            for (final d in designs)
              GestureDetector(
                onTap: () => onPick(d),
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey6,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected?.id == d.id ? _primaryColor : CupertinoColors.systemGrey6,
                      width: selected?.id == d.id ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d.name,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 2),
                            Text(
                                '${d.widthMm.toStringAsFixed(0)} × ${d.heightMm.toStringAsFixed(0)} mm · '
                                '${d.elements.length} element${d.elements.length == 1 ? '' : 's'}',
                                style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey)),
                          ],
                        ),
                      ),
                      if (selected?.id == d.id)
                        const Icon(CupertinoIcons.check_mark_circled_solid, color: _primaryColor),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _QuantityCard extends StatelessWidget {
  final int quantity;
  final ValueChanged<int> onChanged;

  const _QuantityCard({required this.quantity, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CupertinoColors.systemGrey5),
      ),
      child: Row(
        children: [
          const Icon(CupertinoIcons.number, color: _primaryColor, size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Quantity',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: quantity > 1 ? () => onChanged(quantity - 1) : null,
            child: const Icon(CupertinoIcons.minus_circle),
          ),
          SizedBox(
            width: 40,
            child: Text('$quantity',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: quantity < 999 ? () => onChanged(quantity + 1) : null,
            child: const Icon(CupertinoIcons.add_circled),
          ),
        ],
      ),
    );
  }
}

class _ActionsCard extends StatelessWidget {
  final ZebraPrinter? printer;
  final bool busy;
  final bool canPrint;
  final VoidCallback onPrint;
  final VoidCallback? onDemoPrint;

  const _ActionsCard({
    required this.printer,
    required this.busy,
    required this.canPrint,
    required this.onPrint,
    required this.onDemoPrint,
  });

  @override
  Widget build(BuildContext context) {
    final hasPrinter = printer != null;
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
              Icon(hasPrinter ? CupertinoIcons.printer_fill : CupertinoIcons.printer,
                  color: _primaryColor, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hasPrinter ? 'Printer: ${printer!.name}' : 'No printer selected',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          if (!hasPrinter) ...[
            const SizedBox(height: 4),
            const Text(
              'Tap "Demo Print" to see how the label will look. Connect a printer from the Label Printing page to send real prints.',
              style: TextStyle(fontSize: 12, color: CupertinoColors.systemGrey),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: CupertinoButton.filled(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  onPressed: canPrint && !busy ? onPrint : null,
                  child: busy
                      ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                      : Text(hasPrinter ? 'Print' : 'Demo Print'),
                ),
              ),
              if (hasPrinter) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    onPressed: onDemoPrint,
                    child: const Text('Demo Print'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _DemoSheet extends StatelessWidget {
  final LabelDesign design;
  final Map<String, String> data;
  final int quantity;

  const _DemoSheet({required this.design, required this.data, required this.quantity});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CupertinoColors.systemBackground,
      padding: const EdgeInsets.all(20),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Demo label',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                ),
                Text('× $quantity',
                    style: const TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: LabelPreview(
                design: design,
                data: data,
                maxWidth: MediaQuery.of(context).size.width - 40,
                maxHeight: 360,
              ),
            ),
            const SizedBox(height: 16),
            CupertinoButton.filled(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
