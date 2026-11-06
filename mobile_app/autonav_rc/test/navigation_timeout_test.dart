
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:autonav_rc/screens/indoor_map_screen.dart';

void main() {
  testWidgets(
    'Interrupted route planning never sends START',
    (tester) async {
      int planCalls = 0;
      int startCalls = 0;

      final mockClient = MockClient((request) async {
        final endpoint = request.url.path;

        if (endpoint == '/api/v1/maps/current') {
          return http.Response(
            jsonEncode({
              'success': true,
              'map_name': 'Timeout Test Map',
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

        if (endpoint == '/api/v1/navigation/plan') {
          planCalls++;

          // Simulate a network interruption.
          throw TimeoutException(
            'Route planning request timed out',
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

      await finishRequests();

      // Choose destination (2,10).
      final cells = find.descendant(
        of: find.byType(GridView),
        matching: find.byType(GestureDetector),
      );

      await tester.tap(cells.at(40));
      await tester.pump();

      // Request navigation.
      final startButton = find.text(
        'Start Navigation',
        skipOffstage: false,
      );

      await tester.ensureVisible(startButton);
      await tester.pump();

      await tester.tap(startButton);
      await finishRequests();

      // Planning request was attempted.
      expect(planCalls, 1);

      // Critical: no START after planning interruption.
      expect(startCalls, 0);

      // No route should remain displayed.
      expect(
        find.text(
          'A* path positions: 0',
          skipOffstage: false,
        ),
        findsOneWidget,
      );

      // UI must not claim successful navigation.
      expect(
        find.text(
          'Navigation status: IDLE',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
    },
  );
}
