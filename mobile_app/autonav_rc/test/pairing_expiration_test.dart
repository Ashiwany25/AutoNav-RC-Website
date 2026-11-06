import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:autonav_rc/services/authenticated_client.dart';
import 'package:autonav_rc/services/pairing_service.dart';

class MemoryTokenStore implements PairingTokenStore {
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
  test('Expired token creates pairing error', () async {
    final store = MemoryTokenStore();
    await store.save('expired-token');

    final client = AuthenticatedClient(
      tokenStore: store,
      inner: MockClient(
        (request) async => http.Response('{"detail":"Unauthorized"}', 401),
      ),
    );

    await expectLater(
      client.get(Uri.parse('http://localhost/api/v1/robot/status')),
      throwsA(isA<PairingExpiredException>()),
    );

    client.close();
  });

  test('Unauthorized command is not retried', () async {
    final store = MemoryTokenStore();
    await store.save('expired-token');

    var requests = 0;

    final client = AuthenticatedClient(
      tokenStore: store,
      inner: MockClient((request) async {
        requests++;
        return http.Response('{}', 401);
      }),
    );

    await expectLater(
      client.post(
        Uri.parse('http://localhost/api/v1/manual/drive'),
        body: '{}',
      ),
      throwsA(isA<PairingExpiredException>()),
    );

    expect(requests, 1);

    client.close();
  });

  test('Normal authenticated request succeeds', () async {
    final store = MemoryTokenStore();
    await store.save('valid-token');

    final client = AuthenticatedClient(
      tokenStore: store,
      inner: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer valid-token');

        return http.Response('{}', 200);
      }),
    );

    final response = await client.get(
      Uri.parse('http://localhost/api/v1/robot/status'),
    );

    expect(response.statusCode, 200);

    client.close();
  });

  test('Pairing endpoint can return its own 401', () async {
    final store = MemoryTokenStore();

    final client = AuthenticatedClient(
      tokenStore: store,
      inner: MockClient((request) async => http.Response('{}', 401)),
    );

    final response = await client.post(
      Uri.parse('http://localhost/api/v1/pairing/connect'),
      body: '{}',
    );

    expect(response.statusCode, 401);

    client.close();
  });
}
