
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:autonav_rc/main.dart';

void main() {
  testWidgets(
    'AutoNav RC dashboard loads correctly',
    (WidgetTester tester) async {
      // Configure a phone-sized test screen.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Launch AutoNav RC.
      await tester.pumpWidget(const AutoNavApp());
      await tester.pumpAndSettle();

      // Verify dashboard heading.
      expect(
        find.text('Welcome to AutoNav RC'),
        findsOneWidget,
      );

      // Verify navigation options.
      expect(find.text('Manual Control'), findsOneWidget);
      expect(find.text('Indoor Map'), findsOneWidget);
      expect(find.text('Auto Navigation'), findsOneWidget);

      // Find the button even if it is off-screen.
      final emergencyButton = find.text(
        'EMERGENCY STOP',
        skipOffstage: false,
      );

      expect(emergencyButton, findsOneWidget);

      // Verify demo mode.
      expect(find.text('DEMO MODE'), findsOneWidget);
    },
  );
}
