import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/environment_config.dart';
import 'auth_service.dart';
import 'log_service.dart';

/// SOAP client for the ODataRequest codeunit (Mobile Inventory replication).
/// Generic replication loop — each entity supplies its own SOAP operation and
/// any operation-specific body fields (e.g. `storeNo` for GetBarcode).
class InventoryService {
  static const _bcSaasBaseUrl = 'https://api.businesscentral.dynamics.com/v2.0';
  static const _soapNamespace = 'urn:microsoft-dynamics-schemas/codeunit/ODataRequest';
  static const _batchSize = 1000;
  static const _maxPages = 200; // safety cap (200 × 1000 = 200k rows)

  final _log = LogService.instance;
  final AuthService _auth;

  InventoryService({AuthService? auth}) : _auth = auth ?? AuthService.instance;

  Future<List<Map<String, dynamic>>> getBarcodes(EnvironmentConfig config) {
    if (config.storeNo.isEmpty) {
      throw StateError('Store No. is required (set it in Settings → Mobile Inventory)');
    }
    return _replicate(
      config,
      operation: 'GetBarcode',
      extraFields: {'storeNo': config.storeNo},
    );
  }

  Future<List<Map<String, dynamic>>> getItemCategories(EnvironmentConfig config) {
    return _replicate(config, operation: 'GetItemCategory');
  }

  Future<List<Map<String, dynamic>>> getItemVariants(EnvironmentConfig config) {
    if (config.storeNo.isEmpty) {
      throw StateError('Store No. is required (set it in Settings → Mobile Inventory)');
    }
    return _replicate(
      config,
      operation: 'GetItemVariant',
      extraFields: {'storeNo': config.storeNo},
    );
  }

  Future<List<Map<String, dynamic>>> getSalesPrices(EnvironmentConfig config) {
    if (config.storeNo.isEmpty) {
      throw StateError('Store No. is required (set it in Settings → Mobile Inventory)');
    }
    return _replicate(
      config,
      operation: 'GetSalesPrice',
      extraFields: {'storeNo': config.storeNo},
    );
  }

  Future<List<Map<String, dynamic>>> getItemUnitOfMeasures(EnvironmentConfig config) {
    if (config.storeNo.isEmpty) {
      throw StateError('Store No. is required (set it in Settings → Mobile Inventory)');
    }
    return _replicate(
      config,
      operation: 'GetItemUnitOfMeasure',
      extraFields: {'storeNo': config.storeNo},
    );
  }

  Future<List<Map<String, dynamic>>> _replicate(
    EnvironmentConfig config, {
    required String operation,
    Map<String, String> extraFields = const {},
  }) async {
    final all = <Map<String, dynamic>>[];
    var lastKey = '';
    var lastEntryNo = 0;
    var fullRepl = true;

    for (var page = 1; page <= _maxPages; page++) {
      final result = await _fetchPage(
        config,
        operation: operation,
        extraFields: extraFields,
        fullRepl: fullRepl,
        lastKey: lastKey,
        lastEntryNo: lastEntryNo,
      );

      if (result.status.toLowerCase() != 'ok') {
        throw HttpException('BC replication error: ${result.errorText}');
      }

      all.addAll(result.upserts);
      _log.info(
        'InventoryService: $operation page $page — ${result.upserts.length} upserts '
        '(total ${all.length}), endOfTable=${result.endOfTable}',
      );

      if (result.endOfTable) return all;

      lastKey = result.lastKey;
      lastEntryNo = result.lastEntryNo;
      fullRepl = false;
    }

    throw const HttpException('Replication exceeded safety cap');
  }

  Future<_ReplicationPage> _fetchPage(
    EnvironmentConfig config, {
    required String operation,
    required Map<String, String> extraFields,
    required bool fullRepl,
    required String lastKey,
    required int lastEntryNo,
  }) async {
    if (config.type != ConnectionType.saas) {
      throw StateError('Mobile Inventory currently supports SaaS connections only');
    }

    final token = await _auth.getAccessToken(config);
    final url = _endpointFor(config);
    final body = _buildSoapBody(
      operation: operation,
      extraFields: extraFields,
      fullRepl: fullRepl,
      lastKey: lastKey,
      lastEntryNo: lastEntryNo,
    );

    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'text/xml; charset=utf-8',
        'SOAPAction': '$_soapNamespace:$operation',
      },
      body: body,
    );

    if (response.statusCode != 200) {
      _log.error('InventoryService: $operation failed (${response.statusCode}): ${response.body}');
      throw HttpException(
        '$operation failed (${response.statusCode}): ${_extractFaultString(response.body) ?? response.body}',
      );
    }

    final payload = _extractReturnValue(response.body);
    if (payload == null) {
      throw HttpException('$operation response missing <return_value>');
    }

    final json = jsonDecode(payload);
    if (json is! Map<String, dynamic>) {
      throw HttpException('Unexpected payload shape: ${payload.substring(0, payload.length.clamp(0, 200))}');
    }

    final page = _ReplicationPage.fromJson(json);
    if (page.upserts.isEmpty && page.deletes.isEmpty) {
      _log.debug(
        'InventoryService: $operation returned 0 rows — top-level keys: ${json.keys.toList()} · '
        'status="${page.status}" endOfTable=${page.endOfTable} · '
        'payload snippet: ${payload.substring(0, payload.length.clamp(0, 3000))}',
      );
    }
    return page;
  }

  Uri _endpointFor(EnvironmentConfig config) {
    final tenant = Uri.encodeComponent(config.tenant);
    final env = Uri.encodeComponent(config.company);
    final company = Uri.encodeComponent(config.companyName);
    return Uri.parse('$_bcSaasBaseUrl/$tenant/$env/WS/$company/Codeunit/ODataRequest');
  }

  String _buildSoapBody({
    required String operation,
    required Map<String, String> extraFields,
    required bool fullRepl,
    required String lastKey,
    required int lastEntryNo,
  }) {
    final buf = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="utf-8"?>')
      ..writeln('<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"')
      ..writeln('               xmlns:ns="$_soapNamespace">')
      ..writeln('  <soap:Body>')
      ..writeln('    <ns:$operation>');
    for (final entry in extraFields.entries) {
      buf.writeln('      <ns:${entry.key}>${_xmlEscape(entry.value)}</ns:${entry.key}>');
    }
    buf
      ..writeln('      <ns:batchSize>$_batchSize</ns:batchSize>')
      ..writeln('      <ns:fullRepl>$fullRepl</ns:fullRepl>')
      ..writeln('      <ns:lastKey>${_xmlEscape(lastKey)}</ns:lastKey>')
      ..writeln('      <ns:lastEntryNo>$lastEntryNo</ns:lastEntryNo>')
      ..writeln('    </ns:$operation>')
      ..writeln('  </soap:Body>')
      ..write('</soap:Envelope>');
    return buf.toString();
  }

  static List<Map<String, dynamic>> _parseRecRef(Map<String, dynamic>? recRefJson) {
    if (recRefJson == null) return const [];
    final fields = recRefJson['RecordFields'] as List? ?? const [];
    final indexToName = <int, String>{};
    for (final f in fields) {
      if (f is! Map) continue;
      final idx = (f['FieldIndex'] as num?)?.toInt();
      final name = f['FieldName'] as String?;
      if (idx != null && name != null) indexToName[idx] = name;
    }

    final records = recRefJson['Records'] as List? ?? const [];
    final rows = <Map<String, dynamic>>[];
    for (final r in records) {
      if (r is! Map) continue;
      final row = <String, dynamic>{};
      final recFields = r['Fields'] as List? ?? const [];
      for (final field in recFields) {
        if (field is! Map) continue;
        final idx = (field['FieldIndex'] as num?)?.toInt();
        if (idx == null) continue;
        final name = indexToName[idx];
        if (name == null) continue;
        row[name] = field['FieldValue'];
      }
      if (row.isNotEmpty) rows.add(row);
    }
    return rows;
  }

  /// Parses the `DynDataSet` payload shape used by newer BC replication ops
  /// (e.g. `GetItemUnitOfMeasure`). Field metadata lives under `DataSetFields`
  /// and records under `DataSetRecords` (each with a `Fields` array of
  /// `{FieldIndex, FieldValue}`).
  static List<Map<String, dynamic>> _parseDynDataSet(Map<String, dynamic>? dynDataSet) {
    if (dynDataSet == null) return const [];
    final fields = dynDataSet['DataSetFields'] as List? ?? const [];
    final indexToName = <int, String>{};
    for (final f in fields) {
      if (f is! Map) continue;
      final idx = (f['FieldIndex'] as num?)?.toInt();
      final name = f['FieldName'] as String?;
      if (idx != null && name != null) indexToName[idx] = name;
    }

    final records = (dynDataSet['DataSetRecords'] as List?)
        ?? (dynDataSet['Records'] as List?)
        ?? const [];
    final rows = <Map<String, dynamic>>[];
    for (final r in records) {
      if (r is! Map) continue;
      final row = <String, dynamic>{};
      final recFields = (r['Fields'] as List?)
          ?? (r['DataSetFields'] as List?)
          ?? const [];
      for (final field in recFields) {
        if (field is! Map) continue;
        final idx = (field['FieldIndex'] as num?)?.toInt();
        if (idx == null) continue;
        final name = indexToName[idx];
        if (name == null) continue;
        row[name] = field['FieldValue'];
      }
      if (row.isNotEmpty) rows.add(row);
    }
    return rows;
  }

  static String? _extractReturnValue(String soapBody) {
    final match = RegExp(
      r'<(?:\w+:)?return_value[^>]*>([\s\S]*?)</(?:\w+:)?return_value>',
    ).firstMatch(soapBody);
    if (match == null) return null;
    return _xmlUnescape(match.group(1)!);
  }

  static String? _extractFaultString(String soapBody) {
    final m = RegExp(r'<faultstring[^>]*>([\s\S]*?)</faultstring>').firstMatch(soapBody);
    return m == null ? null : _xmlUnescape(m.group(1)!).trim();
  }

  static String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _xmlUnescape(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

class _ReplicationPage {
  final String status;
  final String errorText;
  final String lastKey;
  final int lastEntryNo;
  final bool endOfTable;
  final List<Map<String, dynamic>> upserts;
  final List<Map<String, dynamic>> deletes;

  const _ReplicationPage({
    required this.status,
    required this.errorText,
    required this.lastKey,
    required this.lastEntryNo,
    required this.endOfTable,
    required this.upserts,
    required this.deletes,
  });

  factory _ReplicationPage.fromJson(Map<String, dynamic> json) {
    final tableData = json['TableData'] as Map<String, dynamic>?;
    final dataSet = json['DataSet'] as Map<String, dynamic>?;

    List<Map<String, dynamic>> upserts = const [];
    List<Map<String, dynamic>> deletes = const [];

    if (tableData != null) {
      final upd = tableData['TableDataUpd'] as Map<String, dynamic>?;
      final del = tableData['TableDataDel'] as Map<String, dynamic>?;
      upserts = InventoryService._parseRecRef(upd?['RecRefJson'] as Map<String, dynamic>?);
      deletes = InventoryService._parseRecRef(del?['RecRefJson'] as Map<String, dynamic>?);
    } else if (dataSet != null) {
      final upd = dataSet['DataSetUpd'] as Map<String, dynamic>?;
      final del = dataSet['DataSetDel'] as Map<String, dynamic>?;
      upserts = InventoryService._parseDynDataSet(upd?['DynDataSet'] as Map<String, dynamic>?);
      deletes = InventoryService._parseDynDataSet(del?['DynDataSet'] as Map<String, dynamic>?);
    }

    return _ReplicationPage(
      status: json['Status'] as String? ?? '',
      errorText: json['ErrorText'] as String? ?? '',
      lastKey: json['LastKey'] as String? ?? '',
      lastEntryNo: (json['LastEntryNo'] as num?)?.toInt() ?? 0,
      endOfTable: json['EndOfTable'] as bool? ?? true,
      upserts: upserts,
      deletes: deletes,
    );
  }
}
