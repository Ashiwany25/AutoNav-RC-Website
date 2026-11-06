import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:autonav_rc/screens/saved_map_navigation_screen.dart';

void main() {
  group('Saved Map Navigation Tests', () {
    late MockClient client;

    final requests = <http.Request>[];

    setUp(() {
      requests.clear();

      client = MockClient((request) async {
        requests.add(request);

        final path = request.url.path;

        if (path.endsWith('/teach/map')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'width': 5,
              'height': 5,
              'resolution': 0.1,
              'grid': [
                [0, 0, 0, 0, 0],
                [0, 0, 0, 0, 0],
                [0, 0, 0, 0, 0],
                [0, 0, 0, 0, 0],
                [0, 0, 0, 0, -1],
              ],
              'robot_position': {'row': 1, 'col': 1},
              'exploration_percentage': 96.0,
              'observation_count': 24,
            }),
            200,
          );
        }

        if (path.endsWith('/teach/navigation/plan')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;

          final goal = body['goal'] as Map<String, dynamic>;

          if (goal['row'] == 4 && goal['col'] == 4) {
            return http.Response(
              jsonEncode({'detail': 'Destination is unknown'}),
              400,
            );
          }

          return http.Response(
            jsonEncode({
              'success': true,
              'simulation': true,
              'map_source': 'saved_teach_mode',
              'execution_started': false,
              'clearance_cells': 1,
              'path': [
                {'row': 1, 'col': 1},
                {'row': 1, 'col': 2},
                {'row': 1, 'col': 3},
                {'row': 2, 'col': 3},
              ],
              'steps': 3,
            }),
            200,
          );
        }

        return http.Response(
          jsonEncode({'detail': 'Unknown API endpoint'}),
          404,
        );
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

    testWidgets('Loads saved occupancy map', (tester) async {
      await openScreen(tester);

      expect(find.text('API CONNECTED'), findsOneWidget);

      expect(find.text('Exploration: 96.0%'), findsOneWidget);

      expect(find.byKey(const Key('saved_cell_1_1')), findsOneWidget);

      expect(find.text('PLAN SAFE ROUTE'), findsOneWidget);
    });

    testWidgets('Plans route to tapped free cell', (tester) async {
      await openScreen(tester);

      await tester.tap(find.byKey(const Key('saved_cell_2_3')));

      await tester.pumpAndSettle();

      expect(find.text('Selected destination: (2, 3)'), findsOneWidget);

      await tester.tap(find.text('PLAN SAFE ROUTE'));

      await tester.pumpAndSettle();

      expect(find.text('Safe A* route found: 3 steps'), findsOneWidget);

      final planRequests = requests.where(
        (request) => request.url.path.endsWith('/teach/navigation/plan'),
      );

      expect(planRequests.length, 1);

      final body = jsonDecode(planRequests.first.body) as Map<String, dynamic>;

      expect(body['goal'], {'row': 2, 'col': 3});
    });

    testWidgets('Unknown destination is rejected locally', (tester) async {
      await openScreen(tester);

      await tester.tap(find.byKey(const Key('saved_cell_4_4')));

      await tester.pumpAndSettle();

      expect(
        find.textContaining('Unknown cells and obstacles'),
        findsOneWidget,
      );

      final planRequests = requests.where(
        (request) => request.url.path.endsWith('/teach/navigation/plan'),
      );

      expect(planRequests, isEmpty);
    });
  });
}
