
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:autonav_rc/screens/indoor_map_screen.dart';

void main() {
  testWidgets(
    'Delayed navigation status response updates robot position',
    (tester) async {
      int statusCalls = 0;

      // Control the second API response manually.
      final delayedResponse = Completer<http.Response>();

      final client = MockClient((request) async {
        final endpoint = request.url.path;

        if (endpoint == '/api/v1/maps/current') {
          return http.Response(
            jsonEncode({
              'success': true,
              'map_name': 'Delayed Response Map',
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
          statusCalls++;

          // First request: robot at (2,2).
          if (statusCalls == 1) {
            return http.Response(
              jsonEncode({
                'success': true,
                'navigation_state': 'NAVIGATING',
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

          // Second request: do not respond until
          // the test explicitly releases it.
          if (statusCalls == 2) {
            return delayedResponse.future;
          }

          return http.Response(
            jsonEncode({
              'success': true,
              'navigation_state': 'NAVIGATING',
              'position': {
                'row': 2,
                'col': 5,
              },
              'current_step': 3,
              'total_steps': 8,
              'remaining_steps': 5,
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

      addTearDown(client.close);

      tester.view.physicalSize =
          const Size(1080, 2400);

      tester.view.devicePixelRatio = 3;

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: IndoorMapScreen(
            httpClient: client,
          ),
        ),
      );

      // Complete initial HTTP requests.
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

      expect(statusCalls, 1);

      // Trigger an explicit refresh instead of
      // depending on the polling timer.
      await tester.tap(
        find.byTooltip('Refresh Map'),
      );

      await tester.pump();

      // Let the second request reach MockClient.
      await tester.runAsync(() async {
        await Future<void>.delayed(
          const Duration(milliseconds: 30),
        );
      });

      expect(statusCalls, 2);

      // The second response is still pending.
      // Robot must remain at the old position.
      expect(
        find.text('Robot: (2, 2)'),
        findsOneWidget,
      );

      // Now release the delayed API response.
      delayedResponse.complete(
        http.Response(
          jsonEncode({
            'success': true,
            'navigation_state': 'NAVIGATING',
            'position': {
              'row': 2,
              'col': 5,
            },
            'current_step': 3,
            'total_steps': 8,
            'remaining_steps': 5,
          }),
          200,
        ),
      );

      // Allow the completed HTTP request to
      // propagate through the client and widget.
      await tester.runAsync(() async {
        await Future<void>.delayed(
          const Duration(milliseconds: 30),
        );
      });

      await tester.pump();

      // Verify updated position.
      expect(
        find.text('Robot: (2, 5)'),
        findsOneWidget,
      );

      // Verify navigation progress.
      expect(
        find.text('Progress: 3 / 8 steps'),
        findsOneWidget,
      );
    },
  );
}
