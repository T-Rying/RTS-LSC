import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/dining_area_layout.dart';
import '../models/dining_table.dart';
import '../models/environment_config.dart';
import '../models/hospitality_type.dart';
import 'auth_service.dart';
import 'log_service.dart';

/// Bundled result of fetching the three Hospitality OData entities:
/// * `HospitalityTypes` — Restaurant_No × Sales_Type configuration rows
/// * `DiningAreaLayout` — per-area metadata (capacity, counts, grid size)
/// * `DiningTableLayout` — per-table design-space rectangles
///
/// All three are requested in parallel with the same OAuth bearer token.
class HospitalityLayout {
  final List<HospitalityType> types;
  final List<DiningAreaLayout> areaLayouts;
  final List<DiningTable> tables;

  const HospitalityLayout({
    required this.types,
    required this.areaLayouts,
    required this.tables,
  });

  /// Only the types this page can actually draw — `Graphical Dining
  /// Tables` and `Dining Table Grid`. Everything else (KOT List,
  /// Order List, Delivery, Drive-thru, Self Service) is hidden on the
  /// mobile view because there is no floor plan to show.
  List<HospitalityType> get graphicalTypes =>
      types.where((t) => t.hasGraphicalLayout).toList();

  /// Unique restaurant codes that have at least one graphical type.
  List<String> restaurants() =>
      (graphicalTypes.map((t) => t.restaurantNo).toSet().toList()..sort());

  /// Graphical hospitality types for a given restaurant, ordered by
  /// their configured Sequence (the same order LS Central shows them).
  List<HospitalityType> typesFor(String restaurantNo) =>
      graphicalTypes.where((t) => t.restaurantNo == restaurantNo).toList()
        ..sort((a, b) => a.sequence.compareTo(b.sequence));

  /// A human-readable label for a restaurant, combining its code with
  /// a description derived from its hospitality types. We pick the
  /// `RESTAURANT` sales type's description when available (that row is
  /// almost always the main dining description — e.g. "Restaurant
  /// Downstairs", "Upstairs Coffee House"), otherwise we fall back to
  /// the first graphical type's description. If neither has a
  /// description set we just return the bare code.
  String restaurantLabel(String restaurantNo) {
    final typesHere = typesFor(restaurantNo);
    if (typesHere.isEmpty) return restaurantNo;
    final main = typesHere.firstWhere(
      (t) => t.salesType == 'RESTAURANT' && t.description.isNotEmpty,
      orElse: () => typesHere.firstWhere(
        (t) => t.description.isNotEmpty,
        orElse: () => typesHere.first,
      ),
    );
    if (main.description.isEmpty) return restaurantNo;
    return '$restaurantNo · ${main.description}';
  }

  DiningAreaLayout? metaFor(String areaId, String layoutCode) {
    if (areaId.isEmpty || layoutCode.isEmpty) return null;
    for (final meta in areaLayouts) {
      if (meta.areaId == areaId && meta.layoutCode == layoutCode) return meta;
    }
    return null;
  }

  List<DiningTable> tablesFor(String areaId, String layoutCode) {
    if (areaId.isEmpty || layoutCode.isEmpty) return const [];
    return tables
        .where((t) => t.areaId == areaId && t.layoutCode == layoutCode)
        .toList();
  }
}

/// OData client for the BC Hospitality endpoints used by the mobile
/// Hospitality page.
class HospitalityService {
  static const _bcSaasBaseUrl = 'https://api.businesscentral.dynamics.com/v2.0';

  final _log = LogService.instance;
  final AuthService _auth;

  HospitalityService({AuthService? auth}) : _auth = auth ?? AuthService.instance;

  Future<HospitalityLayout> fetchLayout(EnvironmentConfig config) async {
    if (config.type != ConnectionType.saas) {
      throw StateError('Hospitality currently supports SaaS connections only');
    }
    final token = await _auth.getAccessToken(config);
    final results = await Future.wait([
      _fetchTypes(config, token),
      _fetchAreaLayouts(config, token),
      _fetchTables(config, token),
    ]);
    return HospitalityLayout(
      types: results[0] as List<HospitalityType>,
      areaLayouts: results[1] as List<DiningAreaLayout>,
      tables: results[2] as List<DiningTable>,
    );
  }

  Future<List<HospitalityType>> _fetchTypes(EnvironmentConfig config, String token) async {
    final list = await _fetchOData(
      token: token,
      url: _endpoint(config, 'HospitalityTypes'),
      label: 'HospitalityTypes',
    );
    final types = list
        .whereType<Map<String, dynamic>>()
        .map(HospitalityType.fromJson)
        .toList();
    _log.info('HospitalityService: fetched ${types.length} hospitality types');
    return types;
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
