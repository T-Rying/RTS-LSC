import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the replicated barcode payload locally.
/// Stored as a JSON list under a single SharedPreferences key.
class BarcodeRepository {
  static const _dataKey = 'inventory.barcodes';
  static const _metaKey = 'inventory.barcodes.meta';

  final SharedPreferences _prefs;

  BarcodeRepository(this._prefs);

  Future<void> replace(List<Map<String, dynamic>> rows) async {
    await _prefs.setString(_dataKey, jsonEncode(rows));
    await _prefs.setString(_metaKey, jsonEncode({
      'count': rows.length,
      'lastReplicatedAt': DateTime.now().toIso8601String(),
    }));
  }

  List<Map<String, dynamic>> load() {
    final raw = _prefs.getString(_dataKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded.whereType<Map<String, dynamic>>().toList();
  }

  BarcodeReplicationMeta? meta() {
    final raw = _prefs.getString(_metaKey);
    if (raw == null || raw.isEmpty) return null;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return BarcodeReplicationMeta(
      count: (m['count'] as num?)?.toInt() ?? 0,
      lastReplicatedAt: DateTime.tryParse(m['lastReplicatedAt'] as String? ?? ''),
    );
  }

  Future<void> clear() async {
    await _prefs.remove(_dataKey);
    await _prefs.remove(_metaKey);
  }
}

class BarcodeReplicationMeta {
  final int count;
  final DateTime? lastReplicatedAt;
  const BarcodeReplicationMeta({required this.count, this.lastReplicatedAt});
}
