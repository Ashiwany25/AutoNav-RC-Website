import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:autonav_rc/screens/teach_mode_screen.dart';

void main() {
  group('Teach Mode Tests', () {
    late MockClient client;
    late List<String> requests;
    late List<Map<String, dynamic>> moveRequests;

    bool mappingActive = false;
    bool explored = false;

    Map<String, dynamic> sampleMap() {
      return {
        'width': 3,
        'height': 3,
        'resolution': 0.1,
        'grid': explored
            ? [
                [0, 0, -1],
                [0, 0, 1],
                [-1, -1, -1],
              ]
            : [
                [-1, -1, -1],
                [-1, -1, -1],
                [-1, -1, -1],
              ],
        'robot_position': {'row': 1, 'col': 1},
        'exploration_percentage': explored ? 55.56 : 0.0,
        'observation_count': explored ? 5 : 0,
      };
    }

    setUp(() {
      requests = [];
      moveRequests = [];

      mappingActive = false;
      explored = false;

      client = MockClient((request) async {
        final path = request.url.path;

        requests.add(path);

        Map<String, dynamic> response;

        if (path.endsWith('/teach/status')) {
          response = {
            'success': true,
            'teach_active': mappingActive,
            'map_available': mappingActive || explored,
            'saved_map_available': explored && !mappingActive,
          };
        } else if (path.endsWith('/teach/start')) {
          mappingActive = true;
          explored = false;

          response = {
            'success': true,
            'teach_active': true,
            'map': sampleMap(),
          };
        } else if (path.endsWith('/teach/observe')) {
          explored = true;

          response = {
            'success': true,
            'teach_active': true,
            'observed_cells': 5,
            'new_cells': 5,
            'unique_explored_cells': 5,
            'map': sampleMap(),
          };
        } else if (path.endsWith('/teach/move')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;

          moveRequests.add(body);

          response = {
            'success': true,
            'simulation': true,
            'moved': true,
            'direction': body['direction'],
            'robot_position': {'row': 0, 'col': 1},
            'map': sampleMap(),
          };
        } else if (path.endsWith('/teach/finish')) {
          mappingActive = false;

          response = {'success': true, 'teach_active': false, 'saved': true};
        } else if (path.endsWith('/teach/map')) {
          response = {
            'success': true,
            'teach_active': mappingActive,
            ...sampleMap(),
          };
        } else {
          return http.Response(jsonEncode({'detail': 'Unknown endpoint'}), 404);
        }

        return http.Response(
          jsonEncode(response),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
    });

    tearDown(() {
      client.close();
    });

    Future<void> openScreen(WidgetTester tester) async {
      // Large viewport ensures that all Teach Mode
      // buttons exist and are visible during tests.
      tester.view.physicalSize = const Size(1200, 9000);

      tester.view.devicePixelRatio = 3;

      addTearDown(tester.view.resetPhysicalSize);

      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: TeachModeScreen(httpClient: client),
        ),
      );

      await tester.pumpAndSettle();
    }

    Future<void> tapButton(WidgetTester tester, String label) async {
      final button = find.text(label);

      expect(button, findsOneWidget);

      await tester.ensureVisible(button);
      await tester.pumpAndSettle();

      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('Loads status and shows start control', (tester) async {
      await openScreen(tester);

      expect(find.text('Teach Mode'), findsOneWidget);

      expect(find.text('API CONNECTED'), findsOneWidget);

      expect(find.text('START MAPPING'), findsOneWidget);

      expect(requests.any((path) => path.endsWith('/teach/status')), isTrue);
    });

    testWidgets('Start creates an unknown occupancy grid', (tester) async {
      await openScreen(tester);

      await tapButton(tester, 'START MAPPING');

      expect(find.text('Status: MAPPING'), findsOneWidget);

      expect(find.byKey(const Key('teach_cell_0_0')), findsOneWidget);

      expect(requests.any((path) => path.endsWith('/teach/start')), isTrue);
    });

    testWidgets('Scan records simulated observations', (tester) async {
      await openScreen(tester);

      await tapButton(tester, 'START MAPPING');

      await tapButton(tester, 'SCAN ENVIRONMENT');

      expect(requests.any((path) => path.endsWith('/teach/observe')), isTrue);

      expect(find.text('Total observations: 5'), findsOneWidget);

      expect(find.text('Unique explored cells: 5'), findsOneWidget);

      expect(find.text('Exploration: 55.6%'), findsOneWidget);

      expect(find.text('New cells in last scan: 5'), findsOneWidget);
    });

    testWidgets('Save finishes Teach Mode', (tester) async {
      await openScreen(tester);

      await tapButton(tester, 'START MAPPING');

      await tapButton(tester, 'SAVE MAP');

      expect(requests.any((path) => path.endsWith('/teach/finish')), isTrue);

      expect(requests.any((path) => path.endsWith('/teach/map')), isTrue);

      expect(find.text('Status: NOT MAPPING'), findsOneWidget);

      expect(find.text('Map saved successfully'), findsOneWidget);
    });

    testWidgets('Movement sends Teach Mode request', (tester) async {
      await openScreen(tester);

      await tapButton(tester, 'START MAPPING');

      final upButton = find.byIcon(Icons.keyboard_arrow_up);

      expect(upButton, findsOneWidget);

      await tester.ensureVisible(upButton);
      await tester.pumpAndSettle();

      await tester.tap(upButton);
      await tester.pumpAndSettle();

      expect(requests.any((path) => path.endsWith('/teach/move')), isTrue);

      expect(moveRequests.length, 1);

      expect(moveRequests.first['direction'], 'UP');

      expect(moveRequests.first['steps'], 1);

      expect(find.text('Moved UP'), findsOneWidget);
    });
  });
}
