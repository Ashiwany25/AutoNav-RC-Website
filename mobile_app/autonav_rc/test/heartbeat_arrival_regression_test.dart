import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:autonav_rc/services/navigation_heartbeat_service.dart';

void main() {
  test('HTTP 409 after ARRIVED is not a lost connection', () async {
    final finished = Completer<String>();
    var heartbeats = 0;
    var connectionLost = false;

    final client = MockClient((request) async {
      if (request.url.path.endsWith('/heartbeat')) {
        heartbeats++;

        if (heartbeats == 1) {
          return http.Response('{}', 200);
        }

        return http.Response('{"detail":"Navigation is not active."}', 409);
      }

      if (request.url.path.endsWith('/status')) {
        return http.Response(
          '{"success":true,'
          '"simulation":true,'
          '"physical_motors_active":false,'
          '"navigation_state":"ARRIVED",'
          '"path":[]}',
          200,
        );
      }

      return http.Response('{}', 404);
    });

    final service = NavigationHeartbeatService(
      client: client,
      baseUrl: 'https://192.168.1.13:8443',
      interval: const Duration(milliseconds: 20),
      onConnectionLost: (_) {
        connectionLost = true;
      },
      onTerminalStatus: (status) {
        if (!finished.isCompleted) {
          finished.complete(status['navigation_state'] as String);
        }
      },
    );

    try {
      expect(await service.start(), isTrue);

      expect(
        await finished.future.timeout(const Duration(seconds: 2)),
        'ARRIVED',
      );

      expect(service.isActive, isFalse);
      expect(connectionLost, isFalse);
    } finally {
      service.dispose();
      client.close();
    }
  });

  test('HTTP 409 while still navigating reports failure', () async {
    final failed = Completer<String>();
    var heartbeats = 0;
    var terminalReported = false;

    final client = MockClient((request) async {
      if (request.url.path.endsWith('/heartbeat')) {
        heartbeats++;
        return heartbeats == 1
            ? http.Response('{}', 200)
            : http.Response('Conflict', 409);
      }

      if (request.url.path.endsWith('/status')) {
        return http.Response(
          '{"success":true,'
          '"simulation":true,'
          '"physical_motors_active":false,'
          '"navigation_state":"NAVIGATING"}',
          200,
        );
      }

      return http.Response('{}', 404);
    });

    final service = NavigationHeartbeatService(
      client: client,
      baseUrl: 'https://192.168.1.13:8443',
      interval: const Duration(milliseconds: 20),
      onTerminalStatus: (_) {
        terminalReported = true;
      },
      onConnectionLost: (reason) {
        if (!failed.isCompleted) {
          failed.complete(reason);
        }
      },
    );

    try {
      expect(await service.start(), isTrue);

      final reason = await failed.future.timeout(const Duration(seconds: 2));

      expect(reason, contains('409'));
      expect(terminalReported, isFalse);
      expect(service.isActive, isFalse);
    } finally {
      service.dispose();
      client.close();
    }
  });
}
