import 'package:flutter/cupertino.dart';
import '../services/item_lookup_service.dart';

const Color _primaryColor = Color(0xFF003366);

/// Displays the aggregated item card for a scanned barcode, or a
/// "not found" message if the barcode isn't in the local data.
class ItemCardPage extends StatelessWidget {
  final String scannedBarcode;
  final ItemCard? card;

  const ItemCardPage({
    super.key,
    required this.scannedBarcode,
    required this.card,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Item')),
      child: SafeArea(
        child: card == null ? _NotFound(scanned: scannedBarcode) : _CardBody(card: card!),
      ),
    );
  }
}

class _NotFound extends StatelessWidget {
  final String scanned;
  const _NotFound({required this.scanned});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(CupertinoIcons.exclamationmark_triangle,
                size: 48, color: CupertinoColors.systemOrange),
            const SizedBox(height: 12),
            const Text('Barcode not found',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(scanned,
                style: const TextStyle(color: CupertinoColors.systemGrey)),
            const SizedBox(height: 16),
            const Text(
              'The scanned barcode is not present in the replicated barcodes. '
              'Replicate again, or check that the barcode is registered for '
              'this store.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: CupertinoColors.systemGrey),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardBody extends StatelessWidget {
  final ItemCard card;
  const _CardBody({required this.card});

  String? _s(Map<String, dynamic>? row, String key) {
    if (row == null) return null;
    final v = row[key];
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  @override
  Widget build(BuildContext context) {
    final bc = card.barcode;
    final itemNo = _s(bc, 'Item No.') ?? '';
    final description = _s(bc, 'Description') ?? '';
    final variantCode = _s(bc, 'Variant Code');
    final uom = _s(bc, 'Unit of Measure Code');

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(CupertinoIcons.cube_box, color: _primaryColor, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      description.isEmpty ? itemNo : description,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _kv('Item No.', itemNo),
              _kv('Barcode', card.scannedBarcode),
              if (variantCode != null) _kv('Variant', variantCode),
              if (uom != null) _kv('Unit of Measure', uom),
              if (_s(bc, 'Discount %') != null) _kv('Discount %', _s(bc, 'Discount %')!),
              if (_s(bc, 'Last Date Modified') != null)
                _kv('Last Modified', _s(bc, 'Last Date Modified')!),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (card.category != null) ...[
          _SectionTitle('Category'),
          const SizedBox(height: 8),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv('Code', _s(card.category, 'Code') ?? ''),
                if (_s(card.category, 'Description') != null)
                  _kv('Description', _s(card.category, 'Description')!),
                if (_s(card.category, 'Parent Category') != null)
                  _kv('Parent', _s(card.category, 'Parent Category')!),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (card.variant != null) ...[
          _SectionTitle('Variant'),
          const SizedBox(height: 8),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in card.variant!.entries) _kv(entry.key, entry.value?.toString() ?? ''),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        _SectionTitle(card.salesPrices.isEmpty
            ? 'Sales Prices'
            : 'Sales Prices (${card.salesPrices.length})'),
        const SizedBox(height: 8),
        if (card.salesPrices.isEmpty)
          _Card(
            child: const Text('No matching sales prices',
                style: TextStyle(color: CupertinoColors.systemGrey)),
          )
        else
          for (final price in card.salesPrices) ...[
            _PriceCard(price: price),
            const SizedBox(height: 8),
          ],

        const SizedBox(height: 16),
        _SectionTitle('All Barcode Fields'),
        const SizedBox(height: 8),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final e in bc.entries) _kv(e.key, e.value?.toString() ?? ''),
            ],
          ),
        ),
      ],
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(key,
                style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

class _PriceCard extends StatelessWidget {
  final Map<String, dynamic> price;
  const _PriceCard({required this.price});

  String? _s(String key) {
    final v = price[key];
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  @override
  Widget build(BuildContext context) {
    final unitPrice = _s('Unit Price') ?? _s('Sales Price') ?? '—';
    final currency = _s('Currency Code');
    final salesType = _s('Sales Type');
    final salesCode = _s('Sales Code');
    final minQty = _s('Minimum Quantity');
    final uom = _s('Unit of Measure Code');
    final variant = _s('Variant Code');
    final startDate = _s('Starting Date');
    final endDate = _s('Ending Date');

    return Container(
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
              Text(unitPrice,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _primaryColor)),
              if (currency != null) ...[
                const SizedBox(width: 6),
                Text(currency, style: const TextStyle(color: CupertinoColors.systemGrey)),
              ],
              const Spacer(),
              if (salesType != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey6,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    salesCode != null ? '$salesType: $salesCode' : salesType,
                    style: const TextStyle(fontSize: 11, color: CupertinoColors.systemGrey),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              if (uom != null) _chip('UoM', uom),
              if (variant != null) _chip('Variant', variant),
              if (minQty != null) _chip('Min Qty', minQty),
              if (startDate != null) _chip('From', startDate),
              if (endDate != null) _chip('To', endDate),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String k, String v) {
    return Text('$k: $v',
        style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey));
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
