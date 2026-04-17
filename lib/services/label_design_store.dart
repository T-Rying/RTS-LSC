import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/label_design.dart';

/// Persists label designs locally under the key `label_designs` as a
/// JSON array of design objects. Designs can be exported to / imported
/// from JSON strings to move them between devices.
class LabelDesignStore {
  static const _key = 'label_designs';

  final SharedPreferences _prefs;

  LabelDesignStore(this._prefs);

  List<LabelDesign> list() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(LabelDesign.fromJson)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  LabelDesign? get(String id) {
    for (final d in list()) {
      if (d.id == id) return d;
    }
    return null;
  }

  Future<void> save(LabelDesign design) async {
    final all = list();
    design.updatedAt = DateTime.now();
    final idx = all.indexWhere((d) => d.id == design.id);
    if (idx >= 0) {
      all[idx] = design;
    } else {
      all.add(design);
    }
    await _writeAll(all);
  }

  Future<void> delete(String id) async {
    final all = list()..removeWhere((d) => d.id == id);
    await _writeAll(all);
  }

  /// Encodes one design as a JSON string suitable for sharing.
  String exportDesign(LabelDesign design) {
    return const JsonEncoder.withIndent('  ').convert(design.toJson());
  }

  /// Imports a design JSON string. If a design with the same id already
  /// exists, the import keeps both by assigning a fresh id to the newcomer.
  Future<LabelDesign> importDesignJson(String jsonText) async {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected a JSON object');
    }
    final imported = LabelDesign.fromJson(decoded);
    final existingIds = list().map((d) => d.id).toSet();
    if (existingIds.contains(imported.id)) {
      imported.id = '${imported.id}_imported_${DateTime.now().microsecondsSinceEpoch}';
      imported.name = '${imported.name} (imported)';
    }
    imported.updatedAt = DateTime.now();
    await save(imported);
    return imported;
  }

  Future<void> _writeAll(List<LabelDesign> designs) async {
    final jsonList = designs.map((d) => d.toJson()).toList();
    await _prefs.setString(_key, jsonEncode(jsonList));
  }
}
