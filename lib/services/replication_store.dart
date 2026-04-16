import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists a replicated entity locally as a single JSON blob under
/// `inventory.<entityKey>`, with a sibling `inventory.<entityKey>.meta`
/// that tracks row count and last-replicated timestamp.
class ReplicationStore {
  static const _prefix = 'inventory.';

  final SharedPreferences _prefs;
  final String entityKey;

  ReplicationStore(this._prefs, this.entityKey);

  String get _dataKey => '$_prefix$entityKey';
  String get _metaKey => '$_prefix$entityKey.meta';

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

  ReplicationMeta? meta() {
    final raw = _prefs.getString(_metaKey);
    if (raw == null || raw.isEmpty) return null;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return ReplicationMeta(
      count: (m['count'] as num?)?.toInt() ?? 0,
      lastReplicatedAt: DateTime.tryParse(m['lastReplicatedAt'] as String? ?? ''),
    );
  }

  Future<void> clear() async {
    await _prefs.remove(_dataKey);
    await _prefs.remove(_metaKey);
  }
}

class ReplicationMeta {
  final int count;
  final DateTime? lastReplicatedAt;
  const ReplicationMeta({required this.count, this.lastReplicatedAt});
}
