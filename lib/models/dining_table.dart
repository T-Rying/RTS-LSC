/// One row from the BC DiningTableLayout OData endpoint. Coordinates
/// are in the designer's pixel space (same units the back-office
/// dining-table designer uses) — we scale them to the screen at render
/// time rather than storing pre-scaled values.
class DiningTable {
  final String areaId;
  final String layoutCode;
  final int tableNo;
  final int x1;
  final int y1;
  final int x2;
  final int y2;

  const DiningTable({
    required this.areaId,
    required this.layoutCode,
    required this.tableNo,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  int get width => x2 - x1;
  int get height => y2 - y1;

  factory DiningTable.fromJson(Map<String, dynamic> j) => DiningTable(
        areaId: j['Dining_Area_ID'] as String? ?? '',
        layoutCode: j['Dining_Area_Layout_Code'] as String? ?? '',
        tableNo: (j['Dining_Table_No'] as num?)?.toInt() ?? 0,
        x1: (j['X1_Position_Design'] as num?)?.toInt() ?? 0,
        y1: (j['Y1_Position_Design'] as num?)?.toInt() ?? 0,
        x2: (j['X2_Position_Design'] as num?)?.toInt() ?? 0,
        y2: (j['Y2_Position_Design'] as num?)?.toInt() ?? 0,
      );
}
