
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:autonav_rc/screens/indoor_map_screen.dart';

void main() {
  testWidgets(
    'Changing destination replaces old A* route',
    (tester) async {
      final requestedGoals = <(int, int)>[];

      String navigationState = 'IDLE';

      final mockClient = MockClient((request) async {
        final endpoint = request.url.path;

        if (endpoint == '/api/v1/maps/current') {
          return http.Response(
            jsonEncode({
              'success': true,
              'map_name': 'Destination Update Map',
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
              'navigation_state': navigationState,
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
          final body = jsonDecode(request.body);
          final goal = body['goal'];

          final row = goal['row'] as int;
          final col = goal['col'] as int;

          requestedGoals.add((row, col));

          final path = <Map<String, int>>[
            {'row': 2, 'col': 2},
          ];

          // Build a route from (2,2) to the goal.
          for (int r = 3; r <= row; r++) {
            path.add({'row': r, 'col': 2});
          }

          for (int c = 3; c <= col; c++) {
            path.add({'row': row, 'col': c});
          }

          return http.Response(
            jsonEncode({
              'success': true,
              'navigation_state': 'READY',
              'path': path,
              'steps': path.length - 1,
            }),
            200,
          );
        }

        if (endpoint == '/api/v1/navigation/start') {
          navigationState = 'NAVIGATING';

          return http.Response(
            jsonEncode({
              'success': true,
              'navigation_state': navigationState,
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

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: IndoorMapScreen(
            httpClient: mockClient,
          ),
        ),
      );

      Future<void> finishRequests() async {
        await tester.runAsync(() async {
          await Future<void>.delayed(
            const Duration(milliseconds: 30),
          );
        });

        await tester.pump();
      }

      Future<void> selectCell(int row, int col) async {
        final cells = find.descendant(
          of: find.byType(GridView),
          matching: find.byType(GestureDetector),
        );

        await tester.tap(cells.at(row * 15 + col));
        await tester.pump();
      }

      Future<void> pressNavigationButton() async {
        final button = find.text(
          navigationState == 'NAVIGATING'
              ? 'Update Destination'
              : 'Start Navigation',
          skipOffstage: false,
        );

        await tester.ensureVisible(button);
        await tester.pump();

        await tester.tap(button);
        await finishRequests();
      }

      await finishRequests();

      // First destination: (2,10).
      await selectCell(2, 10);
      await pressNavigationButton();

      expect(requestedGoals, [(2, 10)]);

      expect(
        find.text(
          'A* path positions: 9',
          skipOffstage: false,
        ),
        findsOneWidget,
      );

      // Select a different destination.
      await selectCell(3, 10);

      // The previous route must disappear immediately.
      expect(
        find.text(
          'A* path positions: 0',
          skipOffstage: false,
        ),
        findsOneWidget,
      );

      // Start navigation toward the new destination.
      await pressNavigationButton();

      expect(
        requestedGoals,
        [(2, 10), (3, 10)],
      );

      expect(
        find.text(
          'Destination: (3, 10)',
          skipOffstage: false,
        ),
        findsOneWidget,
      );

      expect(
        find.text(
          'A* path positions: 10',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
    },
  );
}
