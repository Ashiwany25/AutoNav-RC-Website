import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:autonav_rc/services/navigation_heartbeat_service.dart';

void main() {
  group('Navigation Heartbeat Service', () {
    test('Successful heartbeat returns true', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/teach/navigation/sim/heartbeat');

        return http.Response('{}', 200);
      });

      final service = NavigationHeartbeatService(
        client: client,
        baseUrl: 'https://192.168.1.13:8443',
      );

      expect(await service.sendOnce(), isTrue);

      service.dispose();
      client.close();
    });

    test('Server failure returns false', () async {
      final client = MockClient((request) async => http.Response('{}', 503));

      final service = NavigationHeartbeatService(
        client: client,
        baseUrl: 'https://192.168.1.13:8443',
      );

      expect(await service.sendOnce(), isFalse);

      service.dispose();
      client.close();
    });

    test('Missing pairing is rejected', () async {
      final client = MockClient(
        (request) async => http.Response('{"detail":"Unauthorized"}', 401),
      );

      final service = NavigationHeartbeatService(
        client: client,
        baseUrl: 'https://192.168.1.13:8443',
      );

      expect(await service.sendOnce(), isFalse);

      service.dispose();
      client.close();
    });

    test('Heartbeat cannot restart after disposal', () async {
      final client = MockClient((request) async => http.Response('{}', 200));

      final service = NavigationHeartbeatService(
        client: client,
        baseUrl: 'https://192.168.1.13:8443',
      );

      service.dispose();

      expect(await service.start(), isFalse);

      client.close();
    });

    test('Failed activation reports connection loss', () async {
      final client = MockClient((request) async => http.Response('{}', 503));

      String? failure;

      final service = NavigationHeartbeatService(
        client: client,
        baseUrl: 'https://192.168.1.13:8443',
        onConnectionLost: (reason) {
          failure = reason;
        },
      );

      expect(await service.start(), isFalse);
      expect(service.isActive, isFalse);
      expect(failure, isNotNull);

      service.dispose();
      client.close();
    });

    test('Stop disables periodic heartbeats', () async {
      final client = MockClient((request) async => http.Response('{}', 200));

      final service = NavigationHeartbeatService(
        client: client,
        baseUrl: 'https://192.168.1.13:8443',
      );

      expect(await service.start(), isTrue);
      expect(service.isActive, isTrue);

      service.stop();

      expect(service.isActive, isFalse);

      service.dispose();
      client.close();
    });
  });
}
