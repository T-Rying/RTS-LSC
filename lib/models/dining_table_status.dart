/// One row from the BC `DiningTables` OData endpoint — the live
/// status view of a physical dining table.
///
/// Joined back to `DiningTableLayout` by `(Dining_Area_ID,
/// Dining_Table_No)`. A single physical table can appear in multiple
/// layouts but has one live status.
class DiningTableStatus {
  final String areaId;
  final int tableNo;
  final String status;
  final String sectionCode;
  final String typeId;
  final String shape;
  final int seatCapacity;
  final int minCapacity;
  final int maxCapacity;
  final String statusWithError;

  const DiningTableStatus({
    required this.areaId,
    required this.tableNo,
    required this.status,
    required this.sectionCode,
    required this.typeId,
    required this.shape,
    required this.seatCapacity,
    required this.minCapacity,
    required this.maxCapacity,
    required this.statusWithError,
  });

  factory DiningTableStatus.fromJson(Map<String, dynamic> j) =>
      DiningTableStatus(
        areaId: j['Dining_Area_ID'] as String? ?? '',
        tableNo: (j['Dining_Table_No'] as num?)?.toInt() ?? 0,
        status: j['Dining_Table_Status'] as String? ?? '',
        sectionCode: j['Default_Section_Code'] as String? ?? '',
        typeId: j['Dining_Table_Type_ID'] as String? ?? '',
        shape: j['Shape'] as String? ?? '',
        seatCapacity: (j['Seat_Capacity'] as num?)?.toInt() ?? 0,
        minCapacity: (j['Min_Capacity'] as num?)?.toInt() ?? 0,
        maxCapacity: (j['Max_Capacity'] as num?)?.toInt() ?? 0,
        statusWithError: (j['StatusWithError'] as String? ?? '').trim(),
      );

  /// Stable lookup key used when joining with `DiningTableLayout` rows.
  static String keyFor(String areaId, int tableNo) => '$areaId|$tableNo';
  String get key => keyFor(areaId, tableNo);
}
