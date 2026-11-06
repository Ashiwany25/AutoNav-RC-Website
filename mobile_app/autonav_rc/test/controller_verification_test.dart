
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:autonav_rc/services/controller_settings_service.dart';
import 'package:autonav_rc/services/controller_verification_service.dart';

void main() {
  group('Controller Verification', () {
    test('Trusted controller passes health check', () async {
      final service = ControllerVerificationService(
        clientFactory: (host) => MockClient(
          (request) async {
            expect(request.url.scheme, 'https');
            expect(request.url.host, '192.168.1.13');
            return http.Response(
              '{"status":"online"}',
              200,
            );
          },
        ),
      );

      final result = await service.verify(
        ControllerSettings.fromHost(
          '192.168.1.13',
        ),
      );

      expect(result.trusted, isTrue);
    });

    test('Unenrolled controller is rejected', () async {
      var requests = 0;

      final service = ControllerVerificationService(
        clientFactory: (host) => MockClient(
          (request) async {
            requests++;
            return http.Response('{}', 200);
          },
        ),
      );

      final result = await service.verify(
        ControllerSettings.fromHost(
          '192.168.1.20',
        ),
      );

      expect(result.trusted, isFalse);
      expect(requests, 0);
    });

    test('HTTP failure rejects controller', () async {
      final service = ControllerVerificationService(
        clientFactory: (host) => MockClient(
          (request) async =>
              http.Response('{}', 503),
        ),
      );

      final result = await service.verify(
        ControllerSettings.fromHost(
          '192.168.1.13',
        ),
      );

      expect(result.trusted, isFalse);
    });

    test('Network failure rejects controller', () async {
      final service = ControllerVerificationService(
        clientFactory: (host) => MockClient(
          (request) async {
            throw Exception('Network unavailable');
          },
        ),
      );

      final result = await service.verify(
        ControllerSettings.fromHost(
          '192.168.1.13',
        ),
      );

      expect(result.trusted, isFalse);
    });
  });
}
