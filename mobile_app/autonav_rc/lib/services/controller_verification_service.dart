import 'dart:async';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'controller_settings_service.dart';
import 'local_https_client.dart';

class ControllerVerificationResult {
  const ControllerVerificationResult({
    required this.trusted,
    required this.message,
  });

  final bool trusted;
  final String message;
}

class ControllerVerificationService {
  ControllerVerificationService({
    this.trustedHost = autoNavWifiHost,
    this.port = 8443,
    this._clientFactory,
  });

  final String trustedHost;
  final int port;
  final http.Client? Function(String host)? _clientFactory;

  Future<ControllerVerificationResult> verify(
    ControllerSettings settings,
  ) async {
    if (!ControllerSettings.isValidLocalIpv4(settings.host)) {
      return const ControllerVerificationResult(
        trusted: false,
        message: 'Invalid controller address.',
      );
    }

    if (settings.host != trustedHost || settings.port != port) {
      return const ControllerVerificationResult(
        trusted: false,
        message:
            'Controller certificate not enrolled '
            'for this address. Connection blocked.',
      );
    }

    final client =
        _clientFactory?.call(settings.host) ??
        LocalHttpsClient(
          allowedHost: settings.host,
          allowedPort: settings.port,
        );

    try {
      final response = await client
          .get(Uri.parse('${settings.origin}/api/v1/health'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        return ControllerVerificationResult(
          trusted: false,
          message:
              'Controller health check failed: '
              'HTTP ${response.statusCode}',
        );
      }

      return const ControllerVerificationResult(
        trusted: true,
        message:
            'HTTPS certificate verified. '
            'Controller is reachable. '
            'Pairing is still required for control.',
      );
    } catch (error) {
      return ControllerVerificationResult(
        trusted: false,
        message:
            'Secure controller verification failed: '
            '$error',
      );
    } finally {
      client.close();
    }
  }
}
