
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:autonav_rc/screens/indoor_map_screen.dart';

void main() {
  group('Indoor Map Mock Widget Tests', () {
    late MockClient mockClient;

    setUp(() {
      mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/maps/current') {
          final grid = List.generate(
            15,
            (_) => List.filled(15, 0),
          );

          for (int row = 4; row <= 10; row++) {
            grid[row][6] = 1;
          }

          return http.Response(
            jsonEncode({
              'success': true,
              'simulation': true,
              'map_name': 'Mock Indoor Map',
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

        if (request.url.path ==
            '/api/v1/navigation/status') {
          return http.Response(
            jsonEncode({
              'success': true,
              'simulation': true,
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

    Future<void> openMap(
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(
        const Size(1080, 2400),
      );
      tester.view.devicePixelRatio = 3;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: IndoorMapScreen(
            httpClient: mockClient,
          ),
        ),
      );

      // Allow mocked HTTP futures to finish.
      await tester.runAsync(() async {
        await Future<void>.delayed(
          const Duration(milliseconds: 50),
        );
      });

      await tester.pump();
    }

    testWidgets(
      'Displays map received from the API',
      (tester) async {
        await openMap(tester);

        expect(
          find.text('Mock Indoor Map'),
          findsOneWidget,
        );

        expect(
          find.text('Robot: (2, 2)'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Displays navigation state',
      (tester) async {
        await openMap(tester);

        expect(
          find.text('Navigation status: IDLE'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Shows the A* route legend',
      (tester) async {
        await openMap(tester);

        expect(
          find.text('A* Path', skipOffstage: false),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Initially has no planned route',
      (tester) async {
        await openMap(tester);

        expect(
          find.text(
            'A* path positions: 0',
            skipOffstage: false,
          ),
          findsOneWidget,
        );
      },
    );
  });
}
