
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:autonav_rc/screens/indoor_map_screen.dart';

void main() {
  group('AutoNav RC Navigation Widget Tests', () {
    late MockClient mockClient;

    bool apiOnline = true;
    String robotState = 'IDLE';

    int planCalls = 0;
    int startCalls = 0;
    int stopCalls = 0;

    final path = List.generate(
      9,
      (i) => {'row': 2, 'col': i + 2},
    );

    setUp(() {
      apiOnline = true;
      robotState = 'IDLE';

      planCalls = 0;
      startCalls = 0;
      stopCalls = 0;

      mockClient = MockClient((request) async {
        if (!apiOnline) {
          throw Exception('API connection lost');
        }

        final endpoint = request.url.path;

        if (endpoint == '/api/v1/maps/current') {
          final grid = List.generate(
            15,
            (_) => List.filled(15, 0),
          );

          for (int r = 4; r <= 10; r++) {
            grid[r][6] = 1;
          }

          return http.Response(
            jsonEncode({
              'success': true,
              'map_name': 'Mock Navigation Map',
              'width': 15,
              'height': 15,
              'resolution': 0.1,
              'grid': grid,
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
              'navigation_state': robotState,
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
          planCalls++;

          final body = jsonDecode(request.body);

          expect(body['goal']['row'], 2);
          expect(body['goal']['col'], 10);

          return http.Response(
            jsonEncode({
              'success': true,
              'navigation_state': 'READY',
              'path': path,
              'steps': 8,
            }),
            200,
          );
        }

        if (endpoint == '/api/v1/navigation/start') {
          startCalls++;
          robotState = 'NAVIGATING';

          return http.Response(
            jsonEncode({
              'success': true,
              'navigation_state': robotState,
            }),
            200,
          );
        }

        if (endpoint == '/api/v1/navigation/stop') {
          stopCalls++;
          robotState = 'STOPPED';

          return http.Response(
            jsonEncode({
              'success': true,
              'navigation_state': robotState,
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
    });

    tearDown(() {
      mockClient.close();
    });

    Future<void> finishHttp(
      WidgetTester tester,
    ) async {
      await tester.runAsync(() async {
        await Future<void>.delayed(
          const Duration(milliseconds: 30),
        );
      });

      await tester.pump();
    }

    Future<void> openMap(
      WidgetTester tester,
    ) async {
      tester.view.physicalSize =
          const Size(1080, 2400);

      tester.view.devicePixelRatio = 3;

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(
        tester.view.resetDevicePixelRatio,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: IndoorMapScreen(
            httpClient: mockClient,
          ),
        ),
      );

      await finishHttp(tester);
    }

    Future<void> chooseDestination(
      WidgetTester tester,
    ) async {
      // Cell (2,10) has index 2 * 15 + 10 = 40.
      final cells = find.descendant(
        of: find.byType(GridView),
        matching: find.byType(GestureDetector),
      );

      await tester.tap(cells.at(40));
      await tester.pump();
    }

    Future<void> startRobot(
      WidgetTester tester,
    ) async {
      final startButton = find.text(
        'Start Navigation',
        skipOffstage: false,
      );

      await tester.ensureVisible(startButton);
      await tester.pump();

      await tester.tap(startButton);

      await finishHttp(tester);
    }

    testWidgets(
      'Selecting a destination updates the screen',
      (tester) async {
        await openMap(tester);
        await chooseDestination(tester);

        expect(
          find.text(
            'Destination: (2, 10)',
            skipOffstage: false,
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Start requests A* path and displays orange route',
      (tester) async {
        await openMap(tester);
        await chooseDestination(tester);
        await startRobot(tester);

        expect(planCalls, 1);
        expect(startCalls, 1);

        expect(
          find.text(
            'A* path positions: 9',
            skipOffstage: false,
          ),
          findsOneWidget,
        );

        // Verify that at least one grid cell
        // is actually painted orange.
        final gridContainers = tester.widgetList<Container>(
          find.descendant(
            of: find.byType(GridView),
            matching: find.byType(Container),
          ),
        );

        final orangeCellExists = gridContainers.any(
          (container) {
            final decoration = container.decoration;

            return decoration is BoxDecoration &&
                decoration.color ==
                    const Color(0xFFF59E0B);
          },
        );

        expect(orangeCellExists, isTrue);
      },
    );

    testWidgets(
      'STOP sends request and clears displayed route',
      (tester) async {
        await openMap(tester);
        await chooseDestination(tester);
        await startRobot(tester);

        final stopButton = find.text(
          'STOP SIMULATED ROBOT',
          skipOffstage: false,
        );

        await tester.ensureVisible(stopButton);
        await tester.pump();

        await tester.tap(stopButton);
        await finishHttp(tester);

        expect(stopCalls, 1);

        expect(
          find.text(
            'Navigation status: STOPPED',
            skipOffstage: false,
          ),
          findsOneWidget,
        );

        expect(
          find.text(
            'A* path positions: 0',
            skipOffstage: false,
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Connection error and recovery are displayed',
      (tester) async {
        apiOnline = false;

        await openMap(tester);

        expect(
          find.textContaining(
            'Connection error:',
            skipOffstage: false,
          ),
          findsOneWidget,
        );

        // Restore the mock API.
        apiOnline = true;

        final retryButton = find.text(
          'Retry',
          skipOffstage: false,
        );

        await tester.ensureVisible(retryButton);
        await tester.pump();

        await tester.tap(retryButton);
        await finishHttp(tester);

        expect(
          find.text('Mock Navigation Map'),
          findsOneWidget,
        );

        expect(
          find.textContaining(
            'Connection error:',
          ),
          findsNothing,
        );
      },
    );
  });
}
