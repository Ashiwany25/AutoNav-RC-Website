import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:autonav_rc/screens/pairing_screen.dart';
import 'package:autonav_rc/services/pairing_service.dart';

class TestTokenStore implements PairingTokenStore {
  String? value;

  @override
  Future<void> save(String token) async {
    value = token;
  }

  @override
  Future<String?> read() async => value;

  @override
  Future<void> clear() async {
    value = null;
  }
}

void main() {
  late TestTokenStore store;
  late MockClient client;

  setUp(() {
    store = TestTokenStore();
  });

  tearDown(() {
    client.close();
  });

  Future<void> openPairingScreen(
    WidgetTester tester,
    http.Client client,
  ) async {
    final service = PairingService(client: client, tokenStore: store);

    await tester.pumpWidget(MaterialApp(home: PairingScreen(service: service)));
  }

  testWidgets('Valid code securely saves pairing token', (tester) async {
    client = MockClient((request) async {
      expect(request.url.path, '/api/v1/pairing/connect');

      expect(jsonDecode(request.body)['code'], '123456');

      return http.Response(
        jsonEncode({
          'success': true,
          'access_token': 'test-token-123',
          'token_type': 'Bearer',
          'expires_in': 86400,
        }),
        200,
      );
    });

    await openPairingScreen(tester, client);

    await tester.enterText(
      find.byKey(const Key('pairing_code_input')),
      '123456',
    );

    await tester.tap(find.byKey(const Key('pair_device_button')));

    await tester.pumpAndSettle();

    expect(store.value, 'test-token-123');

    expect(find.text('Phone paired successfully.'), findsOneWidget);
  });

  testWidgets('Incorrect code does not save token', (tester) async {
    client = MockClient((request) async {
      return http.Response(jsonEncode({'detail': 'Invalid pairing code'}), 403);
    });

    await openPairingScreen(tester, client);

    await tester.enterText(
      find.byKey(const Key('pairing_code_input')),
      '000000',
    );

    await tester.tap(find.byKey(const Key('pair_device_button')));

    await tester.pumpAndSettle();

    expect(store.value, isNull);

    expect(find.textContaining('Invalid pairing code'), findsOneWidget);
  });

  testWidgets('Clearing pairing removes saved token', (tester) async {
    store.value = 'old-token';

    client = MockClient((request) async {
      return http.Response(jsonEncode({'detail': 'Not used'}), 404);
    });

    await openPairingScreen(tester, client);

    await tester.tap(find.text('CLEAR SAVED TOKEN'));

    await tester.pumpAndSettle();

    expect(store.value, isNull);

    expect(find.text('Saved pairing token cleared.'), findsOneWidget);
  });

  testWidgets('Invalid code length makes no network call', (tester) async {
    var requests = 0;

    client = MockClient((request) async {
      requests++;

      return http.Response('{}', 400);
    });

    await openPairingScreen(tester, client);

    await tester.enterText(find.byKey(const Key('pairing_code_input')), '123');

    await tester.tap(find.byKey(const Key('pair_device_button')));

    await tester.pumpAndSettle();

    expect(requests, 0);
    expect(store.value, isNull);

    expect(find.textContaining('Enter exactly six digits'), findsOneWidget);
  });
}
