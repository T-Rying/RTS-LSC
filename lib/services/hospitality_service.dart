import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/dining_table.dart';
import '../models/environment_config.dart';
import 'auth_service.dart';
import 'log_service.dart';

/// OData client for the BC DiningTableLayout endpoint. Returns the raw
/// rows; grouping by area / layout is done in the UI so the same fetch
/// feeds multiple views without re-querying.
class HospitalityService {
  static const _bcSaasBaseUrl = 'https://api.businesscentral.dynamics.com/v2.0';

  final _log = LogService.instance;
  final AuthService _auth;

  HospitalityService({AuthService? auth}) : _auth = auth ?? AuthService.instance;

  Future<List<DiningTable>> fetchTables(EnvironmentConfig config) async {
    if (config.type != ConnectionType.saas) {
      throw StateError('Hospitality currently supports SaaS connections only');
    }

    final token = await _auth.getAccessToken(config);
    final url = _endpointFor(config);

    _log.info('HospitalityService: GET $url');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      _log.error(
        'HospitalityService: DiningTableLayout failed (${response.statusCode}): ${response.body}',
      );
      throw HttpException(
        'DiningTableLayout failed (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const HttpException('Unexpected response shape: not a JSON object');
    }
    final value = decoded['value'];
    if (value is! List) {
      throw const HttpException('Unexpected response shape: value is not a list');
    }

    final tables = value
        .whereType<Map<String, dynamic>>()
        .map(DiningTable.fromJson)
        .toList();
    _log.info('HospitalityService: fetched ${tables.length} dining tables');
    return tables;
  }

  Uri _endpointFor(EnvironmentConfig config) {
    final tenant = Uri.encodeComponent(config.tenant);
    final env = Uri.encodeComponent(config.company);
    final company = Uri.encodeComponent(config.companyName);
    // BC OData v4 expects the company name in single quotes inside the path.
    return Uri.parse(
      "$_bcSaasBaseUrl/$tenant/$env/ODataV4/Company('$company')/DiningTableLayout",
    );
  }
}
