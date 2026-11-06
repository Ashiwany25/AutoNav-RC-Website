import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:autonav_rc/screens/indoor_map_screen.dart';

void main() {
  group('Indoor Map UI tests', () {
    testWidgets('Indoor Map screen displays its AppBar title', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: IndoorMapScreen(
            httpClient: MockClient((request) async {
              return http.Response(
                '{"detail":"Offline widget test"}',
                503,
                headers: {'content-type': 'application/json'},
              );
            }),
          ),
        ),
      );

      // Find the title specifically inside the AppBar.
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Indoor Map'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Indoor Map displays navigation information', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: IndoorMapScreen(
            httpClient: MockClient((request) async {
              return http.Response(
                '{"detail":"Offline widget test"}',
                503,
                headers: {'content-type': 'application/json'},
              );
            }),
          ),
        ),
      );

      expect(find.textContaining('Navigation status:'), findsOneWidget);
    });
  });
}
