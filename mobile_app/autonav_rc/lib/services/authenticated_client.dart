import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'controller_runtime_gate.dart';
import 'pairing_service.dart';

class PairingExpiredException implements Exception {
  const PairingExpiredException();

  @override
  String toString() => 'Pairing expired. Open Settings and pair again.';
}

class PairingRecoveryState {
  static final ValueNotifier<bool> pairingRequired = ValueNotifier<bool>(false);

  static void requirePairing() {
    pairingRequired.value = true;
    ControllerRuntimeGate.deactivate();
  }

  static void clear() {
    pairingRequired.value = false;
  }
}

class AuthenticatedClient extends http.BaseClient {
  AuthenticatedClient({http.Client? inner, PairingTokenStore? tokenStore})
    : _inner = inner ?? createAutoNavTransport(),
      _tokenStore = tokenStore ?? SecurePairingTokenStore();

  final http.Client _inner;
  final PairingTokenStore _tokenStore;

  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) {
      throw http.ClientException('Authenticated client is closed.');
    }

    // Do not send a movement-capable request
    // unless the trusted controller is active.
    await ControllerRuntimeGate.ensureAllowed(
      method: request.method,
      url: request.url,
      wifiMode: autoNavWifiMode,
    );

    final token = await _tokenStore.read();

    if (autoNavWifiMode &&
        ControllerRuntimeGate.requiresActivation(request.method, request.url) &&
        (token == null || token.isEmpty)) {
      PairingRecoveryState.requirePairing();
      throw const PairingExpiredException();
    }

    if (token != null && token.isNotEmpty) {
      final existing = request.headers['Authorization'];

      if (existing == null || existing.isEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
    }

    final response = await _inner.send(request);

    final pairingEndpoint = request.url.path.startsWith('/api/v1/pairing/');

    if (response.statusCode == 401 && !pairingEndpoint) {
      PairingRecoveryState.requirePairing();

      // Never replay a rejected movement command.
      throw const PairingExpiredException();
    }

    return response;
  }

  @override
  void close() {
    if (_closed) return;

    _closed = true;
    _inner.close();
  }
}
