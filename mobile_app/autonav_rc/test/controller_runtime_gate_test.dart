import 'package:flutter_test/flutter_test.dart';

import 'package:autonav_rc/services/controller_runtime_gate.dart';
import 'package:autonav_rc/services/controller_settings_service.dart';

class FakeControllerStore implements ControllerSettingsStore {
  String? host;

  @override
  Future<String?> readHost() async => host;

  @override
  Future<void> saveHost(String value) async {
    host = value;
  }

  @override
  Future<void> clear() async {
    host = null;
  }
}

void main() {
  late FakeControllerStore store;
  late ControllerSettingsService settings;

  final startUrl = Uri.parse(
    'https://192.168.1.13:8443/'
    'api/v1/teach/navigation/sim/start',
  );

  final stopUrl = Uri.parse(
    'https://192.168.1.13:8443/'
    'api/v1/teach/navigation/sim/stop',
  );

  setUp(() {
    ControllerRuntimeGate.deactivate();

    store = FakeControllerStore();

    settings = ControllerSettingsService(store: store);
  });

  tearDown(() {
    ControllerRuntimeGate.deactivate();
  });

  test('Blocks navigation before activation', () async {
    await settings.save('192.168.1.13');

    await expectLater(
      ControllerRuntimeGate.ensureAllowed(
        method: 'POST',
        url: startUrl,
        wifiMode: true,
        settingsService: settings,
      ),
      throwsA(isA<ControllerNotActivatedException>()),
    );
  });

  test('Allows explicitly activated controller', () async {
    await settings.save('192.168.1.13');

    ControllerRuntimeGate.activate('https://192.168.1.13:8443');

    await ControllerRuntimeGate.ensureAllowed(
      method: 'POST',
      url: startUrl,
      wifiMode: true,
      settingsService: settings,
    );

    expect(ControllerRuntimeGate.isActivated, isTrue);
  });

  test('Rejects changed controller address', () async {
    await settings.save('192.168.1.13');

    ControllerRuntimeGate.activate('https://192.168.1.13:8443');

    await settings.save('192.168.1.20');

    await expectLater(
      ControllerRuntimeGate.ensureAllowed(
        method: 'POST',
        url: startUrl,
        wifiMode: true,
        settingsService: settings,
      ),
      throwsA(isA<ControllerNotActivatedException>()),
    );

    expect(ControllerRuntimeGate.isActivated, isFalse);
  });

  test('STOP remains available without activation', () async {
    await ControllerRuntimeGate.ensureAllowed(
      method: 'POST',
      url: stopUrl,
      wifiMode: true,
      settingsService: settings,
    );
  });

  test('USB development mode remains compatible', () async {
    await ControllerRuntimeGate.ensureAllowed(
      method: 'POST',
      url: Uri.parse('http://127.0.0.1:8000/api/v1/manual/drive'),
      wifiMode: false,
      settingsService: settings,
    );
  });

  test('Unknown controller cannot be activated', () {
    expect(
      () => ControllerRuntimeGate.activate('https://192.168.1.20:8443'),
      throwsA(isA<ControllerNotActivatedException>()),
    );
  });
}
