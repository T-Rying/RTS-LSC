import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/environment_config.dart';
import 'auth_service.dart';
import 'log_service.dart';

/// SOAP client for the ODataRequest codeunit (Mobile Inventory replication).
class InventoryService {
  static const _bcSaasBaseUrl = 'https://api.businesscentral.dynamics.com/v2.0';
  static const _soapNamespace = 'urn:microsoft-dynamics-schemas/codeunit/ODataRequest';

  final _log = LogService.instance;
  final AuthService _auth;

  InventoryService({AuthService? auth}) : _auth = auth ?? AuthService.instance;

  Uri _endpointFor(EnvironmentConfig config) {
    if (config.type != ConnectionType.saas) {
      throw StateError('Mobile Inventory currently supports SaaS connections only');
    }
    final tenant = Uri.encodeComponent(config.tenant);
    final env = Uri.encodeComponent(config.company);
    final company = Uri.encodeComponent(config.companyName);
    return Uri.parse('$_bcSaasBaseUrl/$tenant/$env/WS/$company/Codeunit/ODataRequest');
  }

  /// Calls the GetBarcode codeunit. Returns the raw payload string from
  /// `<return_value>`, which BC usually fills with JSON text.
  Future<String> getBarcodeRaw(EnvironmentConfig config) async {
    if (config.storeNo.isEmpty) {
      throw StateError('Store No. is required (set it in Settings → Mobile Inventory)');
    }

    final token = await _auth.getAccessToken(config);
    final url = _endpointFor(config);

    final body = '''<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
               xmlns:ns="$_soapNamespace">
  <soap:Body>
    <ns:GetBarcode>
      <ns:storeNo>${_xmlEscape(config.storeNo)}</ns:storeNo>
      <ns:batchSize>1000</ns:batchSize>
      <ns:fullRepl>true</ns:fullRepl>
      <ns:lastKey></ns:lastKey>
      <ns:lastEntryNo>0</ns:lastEntryNo>
    </ns:GetBarcode>
  </soap:Body>
</soap:Envelope>''';

    _log.info('InventoryService: POST $url (GetBarcode, store=${config.storeNo})');

    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'text/xml; charset=utf-8',
        'SOAPAction': '$_soapNamespace:GetBarcode',
      },
      body: body,
    );

    if (response.statusCode != 200) {
      _log.error('InventoryService: GetBarcode failed (${response.statusCode}): ${response.body}');
      throw HttpException(
        'GetBarcode failed (${response.statusCode}): ${_extractFaultString(response.body) ?? response.body}',
      );
    }

    final payload = _extractReturnValue(response.body);
    if (payload == null) {
      throw const HttpException('GetBarcode response missing <return_value>');
    }
    _log.info('InventoryService: GetBarcode ok, ${payload.length} chars returned');
    return payload;
  }

  /// Parses the return_value as JSON and extracts a list of barcode rows.
  /// Accepts either a bare JSON array or an object with a common wrapper key.
  Future<List<Map<String, dynamic>>> getBarcodes(EnvironmentConfig config) async {
    final raw = await getBarcodeRaw(config);
    final decoded = _tryDecodeJson(raw);
    if (decoded is List) {
      return decoded.whereType<Map<String, dynamic>>().toList();
    }
    if (decoded is Map<String, dynamic>) {
      for (final key in const ['barcodes', 'Barcodes', 'value', 'data', 'items']) {
        final v = decoded[key];
        if (v is List) return v.whereType<Map<String, dynamic>>().toList();
      }
    }
    throw HttpException('Unexpected payload shape: ${raw.substring(0, raw.length.clamp(0, 200))}');
  }

  static dynamic _tryDecodeJson(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return null;
    }
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
