import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:autonav_rc/services/controller_activation_service.dart';
import 'package:autonav_rc/services/controller_settings_service.dart';
import 'package:autonav_rc/services/controller_verification_service.dart';

class FakeControllerStore implements ControllerSettingsStore {
  String? savedHost;

  @override
  Future<String?> readHost() async => savedHost;

  @override
  Future<void> saveHost(String host) async {
    savedHost = host;
  }

  @override
  Future<void> clear() async {
    savedHost = null;
  }
}

void main() {
  group('Trusted Controller Activation', () {
    late FakeControllerStore store;
    late ControllerSettingsService settings;

    setUp(() {
      store = FakeControllerStore();
      settings = ControllerSettingsService(store: store);
    });

    ControllerActivationService createService({int statusCode = 200}) {
      return ControllerActivationService(
        settingsService: settings,
        verificationService: ControllerVerificationService(
          clientFactory: (host) => MockClient(
            (request) async => http.Response('{"status":"online"}', statusCode),
          ),
        ),
      );
    }

    test('Rejects activation without saved address', () async {
      final service = createService();

      final result = await service.activate();

      expect(result.activated, isFalse);
      expect(service.isActivated, isFalse);
    });

    test('Activates verified development controller', () async {
      await settings.save('192.168.1.13');

      final service = createService();
      final result = await service.activate();

      expect(result.activated, isTrue);
      expect(service.isActivated, isTrue);
      expect(service.activeOrigin, 'https://192.168.1.13:8443');
    });

    test('Rejects an unenrolled controller', () async {
      await settings.save('192.168.1.20');

      final service = createService();
      final result = await service.activate();

      expect(result.activated, isFalse);
      expect(service.activeOrigin, isNull);
    });

    test('Rejects server verification failure', () async {
      await settings.save('192.168.1.13');

      final service = createService(statusCode: 503);
      final result = await service.activate();

      expect(result.activated, isFalse);
      expect(service.isActivated, isFalse);
    });

    test('Deactivation removes controller authorization', () async {
      await settings.save('192.168.1.13');

      final service = createService();

      await service.activate();

      expect(service.isActivated, isTrue);

      service.deactivate();

      expect(service.isActivated, isFalse);
      expect(service.activeOrigin, isNull);
    });

    test('Changing saved host invalidates matching check', () async {
      await settings.save('192.168.1.13');

      final service = createService();

      await service.activate();

      final other = ControllerSettings.fromHost('192.168.1.20');

      expect(service.isActiveFor(other), isFalse);

      await settings.save('192.168.1.20');

      final result = await service.activate();

      expect(result.activated, isFalse);
      expect(service.activeOrigin, isNull);
    });
  });
}
