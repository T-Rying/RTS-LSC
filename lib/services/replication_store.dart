import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists a replicated entity locally as a single JSON blob under
/// `inventory.<entityKey>`, with sibling keys for the per-entity meta
/// (row count + timestamp) and the LS Central replication cursor
/// (`lastKey`, `lastEntryNo`) so delta replication can pick up where
/// the previous run left off.
///
/// `applyDelta` merges a fresh batch into the existing rows using a
/// caller-supplied `keyOf` function — IsDeleted rows are removed,
/// everything else upserts on the resolved primary key. For full
/// (non-delta) loads use `replace`, which discards the previous
/// snapshot.
class ReplicationStore {
  static const _prefix = 'inventory.';

  final SharedPreferences _prefs;
  final String entityKey;

  ReplicationStore(this._prefs, this.entityKey);

  String get _dataKey => '$_prefix$entityKey';
  String get _metaKey => '$_prefix$entityKey.meta';
  String get _cursorKey => '$_prefix$entityKey.cursor';

  /// Replace the whole snapshot. Used for the very first load and any
  /// subsequent full re-replications (after a reset).
  Future<void> replace(List<Map<String, dynamic>> rows) async {
    await _prefs.setString(_dataKey, jsonEncode(rows));
    await _writeMeta(rows.length);
  }

  /// Apply a delta batch onto the existing snapshot. `upserts` are
  /// merged in, replacing any row whose `keyOf` matches; `deletes`
  /// (rows the server marked `IsDeleted`) are removed by their key.
  /// Rows with no resolvable key are skipped (logged at the call site
  /// would be fine — keeping this layer pure).
  Future<void> applyDelta({
    required List<Map<String, dynamic>> upserts,
    required List<Map<String, dynamic>> deletes,
    required String Function(Map<String, dynamic>) keyOf,
  }) async {
    final byKey = <String, Map<String, dynamic>>{};
    for (final row in load()) {
      final k = keyOf(row);
      if (k.isNotEmpty) byKey[k] = row;
    }
    for (final row in upserts) {
      final k = keyOf(row);
      if (k.isNotEmpty) byKey[k] = row;
    }
    for (final row in deletes) {
      final k = keyOf(row);
      if (k.isNotEmpty) byKey.remove(k);
    }
    final merged = byKey.values.toList();
    await _prefs.setString(_dataKey, jsonEncode(merged));
    await _writeMeta(merged.length);
  }

  Future<void> _writeMeta(int count) async {
    await _prefs.setString(_metaKey, jsonEncode({
      'count': count,
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

  /// The cursor returned by the most recent successful replication
  /// pass. `null` when no replication has run yet (or after `clear()`
  /// / `clearCursor()`); the next call should then use a full
  /// replication starting from `lastKey=""`, `lastEntryNo=0`.
  ReplicationCursor? cursor() {
    final raw = _prefs.getString(_cursorKey);
    if (raw == null || raw.isEmpty) return null;
    final m = jsonDecode(raw);
    if (m is! Map<String, dynamic>) return null;
    return ReplicationCursor(
      lastKey: m['lastKey'] as String? ?? '',
      lastEntryNo: (m['lastEntryNo'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> saveCursor(ReplicationCursor c) async {
    await _prefs.setString(
      _cursorKey,
      jsonEncode({
        'lastKey': c.lastKey,
        'lastEntryNo': c.lastEntryNo,
      }),
    );
  }

  Future<void> clearCursor() async {
    await _prefs.remove(_cursorKey);
  }

  Future<void> clear() async {
    await _prefs.remove(_dataKey);
    await _prefs.remove(_metaKey);
    await _prefs.remove(_cursorKey);
  }
}

class ReplicationMeta {
  final int count;
  final DateTime? lastReplicatedAt;
  const ReplicationMeta({required this.count, this.lastReplicatedAt});
}

/// LS Central replication cursor — the (`lastKey`, `lastEntryNo`)
/// pair returned by every `Get…` / `ReplEcomm…` page. Persisted
/// between calls so delta replication can resume; reset to
/// `ReplicationCursor.empty` to force a full re-pull.
class ReplicationCursor {
  final String lastKey;
  final int lastEntryNo;
  const ReplicationCursor({required this.lastKey, required this.lastEntryNo});
  static const empty = ReplicationCursor(lastKey: '', lastEntryNo: 0);

  bool get isEmpty => lastKey.isEmpty && lastEntryNo == 0;

  @override
  String toString() => 'ReplicationCursor(lastKey=$lastKey, lastEntryNo=$lastEntryNo)';
}
