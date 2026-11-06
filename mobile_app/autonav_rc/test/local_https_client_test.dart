import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:autonav_rc/services/local_https_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Local HTTPS Client', () {
    test('Accepts configured HTTPS server address', () {
      final client = LocalHttpsClient(allowedHost: '192.168.1.13');

      expect(
        client.isAllowedUrl(
          Uri.parse('https://192.168.1.13:8443/api/v1/health'),
        ),
        isTrue,
      );

      client.close();
    });

    test('Rejects insecure HTTP URL', () async {
      final client = LocalHttpsClient(allowedHost: '192.168.1.13');

      await expectLater(
        client.get(Uri.parse('http://192.168.1.13:8443/api/v1/health')),
        throwsA(isA<http.ClientException>()),
      );

      client.close();
    });

    test('Rejects unknown server address', () async {
      final client = LocalHttpsClient(allowedHost: '192.168.1.13');

      await expectLater(
        client.get(Uri.parse('https://192.168.1.99:8443/api/v1/health')),
        throwsA(isA<http.ClientException>()),
      );

      client.close();
    });

    test('Rejects incorrect server port', () async {
      final client = LocalHttpsClient(allowedHost: '192.168.1.13');

      await expectLater(
        client.get(Uri.parse('https://192.168.1.13:8000/api/v1/health')),
        throwsA(isA<http.ClientException>()),
      );

      client.close();
    });

    test('Certificate is bundled with the app', () async {
      final certificate = await rootBundle.load(
        'assets/certs/autonav-cert.pem',
      );

      final text = String.fromCharCodes(
        certificate.buffer.asUint8List(
          certificate.offsetInBytes,
          certificate.lengthInBytes,
        ),
      );

      expect(text, contains('BEGIN CERTIFICATE'));

      expect(text, contains('END CERTIFICATE'));
    });
  });
}
