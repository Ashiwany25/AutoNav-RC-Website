import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:autonav_rc/services/authenticated_client.dart';
import 'package:autonav_rc/services/pairing_service.dart';

class FakeTokenStore implements PairingTokenStore {
  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> save(String value) async {
    token = value;
  }

  @override
  Future<void> clear() async {
    token = null;
  }
}

void main() {
  group('AuthenticatedClient', () {
    test('Attaches a valid saved token', () async {
      final store = FakeTokenStore();
      await store.save('my-test-token');

      String? receivedHeader;

      final client = AuthenticatedClient(
        tokenStore: store,
        inner: MockClient((request) async {
          receivedHeader = request.headers['Authorization'];
          return http.Response('OK', 200);
        }),
      );

      final response = await client.get(
        Uri.parse('http://localhost/api/v1/test'),
      );

      expect(response.statusCode, 200);
      expect(receivedHeader, 'Bearer my-test-token');

      client.close();
    });

    test('Works before pairing', () async {
      final store = FakeTokenStore();

      String? receivedHeader;

      final client = AuthenticatedClient(
        tokenStore: store,
        inner: MockClient((request) async {
          receivedHeader = request.headers['Authorization'];
          return http.Response('OK', 200);
        }),
      );

      final response = await client.get(
        Uri.parse('http://localhost/api/v1/test'),
      );

      expect(response.statusCode, 200);
      expect(receivedHeader, isNull);

      client.close();
    });

    test('Cleared token is no longer sent', () async {
      final store = FakeTokenStore();
      await store.save('temporary-token');
      await store.clear();

      final client = AuthenticatedClient(
        tokenStore: store,
        inner: MockClient((request) async {
          expect(request.headers.containsKey('Authorization'), isFalse);

          return http.Response('OK', 200);
        }),
      );

      final response = await client.get(
        Uri.parse('http://localhost/api/v1/test'),
      );

      expect(response.statusCode, 200);

      client.close();
    });

    test('Preserves existing Authorization', () async {
      final store = FakeTokenStore();
      await store.save('stored-token');

      final client = AuthenticatedClient(
        tokenStore: store,
        inner: MockClient((request) async {
          expect(
            request.headers['Authorization'],
            'Bearer explicitly-provided',
          );

          return http.Response('OK', 200);
        }),
      );

      await client.get(
        Uri.parse('http://localhost/api/v1/test'),
        headers: {'Authorization': 'Bearer explicitly-provided'},
      );

      client.close();
    });
  });
}
