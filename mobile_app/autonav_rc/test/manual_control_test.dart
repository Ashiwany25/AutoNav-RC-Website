
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:autonav_rc/screens/manual_control_screen.dart';
import 'package:autonav_rc/services/manual_control_api.dart';

void main() {
  group('Manual Control Widget Tests', () {
    late MockClient mockClient;
    late ManualControlApi api;
    late List<String> commands;

    const sessionId = 'test-session-123';

    setUp(() {
      commands = [];

      mockClient = MockClient((request) async {
        final path = request.url.path;

        if (path.endsWith('/manual/session')) {
          commands.add('SESSION');

          return http.Response(
            jsonEncode({
              'success': true,
              'simulation': true,
              'session_id': sessionId,
              'next_sequence': 1,
              'mode': 'STOPPED',
            }),
            200,
          );
        }

        if (path.endsWith('/manual/drive')) {
          final body =
              jsonDecode(request.body) as Map<String, dynamic>;

          expect(body['session_id'], sessionId);
          expect(body['sequence'], isA<int>());

          final direction = body['direction'] as String;

          commands.add(direction);

          return http.Response(
            jsonEncode({
              'success': true,
              'simulation': true,
              'mode': 'MANUAL',
              'direction': direction,
              'speed': body['speed'],
            }),
            200,
          );
        }

        if (path.endsWith('/manual/stop')) {
          commands.add('STOP');

          return http.Response(
            jsonEncode({
              'success': true,
              'simulation': true,
              'mode': 'STOPPED',
              'direction': 'STOPPED',
              'speed': 0,
            }),
            200,
          );
        }

        return http.Response(
          jsonEncode({
            'success': false,
            'detail': 'Unknown endpoint',
          }),
          404,
        );
      });

      api = ManualControlApi(client: mockClient);
    });

    tearDown(() {
      mockClient.close();
    });

    // Wait until the mocked HTTP server
    // actually receives a command.
    Future<void> waitForCommand(
      WidgetTester tester,
      String expected,
    ) async {
      for (int attempt = 0; attempt < 30; attempt++) {
        if (commands.contains(expected)) {
          return;
        }

        await tester.runAsync(() async {
          await Future<void>.delayed(
            const Duration(milliseconds: 10),
          );
        });

        await tester.pump();
      }

      fail(
        'Expected $expected but received $commands',
      );
    }

    // Use a tall test viewport so all controls,
    // including STOP, are built and visible.
    //
    // This changes the testing viewport only.
    // It does not modify the real Android UI.
    Future<void> openScreen(
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(
        1080,
        4200,
      );

      tester.view.devicePixelRatio = 3;

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: ManualControlScreen(
            apiClient: api,
          ),
        ),
      );

      await waitForCommand(tester, 'SESSION');

      for (int i = 0; i < 5; i++) {
        await tester.pump();
      }

      expect(
        find.text('API CONNECTED'),
        findsOneWidget,
      );
    }

    // TEST 1
    testWidgets(
      'Shows STOPPED when opened',
      (tester) async {
        await openScreen(tester);

        expect(
          find.text('STOPPED'),
          findsOneWidget,
        );

        expect(
          find.text('Speed: 40%'),
          findsOneWidget,
        );
      },
    );

    // TESTS 2-5
    for (final direction in <String, IconData>{
      'FORWARD': Icons.keyboard_arrow_up,
      'BACKWARD': Icons.keyboard_arrow_down,
      'LEFT': Icons.keyboard_arrow_left,
      'RIGHT': Icons.keyboard_arrow_right,
    }.entries) {
      testWidgets(
        '${direction.key} sends API command and stops on release',
        (tester) async {
          await openScreen(tester);

          final button = find.byIcon(
            direction.value,
          );

          expect(button, findsOneWidget);

          final gesture = await tester.startGesture(
            tester.getCenter(button),
          );

          await tester.pump(
            const Duration(milliseconds: 100),
          );

          expect(
            find.text(direction.key),
            findsOneWidget,
          );

          await waitForCommand(
            tester,
            direction.key,
          );

          await gesture.up();
          await tester.pump();

          expect(
            find.text('STOPPED'),
            findsOneWidget,
          );

          await waitForCommand(
            tester,
            'STOP',
          );

          expect(commands.last, 'STOP');
        },
      );
    }

    // TEST 6
    testWidgets(
      'STOP interrupts an active direction',
      (tester) async {
        await openScreen(tester);

        final forward = find.byIcon(
          Icons.keyboard_arrow_up,
        );

        final stopButton = find.text('STOP');

        expect(forward, findsOneWidget);
        expect(stopButton, findsOneWidget);

        // Start holding FORWARD.
        final forwardGesture = await tester.startGesture(
          tester.getCenter(forward),
          pointer: 1,
        );

        await tester.pump(
          const Duration(milliseconds: 100),
        );

        expect(
          find.text('FORWARD'),
          findsOneWidget,
        );

        await waitForCommand(
          tester,
          'FORWARD',
        );

        // Send STOP with a second simulated finger.
        // The original FORWARD finger remains down.
        final stopGesture = await tester.startGesture(
          tester.getCenter(stopButton),
          pointer: 2,
        );

        await tester.pump(
          const Duration(milliseconds: 100),
        );

        await stopGesture.up();
        await tester.pump();

        expect(
          find.text('STOPPED'),
          findsOneWidget,
        );

        await waitForCommand(
          tester,
          'STOP',
        );

        expect(
          commands.last,
          'STOP',
        );

        // Keep the original finger held briefly.
        // The screen must not restart driving.
        await tester.pump(
          const Duration(milliseconds: 300),
        );

        expect(
          find.text('STOPPED'),
          findsOneWidget,
        );

        expect(
          commands.last,
          'STOP',
        );

        // Release the original FORWARD finger.
        await forwardGesture.up();
        await tester.pump();

        expect(
          find.text('STOPPED'),
          findsOneWidget,
        );

        await waitForCommand(
          tester,
          'STOP',
        );
      },
    );

    // TEST 7
    testWidgets(
      'Speed slider is displayed',
      (tester) async {
        await openScreen(tester);

        expect(
          find.byType(Slider),
          findsOneWidget,
        );

        expect(
          find.text('Speed: 40%'),
          findsOneWidget,
        );
      },
    );
  });
}
