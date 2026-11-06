import 'controller_settings_screen.dart';
import '../services/authenticated_client.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/pairing_service.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key, this.service});

  final PairingService? service;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final controller = TextEditingController();

  late final PairingService service;
  http.Client? ownedClient;

  bool working = false;
  String message = 'Enter the code shown in the Mac terminal.';

  @override
  void initState() {
    super.initState();

    if (widget.service != null) {
      service = widget.service!;
    } else {
      ownedClient = AuthenticatedClient();

      service = PairingService(
        client: ownedClient!,
        tokenStore: SecurePairingTokenStore(),
      );
    }
  }

  Future<void> pairPhone() async {
    if (working) return;

    setState(() => working = true);

    try {
      final result = await service.pair(controller.text.trim());

      if (!mounted) return;

      PairingRecoveryState.clear();

      setState(() => message = result);
      controller.clear();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        message = 'Pairing error: $error';
      });
    } finally {
      if (mounted) {
        setState(() => working = false);
      }
    }
  }

  Future<void> clearPairing() async {
    if (working) return;

    setState(() => working = true);

    try {
      await service.disconnect();

      if (!mounted) return;

      setState(() {
        message = 'Saved pairing token cleared.';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        message = 'Unable to clear pairing: $error';
      });
    } finally {
      if (mounted) {
        setState(() => working = false);
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    ownedClient?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pair AutoNav RC')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.phonelink_lock, size: 64),
            const SizedBox(height: 20),
            const Text(
              'Secure Device Pairing',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            const Text(
              'Enter the current six-digit code shown '
              'in your FastAPI terminal. Use the '
              'trusted local HTTPS connection. '
              'You do not need a new code if your '
              'existing pairing token is still valid.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextField(
              key: const Key('pairing_code_input'),
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 6,
              obscureText: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Six-digit pairing code',
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              key: const Key('pair_device_button'),
              onPressed: working ? null : pairPhone,
              icon: const Icon(Icons.lock),
              label: const Text('PAIR DEVICE'),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ControllerSettingsScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.wifi),
              label: const Text('CONTROLLER CONNECTION'),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: working ? null : clearPairing,
              child: const Text('CLEAR SAVED TOKEN'),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              key: const Key('pairing_message'),
              textAlign: TextAlign.center,
            ),
            if (working) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
