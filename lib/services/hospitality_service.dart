import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/dining_area_layout.dart';
import '../models/dining_table.dart';
import '../models/environment_config.dart';
import 'auth_service.dart';
import 'log_service.dart';

/// Bundled result of fetching both `DiningTableLayout` (per-table
/// positions) and `DiningAreaLayout` (per-area metadata). Both queries
/// are done in parallel so the Hospitality page only waits for the
/// slower of the two.
class HospitalityLayout {
  final List<DiningTable> tables;
  final List<DiningAreaLayout> areaLayouts;

  const HospitalityLayout({required this.tables, required this.areaLayouts});

  /// Looks up the DiningAreaLayout row for a given area + layout pair,
  /// or null if no such row exists.
  DiningAreaLayout? metaFor(String areaId, String layoutCode) {
    for (final meta in areaLayouts) {
      if (meta.areaId == areaId && meta.layoutCode == layoutCode) return meta;
    }
    return null;
  }
}

/// OData client for the BC Hospitality layout endpoints.
class HospitalityService {
  static const _bcSaasBaseUrl = 'https://api.businesscentral.dynamics.com/v2.0';

  final _log = LogService.instance;
  final AuthService _auth;

  HospitalityService({AuthService? auth}) : _auth = auth ?? AuthService.instance;

  /// Fetches table positions and area-layout metadata in parallel.
  Future<HospitalityLayout> fetchLayout(EnvironmentConfig config) async {
    if (config.type != ConnectionType.saas) {
      throw StateError('Hospitality currently supports SaaS connections only');
    }
    final token = await _auth.getAccessToken(config);
    final results = await Future.wait([
      _fetchTables(config, token),
      _fetchAreaLayouts(config, token),
    ]);
    return HospitalityLayout(
      tables: results[0] as List<DiningTable>,
      areaLayouts: results[1] as List<DiningAreaLayout>,
    );
  }

  Future<List<DiningTable>> _fetchTables(EnvironmentConfig config, String token) async {
    final list = await _fetchOData(
      token: token,
      url: _endpoint(config, 'DiningTableLayout'),
      label: 'DiningTableLayout',
    );
    final tables = list
        .whereType<Map<String, dynamic>>()
        .map(DiningTable.fromJson)
        .toList();
    _log.info('HospitalityService: fetched ${tables.length} dining tables');
    return tables;
  }

  Future<List<DiningAreaLayout>> _fetchAreaLayouts(EnvironmentConfig config, String token) async {
    final list = await _fetchOData(
      token: token,
      url: _endpoint(config, 'DiningAreaLayout'),
      label: 'DiningAreaLayout',
    );
    final layouts = list
        .whereType<Map<String, dynamic>>()
        .map(DiningAreaLayout.fromJson)
        .toList();
    _log.info('HospitalityService: fetched ${layouts.length} dining-area layouts');
    return layouts;
  }

  Future<List<dynamic>> _fetchOData({
    required String token,
    required Uri url,
    required String label,
  }) async {
    _log.info('HospitalityService: GET $url');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );
    if (response.statusCode != 200) {
      _log.error('HospitalityService: $label failed (${response.statusCode}): ${response.body}');
      throw HttpException(
        '$label failed (${response.statusCode}): ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw HttpException('$label response not a JSON object');
    }
    final value = decoded['value'];
    if (value is! List) {
      throw HttpException('$label response value is not a list');
    }
    return value;
  }

  Uri _endpoint(EnvironmentConfig config, String entitySet) {
    final tenant = Uri.encodeComponent(config.tenant);
    final env = Uri.encodeComponent(config.company);
    final company = Uri.encodeComponent(config.companyName);
    return Uri.parse(
      "$_bcSaasBaseUrl/$tenant/$env/ODataV4/Company('$company')/$entitySet",
    );
  }
}
