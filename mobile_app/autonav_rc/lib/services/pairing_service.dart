import 'api_config.dart';

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

abstract class PairingTokenStore {
  Future<void> save(String token);
  Future<String?> read();
  Future<void> clear();
}

class SecurePairingTokenStore implements PairingTokenStore {
  static const _key = 'autonav_pairing_token';
  final FlutterSecureStorage storage;

  SecurePairingTokenStore({FlutterSecureStorage? storage})
    : storage = storage ?? const FlutterSecureStorage();

  @override
  Future<void> save(String token) => storage.write(key: _key, value: token);

  @override
  Future<String?> read() => storage.read(key: _key);

  @override
  Future<void> clear() => storage.delete(key: _key);
}

class PairingService {
  final http.Client client;
  final PairingTokenStore tokenStore;
  final String baseUrl;

  PairingService({
    required this.client,
    required this.tokenStore,
    this.baseUrl = autoNavApiOrigin,
  });

  Future<String> pair(String code) async {
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const FormatException('Enter exactly six digits.');
    }

    final response = await client
        .post(
          Uri.parse('$baseUrl/api/v1/pairing/connect'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'code': code}),
        )
        .timeout(const Duration(seconds: 5));

    final body = jsonDecode(response.body);

    if (body is! Map<String, dynamic>) {
      throw const FormatException('Invalid server response.');
    }

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['detail'] ?? 'Pairing failed.');
    }

    final token = body['access_token'];

    if (token is! String || token.isEmpty) {
      throw const FormatException('No valid pairing token received.');
    }

    await tokenStore.save(token);

    return 'Phone paired successfully.';
  }

  Future<String?> getToken() => tokenStore.read();

  Future<void> disconnect() => tokenStore.clear();
}
