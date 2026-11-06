import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:autonav_rc/screens/saved_map_navigation_screen.dart';

void main() {
  group('Saved Map Simulation Tests', () {
    late MockClient client;

    final requests = <http.Request>[];

    String simulationState = 'IDLE';

    Map<String, dynamic> mapResponse() {
      return {
        'success': true,
        'width': 7,
        'height': 7,
        'resolution': 0.1,
        'grid': List.generate(7, (_) => List.filled(7, 0)),
        'robot_position': {'row': 2, 'col': 2},
        'exploration_percentage': 100.0,
      };
    }

    Map<String, dynamic> simulationResponse() {
      return {
        'success': true,
        'simulation': true,
        'physical_motors_active': false,
        'navigation_state': simulationState,
        'position': {'row': 2, 'col': 2},
        'goal': simulationState == 'STOPPED' ? null : {'row': 2, 'col': 4},
        'path': simulationState == 'NAVIGATING'
            ? [
                {'row': 2, 'col': 2},
                {'row': 2, 'col': 3},
                {'row': 2, 'col': 4},
              ]
            : [],
        'current_step': 0,
        'total_steps': 2,
        'remaining_steps': simulationState == 'NAVIGATING' ? 2 : 0,
      };
    }

    setUp(() {
      requests.clear();
      simulationState = 'IDLE';

      client = MockClient((request) async {
        requests.add(request);
        final path = request.url.path;

        if (path.endsWith('/teach/map')) {
          return http.Response(jsonEncode(mapResponse()), 200);
        }

        if (path.endsWith('/teach/navigation/plan')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'map_source': 'saved_teach_mode',
              'execution_started': false,
              'path': [
                {'row': 2, 'col': 2},
                {'row': 2, 'col': 3},
                {'row': 2, 'col': 4},
              ],
            }),
            200,
          );
        }

        if (path.endsWith('/teach/navigation/sim/start')) {
          simulationState = 'NAVIGATING';

          return http.Response(jsonEncode(simulationResponse()), 200);
        }

        if (path.endsWith('/teach/navigation/sim/stop')) {
          simulationState = 'STOPPED';

          return http.Response(jsonEncode(simulationResponse()), 200);
        }

        if (path.endsWith('/teach/navigation/sim/status')) {
          return http.Response(jsonEncode(simulationResponse()), 200);
        }

        return http.Response(jsonEncode({'detail': 'Unknown endpoint'}), 404);
      });
    });

    tearDown(() {
      client.close();
    });

    Future<void> openScreen(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 3;

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: SavedMapNavigationScreen(httpClient: client),
        ),
      );

      await tester.pumpAndSettle();
    }

    Future<void> tapText(WidgetTester tester, String label) async {
      final finder = find.text(label);

      expect(finder, findsOneWidget);

      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();

      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    testWidgets('Shows simulator controls', (tester) async {
      await openScreen(tester);

      expect(find.text('START SIMULATION'), findsOneWidget);

      expect(find.text('STOP SIMULATION'), findsOneWidget);

      expect(find.text('Navigation state: IDLE'), findsOneWidget);
    });

    testWidgets('Starts virtual navigation after route planning', (
      tester,
    ) async {
      await openScreen(tester);

      await tester.tap(find.byKey(const Key('saved_cell_2_4')));

      await tester.pumpAndSettle();

      await tapText(tester, 'PLAN SAFE ROUTE');

      await tapText(tester, 'START SIMULATION');

      expect(find.text('Navigation state: NAVIGATING'), findsOneWidget);

      expect(find.text('Virtual robot is moving'), findsOneWidget);

      final starts = requests.where(
        (request) => request.url.path.endsWith('/teach/navigation/sim/start'),
      );

      expect(starts.length, 1);

      final body = jsonDecode(starts.first.body) as Map<String, dynamic>;

      expect(body['goal'], {'row': 2, 'col': 4});
    });

    testWidgets('STOP changes simulator state', (tester) async {
      await openScreen(tester);

      await tapText(tester, 'STOP SIMULATION');

      expect(find.text('Navigation state: STOPPED'), findsOneWidget);

      expect(find.text('Virtual robot stopped'), findsOneWidget);

      final stops = requests.where(
        (request) => request.url.path.endsWith('/teach/navigation/sim/stop'),
      );

      expect(stops.length, 1);
    });
  });
}
