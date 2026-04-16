import 'package:shared_preferences/shared_preferences.dart';
import 'replication_store.dart';

/// Looks up a scanned barcode in the locally replicated LS Central data and
/// builds an aggregated "item card" combining barcode + variant + sales prices.
class ItemLookupService {
  final ReplicationStore _barcodes;
  final ReplicationStore _itemVariants;
  final ReplicationStore _salesPrices;
  final ReplicationStore _itemCategories;

  ItemLookupService(SharedPreferences prefs)
      : _barcodes = ReplicationStore(prefs, 'barcodes'),
        _itemVariants = ReplicationStore(prefs, 'item_variants'),
        _salesPrices = ReplicationStore(prefs, 'sales_prices'),
        _itemCategories = ReplicationStore(prefs, 'item_categories');

  ItemCard? lookup(String scannedBarcode) {
    final barcode = _findBarcode(scannedBarcode);
    if (barcode == null) return null;

    final itemNo = _str(barcode['Item No.']);
    final variantCode = _str(barcode['Variant Code']);
    final uom = _str(barcode['Unit of Measure Code']);

    final variant = (itemNo != null) ? _findVariant(itemNo, variantCode) : null;
    final prices = (itemNo != null)
        ? _findPrices(itemNo: itemNo, variantCode: variantCode, uom: uom)
        : const <Map<String, dynamic>>[];
    final category = _findCategoryFor(barcode);

    return ItemCard(
      scannedBarcode: scannedBarcode,
      barcode: barcode,
      variant: variant,
      category: category,
      salesPrices: prices,
    );
  }

  Map<String, dynamic>? _findBarcode(String scanned) {
    final needle = scanned.trim();
    if (needle.isEmpty) return null;
    for (final row in _barcodes.load()) {
      final bc = _str(row['Barcode No.']);
      if (bc != null && bc == needle) return row;
    }
    return null;
  }

  Map<String, dynamic>? _findVariant(String itemNo, String? variantCode) {
    if (variantCode == null || variantCode.isEmpty) return null;
    for (final row in _itemVariants.load()) {
      if (_str(row['Item No.']) == itemNo && _str(row['Code']) == variantCode) {
        return row;
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _findPrices({
    required String itemNo,
    String? variantCode,
    String? uom,
  }) {
    final matches = <Map<String, dynamic>>[];
    for (final row in _salesPrices.load()) {
      if (_str(row['Item No.']) != itemNo) continue;
      final rowVariant = _str(row['Variant Code']) ?? '';
      if (variantCode != null && variantCode.isNotEmpty && rowVariant.isNotEmpty && rowVariant != variantCode) {
        continue;
      }
      final rowUom = _str(row['Unit of Measure Code']) ?? '';
      if (uom != null && uom.isNotEmpty && rowUom.isNotEmpty && rowUom != uom) {
        continue;
      }
      matches.add(row);
    }
    return matches;
  }

  Map<String, dynamic>? _findCategoryFor(Map<String, dynamic> barcode) {
    final code = _str(barcode['Item Category Code']) ?? _str(barcode['Category Code']);
    if (code == null || code.isEmpty) return null;
    for (final row in _itemCategories.load()) {
      if (_str(row['Code']) == code) return row;
    }
    return null;
  }

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }
}

class ItemCard {
  final String scannedBarcode;
  final Map<String, dynamic> barcode;
  final Map<String, dynamic>? variant;
  final Map<String, dynamic>? category;
  final List<Map<String, dynamic>> salesPrices;

  const ItemCard({
    required this.scannedBarcode,
    required this.barcode,
    this.variant,
    this.category,
    required this.salesPrices,
  });
}
