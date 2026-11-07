import 'package:http/http.dart' as http;

import 'local_https_client.dart';

const bool autoNavWifiMode = bool.fromEnvironment(
  'AUTONAV_WIFI',
  defaultValue: false,
);

// Change this only for a controller whose TLS certificate has been enrolled.
// A different IP without a matching certificate will still fail closed.
const String autoNavWifiHost = String.fromEnvironment(
  'AUTONAV_WIFI_HOST',
  defaultValue: '192.168.1.13',
);

const String autoNavApiOrigin = autoNavWifiMode
    ? 'https://$autoNavWifiHost:8443'
    : 'http://127.0.0.1:8000';

http.Client createAutoNavTransport() {
  if (autoNavWifiMode) {
    return LocalHttpsClient(allowedHost: autoNavWifiHost, allowedPort: 8443);
  }

  // Existing USB development mode.
  return http.Client();
}
