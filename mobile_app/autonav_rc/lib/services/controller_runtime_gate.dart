import 'api_config.dart';
import 'controller_settings_service.dart';

class ControllerNotActivatedException implements Exception {
  const ControllerNotActivatedException();

  @override
  String toString() =>
      'Controller not activated. '
      'Open Settings → Controller Connection '
      'and activate the verified controller.';
}

class ControllerRuntimeGate {
  static String? _activeOrigin;

  static bool get isActivated => _activeOrigin != null;

  static String? get activeOrigin => _activeOrigin;

  static void activate(String origin) {
    // Activation is allowed only for our current
    // development controller. The settings UI
    // must first verify its HTTPS certificate.
    if (origin != 'https://$autoNavWifiHost:8443') {
      throw const ControllerNotActivatedException();
    }

    _activeOrigin = origin;
  }

  static void deactivate() {
    _activeOrigin = null;
  }

  static bool requiresActivation(String method, Uri url) {
    if (method.toUpperCase() != 'POST') {
      return false;
    }

    final path = url.path;

    if (!path.startsWith('/api/v1/')) {
      return false;
    }

    // Pairing must remain possible before
    // controller activation.
    if (path.startsWith('/api/v1/pairing/')) {
      return false;
    }

    // Never block a STOP request merely
    // because local activation was lost.
    if (path.endsWith('/stop')) {
      return false;
    }

    // Fail closed for all other API POSTs,
    // including existing and future control
    // commands.
    return true;
  }

  static Future<void> ensureAllowed({
    required String method,
    required Uri url,
    required bool wifiMode,
    ControllerSettingsService? settingsService,
  }) async {
    if (!wifiMode || !requiresActivation(method, url)) {
      return;
    }

    final approvedOrigin = _activeOrigin;

    if (approvedOrigin == null) {
      throw const ControllerNotActivatedException();
    }

    try {
      final service = settingsService ?? ControllerSettingsService();

      final saved = await service.load();

      if (saved == null ||
          saved.origin != approvedOrigin ||
          (autoNavWifiMode && saved.origin != autoNavApiOrigin) ||
          url.origin != approvedOrigin) {
        deactivate();
        throw const ControllerNotActivatedException();
      }
    } on ControllerNotActivatedException {
      rethrow;
    } catch (_) {
      deactivate();
      throw const ControllerNotActivatedException();
    }
  }
}
