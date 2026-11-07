import 'package:flutter_test/flutter_test.dart';
import 'package:autonav_rc/services/api_config.dart';
import 'package:autonav_rc/services/controller_runtime_gate.dart';

void main() {
  test('Wi-Fi URL uses enrolled build-time controller host', () {
    expect(autoNavWifiHost, isNotEmpty);
    if (autoNavWifiMode) {
      expect(autoNavApiOrigin, 'https://$autoNavWifiHost:8443');
    } else {
      expect(autoNavApiOrigin, 'http://127.0.0.1:8000');
    }
  });
  test('Different controller cannot activate without enrolled build', () {
    ControllerRuntimeGate.deactivate();
    expect(
      () => ControllerRuntimeGate.activate('https://10.1.2.3:8443'),
      throwsA(isA<ControllerNotActivatedException>()),
    );
  });
}
