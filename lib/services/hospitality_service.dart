import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/dining_area_layout.dart';
import '../models/dining_table.dart';
import '../models/dining_table_status.dart';
import '../models/environment_config.dart';
import '../models/hospitality_type.dart';
import 'auth_service.dart';
import 'log_service.dart';

/// Bundled result of fetching the four Hospitality OData entities:
/// * `HospitalityTypes` — Restaurant_No × Sales_Type configuration rows
/// * `DiningAreaLayout` — per-area metadata (capacity, counts, grid size)
/// * `DiningTableLayout` — per-table design-space rectangles
/// * `DiningTables` — live per-table status (Free / Occupied / Dirty / …),
///   capacity and shape; joined back to the layout rows by
///   `(Dining_Area_ID, Dining_Table_No)`.
///
/// All four are requested in parallel with the same OAuth bearer token.
class HospitalityLayout {
  final List<HospitalityType> types;
  final List<DiningAreaLayout> areaLayouts;
  final List<DiningTable> tables;
  final Map<String, DiningTableStatus> statusByKey;

  const HospitalityLayout({
    required this.types,
    required this.areaLayouts,
    required this.tables,
    required this.statusByKey,
  });

  /// Returns the live status row for a drawn table, or `null` when the
  /// `DiningTables` endpoint has no matching entry (e.g. the table
  /// exists in the layout but isn't configured for service).
  DiningTableStatus? statusFor(String areaId, int tableNo) =>
      statusByKey[DiningTableStatus.keyFor(areaId, tableNo)];

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
  /// a name.
  ///
  /// When [storeNames] contains an entry for [restaurantNo] (populated
  /// from the replicated Store table — `GetStoreBuffer`), we use the
  /// real store name ("Cronus Restaurant", "Cronus Café", …). That's
  /// the preferred source because it's the name LS Central itself
  /// shows.
  ///
  /// If no store name is available (e.g. the user hasn't replicated
  /// Stores yet), we derive a description from the hospitality types
  /// instead: the `RESTAURANT` sales-type's description when present,
  /// otherwise the first graphical type's description. If neither has
  /// a description set we just return the bare code.
  String restaurantLabel(String restaurantNo, {Map<String, String>? storeNames}) {
    final storeName = storeNames?[restaurantNo];
    if (storeName != null && storeName.isNotEmpty) {
      return '$restaurantNo · $storeName';
    }
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
      _fetchTableStatuses(config, token),
    ]);
    final statuses = results[3] as List<DiningTableStatus>;
    return HospitalityLayout(
      types: results[0] as List<HospitalityType>,
      areaLayouts: results[1] as List<DiningAreaLayout>,
      tables: results[2] as List<DiningTable>,
      statusByKey: {for (final s in statuses) s.key: s},
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

  Future<List<DiningTableStatus>> _fetchTableStatuses(
      EnvironmentConfig config, String token) async {
    final list = await _fetchOData(
      token: token,
      url: _endpoint(config, 'DiningTables'),
      label: 'DiningTables',
    );
    final statuses = list
        .whereType<Map<String, dynamic>>()
        .map(DiningTableStatus.fromJson)
        .toList();
    _log.info('HospitalityService: fetched ${statuses.length} dining table statuses');
    return statuses;
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

  /// Single-row URL for a `DiningTables` key pair — encoded for use as
  /// the target of an OData V4 `PATCH`. Single quotes inside the area
  /// ID are doubled per OData literal rules, then percent-encoded.
  Uri _diningTableRowEndpoint(
      EnvironmentConfig config, String areaId, int tableNo) {
    final base = _endpoint(config, 'DiningTables');
    final literal = Uri.encodeComponent(areaId.replaceAll("'", "''"));
    return Uri.parse(
      "$base(Dining_Area_ID='$literal',Dining_Table_No=$tableNo)",
    );
  }

  /// PATCHes the `Dining_Table_Status` field on a single row of the
  /// `DiningTables` page web service. Uses the row's `@odata.etag` as
  /// `If-Match` so we fail fast if another client has already changed
  /// the row.
  ///
  /// Throws when the page rejects the write — most commonly because the
  /// stock LS Central `Dining Tables` page has `Dining_Table_Status` as
  /// `Editable = false`. In that case the caller should surface the
  /// error as-is rather than retry.
  Future<void> updateTableStatus(
    EnvironmentConfig config, {
    required String areaId,
    required int tableNo,
    required String etag,
    required String newStatus,
  }) async {
    if (config.type != ConnectionType.saas) {
      throw StateError('Hospitality updates require a SaaS connection');
    }
    final token = await _auth.getAccessToken(config);
    final url = _diningTableRowEndpoint(config, areaId, tableNo);
    _log.info('HospitalityService: PATCH $url → $newStatus');
    final response = await http.patch(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'If-Match': etag.isEmpty ? '*' : etag,
      },
      body: jsonEncode({'Dining_Table_Status': newStatus}),
    );
    if (response.statusCode == 200 || response.statusCode == 204) {
      _log.info(
          'HospitalityService: PATCH DiningTables OK (${response.statusCode})');
      return;
    }
    _log.error(
        'HospitalityService: PATCH DiningTables failed (${response.statusCode}): ${response.body}');
    throw HttpException(
      'PATCH DiningTables failed (${response.statusCode}): ${response.body}',
    );
  }
}
