import 'controller_settings_service.dart';
import 'controller_verification_service.dart';

class ControllerActivationResult {
  const ControllerActivationResult({
    required this.activated,
    required this.message,
  });

  final bool activated;
  final String message;
}

class ControllerActivationService {
  ControllerActivationService({
    required this._settingsService,
    required this._verificationService,
  });

  final ControllerSettingsService _settingsService;
  final ControllerVerificationService _verificationService;

  String? _activeOrigin;

  String? get activeOrigin => _activeOrigin;

  bool get isActivated => _activeOrigin != null;

  void deactivate() {
    _activeOrigin = null;
  }

  bool isActiveFor(ControllerSettings settings) {
    return _activeOrigin == settings.origin;
  }

  Future<ControllerActivationResult> activate() async {
    // Always revoke previous activation before trying
    // to verify a new controller.
    deactivate();

    try {
      final settings = await _settingsService.load();

      if (settings == null) {
        return const ControllerActivationResult(
          activated: false,
          message: 'Save a controller address first.',
        );
      }

      final verification = await _verificationService.verify(settings);

      if (!verification.trusted) {
        return ControllerActivationResult(
          activated: false,
          message: verification.message,
        );
      }

      _activeOrigin = settings.origin;

      return ControllerActivationResult(
        activated: true,
        message:
            'Controller verified and activated for '
            'this application session. '
            'Phone pairing is also required.',
      );
    } catch (error) {
      deactivate();

      return ControllerActivationResult(
        activated: false,
        message: 'Controller activation failed: $error',
      );
    }
  }
}
