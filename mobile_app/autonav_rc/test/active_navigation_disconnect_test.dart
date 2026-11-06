
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:autonav_rc/screens/indoor_map_screen.dart';

void main() {
  testWidgets(
    'Connection loss during navigation clears stale route',
    (tester) async {
      bool apiOnline = true;
      String backendState = 'IDLE';
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
              'map_name': 'Disconnect Test Map',
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
              'navigation_state': backendState,
              'position': {
                'row': 2,
                'col': 2,
              },
              'current_step': 0,
              'total_steps': 8,
              'remaining_steps': 8,
            }),
            200,
          );
        }

        if (endpoint == '/api/v1/navigation/plan') {
          return http.Response(
            jsonEncode({
              'success': true,
              'navigation_state': 'READY',
              'path': List.generate(
                9,
                (i) => {
                  'row': 2,
                  'col': i + 2,
                },
              ),
              'steps': 8,
            }),
            200,
          );
        }

        if (endpoint == '/api/v1/navigation/start') {
          startCalls++;
          backendState = 'NAVIGATING';

          return http.Response(
            jsonEncode({
              'success': true,
              'navigation_state': backendState,
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

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: IndoorMapScreen(
            httpClient: mockClient,
          ),
        ),
      );

      await finishRequests();

      // Confirm initial map is available.
      expect(
        find.text('Disconnect Test Map'),
        findsOneWidget,
      );

      // Select destination (2,10).
      final cells = find.descendant(
        of: find.byType(GridView),
        matching: find.byType(GestureDetector),
      );

      await tester.tap(cells.at(40));
      await tester.pump();

      // Start simulated navigation.
      final startButton = find.text(
        'Start Navigation',
        skipOffstage: false,
      );

      await tester.ensureVisible(startButton);
      await tester.pump();

      await tester.tap(startButton);
      await finishRequests();

      expect(startCalls, 1);

      expect(
        find.text(
          'Navigation status: NAVIGATING',
          skipOffstage: false,
        ),
        findsOneWidget,
      );

      expect(
        find.text(
          'A* path positions: 9',
          skipOffstage: false,
        ),
        findsOneWidget,
      );

      // Simulate losing the API connection.
      apiOnline = false;

      // Manually request a refresh.
      await tester.tap(
        find.byTooltip('Refresh Map'),
      );

      await finishRequests();

      // The application should show an error.
      expect(
        find.textContaining(
          'Connection error:',
          skipOffstage: false,
        ),
        findsOneWidget,
      );

      // An old route must no longer be shown
      // as an active navigation path.
      expect(
        find.text(
          'A* path positions: 0',
          skipOffstage: false,
        ),
        findsOneWidget,
      );

      // No extra START request should occur.
      expect(startCalls, 1);
    },
  );
}
