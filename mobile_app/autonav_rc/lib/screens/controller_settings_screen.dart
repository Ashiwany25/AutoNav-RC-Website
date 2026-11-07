import 'package:flutter/material.dart';

import '../services/api_config.dart';
import '../services/controller_activation_service.dart';
import '../services/controller_runtime_gate.dart';
import '../services/controller_settings_service.dart';
import '../services/controller_verification_service.dart';

class ControllerSettingsScreen extends StatefulWidget {
  const ControllerSettingsScreen({super.key, this.service});

  final ControllerSettingsService? service;

  @override
  State<ControllerSettingsScreen> createState() =>
      _ControllerSettingsScreenState();
}

class _ControllerSettingsScreenState extends State<ControllerSettingsScreen> {
  final hostController = TextEditingController();

  late final ControllerSettingsService service;
  late final ControllerActivationService activationService;

  bool working = true;
  String message = 'Loading saved settings...';
  String? savedOrigin;

  @override
  void initState() {
    super.initState();

    service = widget.service ?? ControllerSettingsService();

    activationService = ControllerActivationService(
      settingsService: service,
      verificationService: ControllerVerificationService(),
    );

    loadSettings();
  }

  Future<void> loadSettings() async {
    try {
      final settings = await service.load();

      if (!mounted) return;

      setState(() {
        hostController.text = settings?.host ?? autoNavWifiHost;
        savedOrigin = settings?.origin;

        message = settings == null
            ? 'No controller address saved yet.'
            : 'Saved controller: ${settings.origin}';

        working = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        working = false;
        message = 'Unable to load settings: $error';
      });
    }
  }

  Future<void> saveSettings() async {
    if (working) return;

    setState(() => working = true);

    try {
      final settings = await service.save(hostController.text);

      // Saving a host always requires new activation.
      ControllerRuntimeGate.deactivate();
      activationService.deactivate();

      if (!mounted) return;

      setState(() {
        savedOrigin = settings.origin;
        message =
            'Controller address saved. Verify and activate '
            'the controller before movement.';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        message = 'Invalid settings: $error';
      });
    } finally {
      if (mounted) {
        setState(() => working = false);
      }
    }
  }

  Future<void> verifyController() async {
    if (working) return;

    setState(() {
      working = true;
      message = 'Verifying HTTPS connection...';
    });

    try {
      final settings = ControllerSettings.fromHost(hostController.text);

      final result = await ControllerVerificationService().verify(settings);

      if (!mounted) return;

      setState(() {
        message = result.message;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        message = 'Verification failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() => working = false);
      }
    }
  }

  Future<void> activateController() async {
    if (working) return;

    setState(() {
      working = true;
      message = 'Activating verified controller...';
    });

    ControllerRuntimeGate.deactivate();

    try {
      // Prevent activating an address that has
      // been edited but not saved.
      final entered = ControllerSettings.fromHost(hostController.text);

      final saved = await service.load();

      if (saved == null || saved.origin != entered.origin) {
        throw const FormatException('Save the current address first.');
      }

      final result = await activationService.activate();

      if (!result.activated) {
        throw StateError(result.message);
      }

      ControllerRuntimeGate.activate(saved.origin);

      if (!mounted) return;

      setState(() {
        message =
            'Controller activated for this app session. '
            'Pairing is also required.';
      });
    } catch (error) {
      ControllerRuntimeGate.deactivate();
      activationService.deactivate();

      if (!mounted) return;

      setState(() {
        message = 'Activation failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() => working = false);
      }
    }
  }

  void deactivateController() {
    ControllerRuntimeGate.deactivate();
    activationService.deactivate();

    setState(() {
      message =
          'Controller deactivated. '
          'New movement commands are blocked.';
    });
  }

  Future<void> clearSettings() async {
    if (working) return;

    setState(() => working = true);

    try {
      await service.clear();

      ControllerRuntimeGate.deactivate();
      activationService.deactivate();

      if (!mounted) return;

      setState(() {
        savedOrigin = null;
        hostController.clear();
        message = 'Controller address cleared.';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        message = 'Unable to clear settings: $error';
      });
    } finally {
      if (mounted) {
        setState(() => working = false);
      }
    }
  }

  @override
  void dispose() {
    hostController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Controller Connection')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.wifi, size: 60),
            const SizedBox(height: 16),
            const Text(
              'Local Controller Address',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('controller_host_input'),
              controller: hostController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Controller IP address',
                hintText: '192.168.1.13',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.router),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Private IPv4 address only. '
              'HTTPS port 8443.',
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              key: const Key('save_controller_button'),
              onPressed: working ? null : saveSettings,
              icon: const Icon(Icons.save_outlined),
              label: const Text('SAVE ADDRESS'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('verify_controller_button'),
              onPressed: working ? null : verifyController,
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('VERIFY CONTROLLER'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              key: const Key('activate_controller_button'),
              onPressed: working ? null : activateController,
              icon: const Icon(Icons.lock_open_outlined),
              label: const Text('ACTIVATE CONTROLLER'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('deactivate_controller_button'),
              onPressed: working ? null : deactivateController,
              icon: const Icon(Icons.lock_outline),
              label: const Text('DEACTIVATE CONTROLLER'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('clear_controller_button'),
              onPressed: working ? null : clearSettings,
              icon: const Icon(Icons.delete_outline),
              label: const Text('CLEAR ADDRESS'),
            ),
            const SizedBox(height: 20),
            if (working) const LinearProgressIndicator(),
            Text(
              message,
              key: const Key('controller_settings_message'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (savedOrigin != null)
              SelectableText(savedOrigin!, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Stop navigation before changing '
                  'controller settings. Activation is '
                  'an app-side safeguard, not a physical '
                  'emergency stop. Real motor control '
                  'will require a hardware watchdog '
                  'and server-side authorization.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
