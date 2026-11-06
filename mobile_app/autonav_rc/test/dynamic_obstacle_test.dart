import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:autonav_rc/screens/dynamic_obstacle_screen.dart';

void main() {
  group('Dynamic Obstacle Screen', () {
    late MockClient client;
    late List<Map<String, dynamic>> updates;

    final obstacles = <Map<String, int>>[];

    Map<String, dynamic> status() {
      return {
        'success': true,
        'simulation': true,
        'physical_motors_active': false,
        'navigation_state': 'NAVIGATING',
        'position': {'row': 1, 'col': 1},
        'goal': {'row': 3, 'col': 3},
        'path': [
          {'row': 1, 'col': 1},
          {'row': 2, 'col': 2},
          {'row': 3, 'col': 3},
        ],
        'replan_count': obstacles.isEmpty ? 0 : 1,
        'dynamic_obstacles': obstacles,
      };
    }

    setUp(() {
      updates = [];
      obstacles.clear();

      client = MockClient((request) async {
        if (request.url.path.endsWith('/teach/map')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'width': 5,
              'height': 5,
              'grid': [
                [0, 0, 0, 0, 0],
                [0, 0, 0, 0, 0],
                [0, 0, 0, 0, 0],
                [0, 0, 0, 0, 0],
                [0, 0, 0, 0, -1],
              ],
            }),
            200,
          );
        }

        if (request.url.path.endsWith('/teach/navigation/sim/status')) {
          return http.Response(jsonEncode(status()), 200);
        }

        if (request.url.path.endsWith('/teach/navigation/sim/obstacle')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;

          updates.add(body);

          final obstacle = {
            'row': body['row'] as int,
            'col': body['col'] as int,
          };

          if (body['occupied'] == true) {
            if (!obstacles.any(
              (item) =>
                  item['row'] == obstacle['row'] &&
                  item['col'] == obstacle['col'],
            )) {
              obstacles.add(obstacle);
            }
          } else {
            obstacles.removeWhere(
              (item) =>
                  item['row'] == obstacle['row'] &&
                  item['col'] == obstacle['col'],
            );
          }

          return http.Response(
            jsonEncode({
              ...status(),
              'replanned': body['occupied'] == true,
              'obstacle_changed': true,
            }),
            200,
          );
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
          home: DynamicObstacleScreen(httpClient: client),
        ),
      );

      await tester.pump();
      await tester.pump();
      await tester.pump();
    }

    testWidgets('Loads obstacle map', (tester) async {
      await openScreen(tester);

      expect(find.text('Navigation state: NAVIGATING'), findsOneWidget);

      expect(find.byKey(const Key('obstacle_cell_1_1')), findsOneWidget);

      expect(find.text('Dynamic obstacles: 0'), findsOneWidget);
    });

    testWidgets('Adds and removes obstacle', (tester) async {
      await openScreen(tester);

      await tester.tap(find.byKey(const Key('obstacle_cell_2_3')));
      await tester.pump();

      await tester.tap(find.text('ADD OBSTACLE'));

      await tester.pump();
      await tester.pump();

      expect(updates.length, 1);
      expect(updates.first['row'], 2);
      expect(updates.first['col'], 3);
      expect(updates.first['occupied'], true);

      expect(find.text('Dynamic obstacles: 1'), findsOneWidget);

      await tester.tap(find.text('REMOVE OBSTACLE'));
      await tester.pump();
      await tester.pump();

      expect(updates.length, 2);
      expect(updates.last['occupied'], false);

      expect(find.text('Dynamic obstacles: 0'), findsOneWidget);
    });

    testWidgets('Unknown cells cannot be edited', (tester) async {
      await openScreen(tester);

      await tester.tap(find.byKey(const Key('obstacle_cell_4_4')));
      await tester.pump();

      expect(find.text('Only saved free cells can be edited'), findsOneWidget);

      expect(updates, isEmpty);
    });
  });
}
