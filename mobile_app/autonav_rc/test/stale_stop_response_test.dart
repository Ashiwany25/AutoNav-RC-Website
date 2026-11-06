
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:autonav_rc/screens/indoor_map_screen.dart';

void main() {
  testWidgets(
    'Old NAVIGATING response cannot overwrite STOP',
    (tester) async {
      int statusCalls = 0;
      int stopCalls = 0;

      final delayedStatus = Completer<http.Response>();

      String backendState = 'IDLE';

      http.Response statusResponse(String state) {
        return http.Response(
          jsonEncode({
            'success': true,
            'navigation_state': state,
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

      final mockClient = MockClient((request) async {
        final endpoint = request.url.path;

        if (endpoint == '/api/v1/maps/current') {
          return http.Response(
            jsonEncode({
              'success': true,
              'map_name': 'STOP Safety Test Map',
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

          if (statusCalls == 1) {
            return statusResponse('IDLE');
          }

          // Second response is deliberately delayed.
          if (statusCalls == 2) {
            return delayedStatus.future;
          }

          return statusResponse(backendState);
        }

        if (endpoint == '/api/v1/navigation/stop') {
          stopCalls++;

          backendState = 'STOPPED';

          return http.Response(
            jsonEncode({
              'success': true,
              'navigation_state': 'STOPPED',
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

      Future<void> finishRequests() async {
        await tester.runAsync(() async {
          await Future<void>.delayed(
            const Duration(milliseconds: 30),
          );
        });

        await tester.pump();
      }

      // Open the actual Indoor Map widget.
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: IndoorMapScreen(
            httpClient: mockClient,
          ),
        ),
      );

      await finishRequests();

      // Initially the robot is IDLE.
      expect(
        find.text(
          'Navigation status: IDLE',
          skipOffstage: false,
        ),
        findsOneWidget,
      );

      expect(statusCalls, 1);

      // Trigger another status refresh.
      await tester.tap(
        find.byTooltip('Refresh Map'),
      );

      await tester.pump();

      await finishRequests();

      // The old response is still pending.
      expect(statusCalls, 2);

      expect(
        delayedStatus.isCompleted,
        isFalse,
      );

      // Press STOP while the earlier
      // status response is still pending.
      final stopButton = find.text(
        'STOP SIMULATED ROBOT',
        skipOffstage: false,
      );

      await tester.ensureVisible(stopButton);
      await tester.pump();

      await tester.tap(stopButton);

      await finishRequests();

      // The STOP request must have been sent.
      expect(stopCalls, 1);

      expect(
        backendState,
        'STOPPED',
      );

      // The UI must now display STOPPED.
      expect(
        find.text(
          'Navigation status: STOPPED',
          skipOffstage: false,
        ),
        findsOneWidget,
      );

      // Release the older status response.
      // It incorrectly reports NAVIGATING.
      delayedStatus.complete(
        statusResponse('NAVIGATING'),
      );

      await finishRequests();

      // Critical synchronization check:
      // The old response must be ignored.
      expect(
        find.text(
          'Navigation status: STOPPED',
          skipOffstage: false,
        ),
        findsOneWidget,
      );

      expect(
        find.text(
          'Navigation status: NAVIGATING',
          skipOffstage: false,
        ),
        findsNothing,
      );

      // No old route should be displayed.
      expect(
        find.text(
          'A* path positions: 0',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
    },
  );
}
