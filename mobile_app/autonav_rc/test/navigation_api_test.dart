
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('AutoNav API Mock Tests', () {
    test('Fetches the indoor occupancy grid', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.path,
          '/api/v1/maps/current',
        );

        return http.Response(
          jsonEncode({
            'success': true,
            'width': 3,
            'height': 3,
            'resolution': 0.1,
            'grid': [
              [0, 0, 0],
              [0, 1, 0],
              [0, 0, 0],
            ],
            'robot_position': {
              'row': 0,
              'col': 0,
            },
          }),
          200,
        );
      });

      final response = await client.get(
        Uri.parse(
          'http://127.0.0.1:8000/api/v1/maps/current',
        ),
      );

      final data = jsonDecode(response.body);

      expect(response.statusCode, 200);
      expect(data['success'], true);
      expect(data['grid'][1][1], 1);
      expect(data['robot_position']['row'], 0);

      client.close();
    });

    test('Receives a valid A* route', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.path,
          '/api/v1/navigation/plan',
        );

        final body = jsonDecode(request.body);

        expect(body['goal']['row'], 0);
        expect(body['goal']['col'], 2);

        return http.Response(
          jsonEncode({
            'success': true,
            'navigation_state': 'READY',
            'path': [
              {'row': 0, 'col': 0},
              {'row': 0, 'col': 1},
              {'row': 0, 'col': 2},
            ],
            'steps': 2,
          }),
          200,
        );
      });

      final response = await client.post(
        Uri.parse(
          'http://127.0.0.1:8000/api/v1/navigation/plan',
        ),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'goal': {
            'row': 0,
            'col': 2,
          },
        }),
      );

      final data = jsonDecode(response.body);

      expect(response.statusCode, 200);
      expect(data['path'].length, 3);
      expect(data['steps'], 2);

      client.close();
    });

    test('Starts simulated navigation', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.path,
          '/api/v1/navigation/start',
        );

        final body = jsonDecode(request.body);

        expect(body['goal']['row'], 2);
        expect(body['goal']['col'], 2);

        return http.Response(
          jsonEncode({
            'success': true,
            'navigation_state': 'NAVIGATING',
          }),
          200,
        );
      });

      final response = await client.post(
        Uri.parse(
          'http://127.0.0.1:8000/api/v1/navigation/start',
        ),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'goal': {
            'row': 2,
            'col': 2,
          },
        }),
      );

      final data = jsonDecode(response.body);

      expect(response.statusCode, 200);
      expect(data['navigation_state'], 'NAVIGATING');

      client.close();
    });

    test('Stops simulated navigation', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.path,
          '/api/v1/navigation/stop',
        );

        return http.Response(
          jsonEncode({
            'success': true,
            'navigation_state': 'STOPPED',
          }),
          200,
        );
      });

      final response = await client.post(
        Uri.parse(
          'http://127.0.0.1:8000/api/v1/navigation/stop',
        ),
      );

      final data = jsonDecode(response.body);

      expect(response.statusCode, 200);
      expect(data['navigation_state'], 'STOPPED');

      client.close();
    });

    test('Handles an unavailable API', () async {
      final client = MockClient((request) async {
        throw Exception('Connection lost');
      });

      expect(
        () => client.get(
          Uri.parse(
            'http://127.0.0.1:8000/api/v1/maps/current',
          ),
        ),
        throwsException,
      );

      client.close();
    });
  });
}
