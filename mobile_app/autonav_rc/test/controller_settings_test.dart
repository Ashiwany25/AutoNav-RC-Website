import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:autonav_rc/screens/controller_settings_screen.dart';
import 'package:autonav_rc/services/controller_settings_service.dart';

class FakeSettingsStore implements ControllerSettingsStore {
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
  group('Controller Settings', () {
    test('Accepts valid private IP address', () {
      final settings = ControllerSettings.fromHost('192.168.1.13');

      expect(settings.host, '192.168.1.13');
      expect(settings.origin, 'https://192.168.1.13:8443');
    });

    test('Rejects public IP address', () {
      expect(
        () => ControllerSettings.fromHost('8.8.8.8'),
        throwsFormatException,
      );
    });

    test('Rejects malformed IP address', () {
      expect(
        () => ControllerSettings.fromHost('192.168.1.999'),
        throwsFormatException,
      );
    });

    test('Saves and reloads controller address', () async {
      final store = FakeSettingsStore();
      final service = ControllerSettingsService(store: store);

      await service.save('192.168.1.13');

      final loaded = await service.load();

      expect(loaded?.host, '192.168.1.13');

      await service.clear();

      expect(await service.load(), isNull);
    });

    testWidgets('Displays and saves settings', (tester) async {
      final store = FakeSettingsStore();

      await tester.pumpWidget(
        MaterialApp(
          home: ControllerSettingsScreen(
            service: ControllerSettingsService(store: store),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('controller_host_input')),
        '192.168.1.20',
      );

      await tester.tap(find.byKey(const Key('save_controller_button')));

      await tester.pumpAndSettle();

      expect(store.host, '192.168.1.20');

      await tester.scrollUntilVisible(
        find.byKey(const Key('controller_settings_message')),
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      final messageWidget = tester.widget<Text>(
        find.byKey(const Key('controller_settings_message')),
      );

      expect(messageWidget.data?.toLowerCase(), contains('saved'));
    });
  });
}
