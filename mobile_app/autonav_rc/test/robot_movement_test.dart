
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:autonav_rc/screens/indoor_map_screen.dart';

void main() {
  testWidgets(
    'Robot position updates when backend position changes',
    (tester) async {
      int robotCol = 2;

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/maps/current') {
          return http.Response(
            jsonEncode({
              'success': true,
              'map_name': 'Movement Test Map',
              'width': 15,
              'height': 15,
              'resolution': 0.1,
              'grid': List.generate(
                15,
                (_) => List.filled(15, 0),
              ),
              'robot_position': {
                'row': 2,
                'col': robotCol,
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
              'navigation_state': 'NAVIGATING',
              'position': {
                'row': 2,
                'col': robotCol,
              },
              'current_step': robotCol - 2,
              'total_steps': 8,
              'remaining_steps': 10 - robotCol,
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

      tester.view.physicalSize = const Size(1080, 2400);
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

      // Complete the initial mocked requests.
      await tester.runAsync(() async {
        await Future<void>.delayed(
          const Duration(milliseconds: 30),
        );
      });

      await tester.pump();

      expect(
        find.text('Robot: (2, 2)'),
        findsOneWidget,
      );

      // Simulate movement in the backend.
      robotCol = 5;

      // Advance the screen's one-second polling timer.
      await tester.pump(
        const Duration(seconds: 1),
      );

      await tester.runAsync(() async {
        await Future<void>.delayed(
          const Duration(milliseconds: 30),
        );
      });

      await tester.pump();

      expect(
        find.text('Robot: (2, 5)'),
        findsOneWidget,
      );

      expect(
        find.text('Progress: 3 / 8 steps'),
        findsOneWidget,
      );
    },
  );
}
