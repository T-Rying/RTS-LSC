/// One row from the BC `DiningAreaLayout` OData endpoint — metadata
/// about a specific (Dining Area, Layout) pair: capacity, how many
/// tables are in use, grid sizing, etc. The table rectangles for the
/// same pair come from `DiningTableLayout`; the two are combined in
/// the Hospitality page so the user sees both the floor plan and its
/// summary counts.
class DiningAreaLayout {
  final String areaId;
  final String layoutCode;
  final String description;
  final int totalCapacity;
  final int inUseDiningTables;
  final int availableDiningTables;
  final int notInUseDiningTables;
  final int combinedTables;
  final int pages;

  const DiningAreaLayout({
    required this.areaId,
    required this.layoutCode,
    required this.description,
    required this.totalCapacity,
    required this.inUseDiningTables,
    required this.availableDiningTables,
    required this.notInUseDiningTables,
    required this.combinedTables,
    required this.pages,
  });

  factory DiningAreaLayout.fromJson(Map<String, dynamic> j) => DiningAreaLayout(
        areaId: j['Dining_Area_ID'] as String? ?? '',
        layoutCode: j['Layout_Code'] as String? ?? '',
        description: j['Description'] as String? ?? '',
        totalCapacity: (j['Total_Capacity'] as num?)?.toInt() ?? 0,
        inUseDiningTables: (j['In_Use_Dining_Tables'] as num?)?.toInt() ?? 0,
        availableDiningTables: (j['Available_Dining_Tables'] as num?)?.toInt() ?? 0,
        notInUseDiningTables: (j['Not_in_Use_Dining_Tables'] as num?)?.toInt() ?? 0,
        combinedTables: (j['No_of_Combined_Tables'] as num?)?.toInt() ?? 0,
        pages: (j['Pages'] as num?)?.toInt() ?? 0,
      );
}

/// Splits a `Dining_Area_ID` (e.g. `S0005-RESTAURANT`) into a
/// restaurant identifier and an area identifier. IDs without a dash
/// are treated as unified (both halves equal the full ID) so standalone
/// areas like `LUKSA` or `DINING` still group sensibly.
({String restaurant, String area}) splitDiningAreaId(String id) {
  final idx = id.indexOf('-');
  if (idx < 0) return (restaurant: id, area: id);
  return (restaurant: id.substring(0, idx), area: id.substring(idx + 1));
}
