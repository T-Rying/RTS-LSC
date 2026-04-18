/// One row from the BC `HospitalityTypes` OData endpoint. The real
/// record has ~80 configuration fields; we only keep the ones the
/// mobile view actually renders or uses to cross-link to the other
/// two endpoints (`DiningAreaLayout` + `DiningTableLayout`).
///
/// Each row is a (Restaurant_No, Sales_Type) pair — e.g. the bar at
/// store S0005, or the drive-thru at S0017. The `Dining_Area_ID` +
/// `Current_Din_Area_Layout_Code` fields pin the type to a specific
/// floor plan; types without those values (counter, delivery, drive-
/// thru, etc.) have no graphical layout and the page just shows the
/// configuration summary for them.
class HospitalityType {
  final String restaurantNo;
  final int sequence;
  final String salesType;
  final String description;
  final String serviceType;
  final String serviceFlowId;
  final String diningAreaId;
  final String currentLayoutCode;
  final String orderId;
  final String layoutView;
  final String queueCounterCode;
  final int maxGuestsPerOrder;
  final String accessToOtherRestaurant;
  final bool viewMultipleRestaurants;

  const HospitalityType({
    required this.restaurantNo,
    required this.sequence,
    required this.salesType,
    required this.description,
    required this.serviceType,
    required this.serviceFlowId,
    required this.diningAreaId,
    required this.currentLayoutCode,
    required this.orderId,
    required this.layoutView,
    required this.queueCounterCode,
    required this.maxGuestsPerOrder,
    required this.accessToOtherRestaurant,
    required this.viewMultipleRestaurants,
  });

  bool get hasDiningArea =>
      diningAreaId.isNotEmpty && currentLayoutCode.isNotEmpty;

  /// The two `Layout_View` values LS Central uses to draw an actual
  /// floor plan on the POS: a free-form graphical view (tables placed
  /// by x/y coordinates and shape) and a row-column grid view (tables
  /// placed by row/col cell). Other layout views (KOT List, Order
  /// List, Delivery) don't have a drawable plan on this page.
  static const _graphicalViews = {
    'Graphical Dining Tables',
    'Dining Table Grid',
  };

  bool get hasGraphicalLayout =>
      hasDiningArea && _graphicalViews.contains(layoutView);

  String get displayLabel =>
      description.isNotEmpty ? '$salesType · $description' : salesType;

  factory HospitalityType.fromJson(Map<String, dynamic> j) => HospitalityType(
        restaurantNo: j['Restaurant_No'] as String? ?? '',
        sequence: (j['Sequence'] as num?)?.toInt() ?? 0,
        salesType: j['Sales_Type'] as String? ?? '',
        description: j['Description'] as String? ?? '',
        serviceType: j['Service_Type'] as String? ?? '',
        serviceFlowId: j['Service_Flow_ID'] as String? ?? '',
        diningAreaId: j['Dining_Area_ID'] as String? ?? '',
        currentLayoutCode: j['Current_Din_Area_Layout_Code'] as String? ?? '',
        orderId: j['Order_ID'] as String? ?? '',
        layoutView: j['Layout_View'] as String? ?? '',
        queueCounterCode: j['Queue_Counter_Code'] as String? ?? '',
        maxGuestsPerOrder: (j['Max_Guests_Per_Order'] as num?)?.toInt() ?? 0,
        accessToOtherRestaurant:
            j['Access_To_Other_Restaurant'] as String? ?? '',
        viewMultipleRestaurants: j['View_Multiple_Restaurants'] as bool? ?? false,
      );
}
