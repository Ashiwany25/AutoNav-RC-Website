import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ControllerSettings {
  const ControllerSettings({required this.host, this.port = 8443});

  final String host;
  final int port;

  String get origin => 'https://$host:$port';

  static bool isValidLocalIpv4(String address) {
    final parts = address.split('.');

    if (parts.length != 4) return false;

    final octets = <int>[];

    for (final part in parts) {
      if (part.isEmpty || !RegExp(r'^\d{1,3}$').hasMatch(part)) {
        return false;
      }

      // Avoid ambiguous IPv4 representations.
      if (part.length > 1 && part.startsWith('0')) {
        return false;
      }

      final number = int.tryParse(part);

      if (number == null || number > 255) {
        return false;
      }

      octets.add(number);
    }

    final a = octets[0];
    final b = octets[1];

    return a == 10 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168);
  }

  static ControllerSettings fromHost(String value) {
    final host = value.trim();

    if (!isValidLocalIpv4(host)) {
      throw const FormatException(
        'Enter a valid private-network IPv4 address, '
        'such as 192.168.1.13.',
      );
    }

    return ControllerSettings(host: host);
  }
}

abstract class ControllerSettingsStore {
  Future<String?> readHost();
  Future<void> saveHost(String host);
  Future<void> clear();
}

class SecureControllerSettingsStore implements ControllerSettingsStore {
  SecureControllerSettingsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'autonav_controller_host';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readHost() => _storage.read(key: _key);

  @override
  Future<void> saveHost(String host) => _storage.write(key: _key, value: host);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class ControllerSettingsService {
  ControllerSettingsService({ControllerSettingsStore? store})
    : _store = store ?? SecureControllerSettingsStore();

  final ControllerSettingsStore _store;

  Future<ControllerSettings?> load() async {
    final host = await _store.readHost();

    if (host == null || host.isEmpty) {
      return null;
    }

    return ControllerSettings.fromHost(host);
  }

  Future<ControllerSettings> save(String input) async {
    final settings = ControllerSettings.fromHost(input);

    await _store.saveHost(settings.host);

    return settings;
  }

  Future<void> clear() => _store.clear();
}
