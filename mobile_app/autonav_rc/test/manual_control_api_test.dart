import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:autonav_rc/services/manual_control_api.dart';

void main() {
  
  const sessionId = 'test-session-123';

  group('Manual Control API Tests', () {
    // --------------------------------------
    // MOCK SERVER HELPER
    // --------------------------------------

    MockClient createMockServer({List<Map<String, dynamic>>? received}) {
      return MockClient((request) async {
        final path = request.url.path;

        if (path.endsWith('/manual/session')) {
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
          final body = jsonDecode(request.body) as Map<String, dynamic>;

          received?.add(body);

          if (body['session_id'] != sessionId) {
            return http.Response(
              jsonEncode({'detail': 'Invalid session'}),
              409,
            );
          }

          return http.Response(
            jsonEncode({
              'success': true,
              'simulation': true,
              'mode': 'MANUAL',
              'direction': body['direction'],
              'speed': body['speed'],
              'sequence': body['sequence'],
            }),
            200,
          );
        }

        if (path.endsWith('/manual/stop')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;

          received?.add(body);

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

        if (path.endsWith('/manual/status')) {
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

        return http.Response(jsonEncode({'detail': 'Unknown endpoint'}), 404);
      });
    }

    // --------------------------------------
    // TEST 1: SESSION CREATION
    // --------------------------------------

    test('Creates controller session', () async {
      final client = createMockServer();
      final api = ManualControlApi(client: client);

      final result = await api.createSession();

      expect(result['success'], true);
      expect(api.hasSession, true);
      expect(api.sessionId, sessionId);

      client.close();
    });

    // --------------------------------------
    // TEST 2: DRIVE WITHOUT SESSION
    // --------------------------------------

    test('Drive without session is rejected', () async {
      int requests = 0;

      final client = MockClient((request) async {
        requests++;

        return http.Response(jsonEncode({'success': true}), 200);
      });

      final api = ManualControlApi(client: client);

      await expectLater(
        api.drive(direction: 'FORWARD', speed: 40),
        throwsStateError,
      );

      expect(requests, 0);

      client.close();
    });

    // --------------------------------------
    // TEST 3: FORWARD COMMAND
    // --------------------------------------

    test('FORWARD sends correct API request', () async {
      final received = <Map<String, dynamic>>[];

      final client = createMockServer(received: received);

      final api = ManualControlApi(client: client);

      await api.createSession();

      final result = await api.drive(direction: 'FORWARD', speed: 40);

      expect(result['direction'], 'FORWARD');
      expect(received.length, 1);
      expect(received.first['direction'], 'FORWARD');
      expect(received.first['speed'], 40);
      expect(received.first['sequence'], 1);
      expect(received.first['session_id'], sessionId);

      client.close();
    });

    // --------------------------------------
    // TEST 4: ALL DIRECTIONS
    // --------------------------------------

    test('All four directions work', () async {
      final client = createMockServer();
      final api = ManualControlApi(client: client);

      await api.createSession();

      for (final direction in ['FORWARD', 'BACKWARD', 'LEFT', 'RIGHT']) {
        final result = await api.drive(direction: direction, speed: 30);

        expect(result['direction'], direction);
      }

      client.close();
    });

    // --------------------------------------
    // TEST 5: INCREASING SEQUENCES
    // --------------------------------------

    test('Sequence numbers increase', () async {
      final received = <Map<String, dynamic>>[];

      final client = createMockServer(received: received);

      final api = ManualControlApi(client: client);

      await api.createSession();

      await api.drive(direction: 'FORWARD', speed: 40);

      await api.drive(direction: 'LEFT', speed: 40);

      await api.drive(direction: 'RIGHT', speed: 40);

      expect(received.map((e) => e['sequence']).toList(), [1, 2, 3]);

      client.close();
    });

    // --------------------------------------
    // TEST 6: STOP COMMAND
    // --------------------------------------

    test('STOP sends correct request', () async {
      final received = <Map<String, dynamic>>[];

      final client = createMockServer(received: received);

      final api = ManualControlApi(client: client);

      await api.createSession();

      final result = await api.stop();

      expect(result['mode'], 'STOPPED');
      expect(result['speed'], 0);
      expect(received.length, 1);
      expect(received.first['sequence'], 1);
      expect(received.first['session_id'], sessionId);

      client.close();
    });

    // --------------------------------------
    // TEST 7: STOP INCREASES SEQUENCE
    // --------------------------------------

    test('STOP follows drive sequence', () async {
      final received = <Map<String, dynamic>>[];

      final client = createMockServer(received: received);

      final api = ManualControlApi(client: client);

      await api.createSession();

      await api.drive(direction: 'FORWARD', speed: 40);

      await api.stop();

      expect(received.length, 2);
      expect(received[0]['sequence'], 1);
      expect(received[1]['sequence'], 2);

      client.close();
    });

    // --------------------------------------
    // TEST 8: STATUS
    // --------------------------------------

    test('Manual status returns STOPPED', () async {
      final client = createMockServer();
      final api = ManualControlApi(client: client);

      final result = await api.status();

      expect(result['mode'], 'STOPPED');
      expect(result['speed'], 0);

      client.close();
    });

    // --------------------------------------
    // TEST 9: INVALID DIRECTION
    // --------------------------------------

    test('Invalid direction is rejected', () async {
      final client = createMockServer();
      final api = ManualControlApi(client: client);

      await expectLater(
        api.drive(direction: 'FLY', speed: 40),
        throwsArgumentError,
      );

      client.close();
    });

    // --------------------------------------
    // TEST 10: INVALID SPEED
    // --------------------------------------

    test('Invalid speed is rejected', () async {
      final client = createMockServer();
      final api = ManualControlApi(client: client);

      await expectLater(
        api.drive(direction: 'FORWARD', speed: 150),
        throwsArgumentError,
      );

      client.close();
    });

    // --------------------------------------
    // TEST 11: SERVER ERROR
    // --------------------------------------

    test('Server error is handled', () async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode({'detail': 'Invalid session'}), 409);
      });

      final api = ManualControlApi(client: client);

      await expectLater(api.createSession(), throwsException);

      client.close();
    });

    // --------------------------------------
    // TEST 12: MALFORMED RESPONSE
    // --------------------------------------

    test('Malformed response is rejected', () async {
      final client = MockClient((request) async {
        return http.Response('not valid json', 200);
      });

      final api = ManualControlApi(client: client);

      await expectLater(api.createSession(), throwsFormatException);

      client.close();
    });
  });
}
