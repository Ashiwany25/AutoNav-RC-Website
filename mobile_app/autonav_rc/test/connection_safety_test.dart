
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:autonav_rc/screens/indoor_map_screen.dart';

void main() {
  testWidgets(
    'Navigation is disabled offline and restored online',
    (tester) async {
      bool apiOnline = true;
      int startCalls = 0;

      final mockClient = MockClient((request) async {
        if (!apiOnline) {
          throw Exception('Connection lost');
        }

        final endpoint = request.url.path;

        if (endpoint == '/api/v1/maps/current') {
          return http.Response(
            jsonEncode({
              'success': true,
              'map_name': 'Connection Safety Map',
              'width': 15,
              'height': 15,
              'resolution': 0.1,
              'grid': List.generate(
                15,
                (_) => List.filled(15, 0),
              ),
              'robot_position': {
                'row': 2,
                'col': 2,
              },
            }),
            200,
          );
        }

        if (endpoint == '/api/v1/navigation/status') {
          return http.Response(
            jsonEncode({
              'success': true,
              'navigation_state': 'IDLE',
              'position': {
                'row': 2,
                'col': 2,
              },
              'current_step': 0,
              'total_steps': 0,
              'remaining_steps': 0,
            }),
            200,
          );
        }

        if (endpoint == '/api/v1/navigation/start') {
          startCalls++;

          return http.Response(
            jsonEncode({
              'success': true,
              'navigation_state': 'NAVIGATING',
            }),
            200,
          );
        }

        return http.Response(
          jsonEncode({
            'success': false,
            'message': 'Unknown endpoint',
          }),
          404,
        );
      });

      addTearDown(mockClient.close);

      tester.view.physicalSize =
          const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Future<void> finishRequests() async {
        await tester.runAsync(() async {
          await Future<void>.delayed(
            const Duration(milliseconds: 30),
          );
        });
        await tester.pump();
      }

       
ElevatedButton getStartButton() {
  // Locate the navigation button by its icon,
  // even when the button is outside the visible
  // part of the scrollable screen.
  final navigationIcon = find.byIcon(
    Icons.navigation_outlined,
    skipOffstage: false,
  );

  final buttonFinder = find.ancestor(
    of: navigationIcon,
    matching: find.byType(
      ElevatedButton,
      skipOffstage: false,
    ),
  );

  expect(
    buttonFinder,
    findsOneWidget,
  );

  return tester.widget<ElevatedButton>(
    buttonFinder,
  );
}


      // Open the actual Indoor Map screen.
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: IndoorMapScreen(
            httpClient: mockClient,
          ),
        ),
      );

      await finishRequests();

      // Verify initial API connection.
      expect(
        find.text(
          'API CONNECTED',
          skipOffstage: false,
        ),
        findsOneWidget,
      );

      // Select a free destination.
      final cells = find.descendant(
        of: find.byType(GridView),
        matching: find.byType(GestureDetector),
      );

      // Cell (2,10) = 2 * 15 + 10.
      await tester.tap(cells.at(40));
      await tester.pump();

      expect(
        find.text(
          'Destination: (2, 10)',
          skipOffstage: false,
        ),
        findsOneWidget,
      );

      // The START button should be enabled.
      expect(
        getStartButton().onPressed,
        isNotNull,
      );

      // Simulate API disconnection.
      apiOnline = false;

      await tester.tap(
        find.byTooltip('Refresh Map'),
      );

      await finishRequests();

      // Verify disconnection warning.
      expect(
        find.text(
          'API DISCONNECTED',
          skipOffstage: false,
        ),
        findsOneWidget,
      );

      // START must now be disabled.
      expect(
        getStartButton().onPressed,
        isNull,
      );

      // No navigation request was sent.
      expect(startCalls, 0);

      // Restore the mock API connection.
      apiOnline = true;

      await tester.tap(
        find.byTooltip('Refresh Map'),
      );

      await finishRequests();

      // Verify connection recovery.
      expect(
        find.text(
          'API CONNECTED',
          skipOffstage: false,
        ),
        findsOneWidget,
      );

      // START should become enabled again.
      expect(
        getStartButton().onPressed,
        isNotNull,
      );

      // The previously selected goal remains.
      expect(
        find.text(
          'Destination: (2, 10)',
          skipOffstage: false,
        ),
        findsOneWidget,
      );

      // No unintended START request occurred.
      expect(startCalls, 0);
    },
  );
}
