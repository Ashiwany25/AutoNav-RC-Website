import 'package:http/http.dart' as http;

import 'local_https_client.dart';

const bool autoNavWifiMode = bool.fromEnvironment(
  'AUTONAV_WIFI',
  defaultValue: false,
);

const String autoNavWifiHost = '192.168.1.13';

const String autoNavApiOrigin = autoNavWifiMode
    ? 'https://192.168.1.13:8443'
    : 'http://127.0.0.1:8000';

http.Client createAutoNavTransport() {
  if (autoNavWifiMode) {
    return LocalHttpsClient(allowedHost: autoNavWifiHost, allowedPort: 8443);
  }

  // Existing USB development mode.
  return http.Client();
}
