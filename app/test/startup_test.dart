import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alarm_app/main.dart';
import 'package:alarm_app/state/app_state.dart';

void main() {
  testWidgets('fresh install opens binding screen without network or map key', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await AppState.instance.bootstrap();
    await tester.pumpWidget(const AlarmApp());
    await tester.pump();
    expect(find.byType(TextFormField), findsWidgets);
    expect(find.text('巴法云 appID|secretKey'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    AppState.instance.stopClockForTest();
  });
}
