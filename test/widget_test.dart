import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rts_lsc/main.dart';
import 'package:rts_lsc/services/environment_service.dart';

void main() {
  testWidgets('Homepage shows three module buttons and settings icon', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    environmentService = EnvironmentService(prefs);

    await tester.pumpWidget(const MyApp());

    expect(find.text('POS'), findsOneWidget);
    expect(find.text('Mobile Inventory'), findsOneWidget);
    expect(find.text('Hospitality'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.gear), findsOneWidget);
  });
}
