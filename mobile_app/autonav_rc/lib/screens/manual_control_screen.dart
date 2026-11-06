import 'dart:async';

import 'package:flutter/material.dart';

import '../services/manual_control_api.dart';

class ManualControlScreen extends StatefulWidget {
  const ManualControlScreen({super.key, this.apiClient});

  final ManualControlApi? apiClient;

  @override
  State<ManualControlScreen> createState() => _ManualControlScreenState();
}

class _ManualControlScreenState extends State<ManualControlScreen>
    with WidgetsBindingObserver {
  late final ManualControlApi api;

  static const Duration commandInterval = Duration(milliseconds: 200);

  Timer? commandTimer;

  String currentCommand = 'STOPPED';
  String connectionStatus = 'CONNECTING...';

  String? heldDirection;

  double speed = 40;

  bool sessionReady = false;
  bool connecting = false;
  bool commandInFlight = false;
  bool stopping = false;

  int commandGeneration = 0;

  @override
  void initState() {
    super.initState();

    api = widget.apiClient ?? ManualControlApi();

    WidgetsBinding.instance.addObserver(this);

    // Create the controller session before
    // accepting manual driving commands.
    initializeSession();
  }

  // -----------------------------------------
  // CREATE CONTROLLER SESSION
  // -----------------------------------------

  Future<void> initializeSession() async {
    if (connecting || stopping) return;

    connecting = true;
    sessionReady = false;

    if (mounted) {
      setState(() {
        currentCommand = 'STOPPED';
        connectionStatus = 'CONNECTING...';
      });
    }

    try {
      await api.createSession();

      if (!mounted) return;

      setState(() {
        sessionReady = true;
        connectionStatus = 'API CONNECTED';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        sessionReady = false;
        connectionStatus = 'API DISCONNECTED';
      });
    } finally {
      connecting = false;
    }
  }

  // -----------------------------------------
  // APP LIFECYCLE SAFETY
  // -----------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      stopDriving();
    }
  }

  // -----------------------------------------
  // START MANUAL DRIVING
  // -----------------------------------------

  void startDriving(String direction) {
    if (!mounted ||
        !sessionReady ||
        connecting ||
        stopping ||
        heldDirection != null) {
      return;
    }

    commandTimer?.cancel();

    heldDirection = direction;
    commandGeneration++;

    setState(() {
      currentCommand = direction;
    });

    sendDriveCommand();

    commandTimer = Timer.periodic(commandInterval, (_) => sendDriveCommand());
  }

  // -----------------------------------------
  // SEND LIVE DRIVE COMMANDS
  // -----------------------------------------

  Future<void> sendDriveCommand() async {
    if (!sessionReady || heldDirection == null || commandInFlight || stopping) {
      return;
    }

    final direction = heldDirection!;
    final generation = commandGeneration;

    commandInFlight = true;

    try {
      await api.drive(direction: direction, speed: speed.round());

      if (!mounted) return;

      if (generation == commandGeneration && heldDirection == direction) {
        setState(() {
          connectionStatus = 'API CONNECTED';
        });
      }
    } catch (error) {
      if (!mounted) return;

      if (generation == commandGeneration) {
        // Stop sending commands after a failed
        // request, including expired sessions
        // and HTTP 409 responses.
        setState(() {
          connectionStatus = 'API DISCONNECTED';
          sessionReady = false;
        });

        stopDriving();
      }
    } finally {
      commandInFlight = false;
    }
  }

  // -----------------------------------------
  // STOP MANUAL DRIVING
  // -----------------------------------------

  void stopDriving() {
    commandTimer?.cancel();
    commandTimer = null;

    heldDirection = null;
    commandGeneration++;

    if (mounted) {
      setState(() {
        currentCommand = 'STOPPED';
      });
    }

    // Always attempt STOP, even if the app
    // currently reports a disconnected API.
    sendStopCommand();
  }

  // -----------------------------------------
  // SEND STOP TO FASTAPI
  // -----------------------------------------

  Future<void> sendStopCommand() async {
    if (stopping) return;

    stopping = true;

    try {
      await api.stop();

      if (!mounted) return;

      setState(() {
        connectionStatus = 'API CONNECTED';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        connectionStatus = 'API DISCONNECTED';
        sessionReady = false;
      });
    } finally {
      stopping = false;
    }
  }

  // -----------------------------------------
  // RETRY CONTROLLER CONNECTION
  // -----------------------------------------

  Future<void> retryConnection() async {
    if (connecting || stopping || heldDirection != null) {
      return;
    }

    await initializeSession();
  }

  // -----------------------------------------
  // DIRECTION BUTTON
  // -----------------------------------------

  Widget directionButton(IconData icon, String direction) {
    final selected = heldDirection == direction;

    final enabled = sessionReady && !connecting && !stopping;

    return GestureDetector(
      onTapDown: enabled ? (_) => startDriving(direction) : null,
      onTapUp: enabled ? (_) => stopDriving() : null,
      onTapCancel: enabled ? stopDriving : null,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: !enabled
              ? const Color(0xFF1F2937)
              : selected
              ? const Color(0xFF2563EB)
              : const Color(0xFF334155),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          icon,
          size: 38,
          color: enabled ? Colors.white : Colors.white38,
        ),
      ),
    );
  }

  // -----------------------------------------
  // CLEANUP
  // -----------------------------------------

  @override
  void dispose() {
    commandTimer?.cancel();
    commandTimer = null;

    heldDirection = null;
    commandGeneration++;

    WidgetsBinding.instance.removeObserver(this);

    // Best-effort STOP before closing the
    // internally owned HTTP client.
    //
    // The server watchdog is the fallback.
    api.stop().then((_) {}, onError: (Object error) {}).whenComplete(() {
      if (widget.apiClient == null) {
        api.dispose();
      }
    });

    super.dispose();
  }

  // -----------------------------------------
  // SCREEN UI
  // -----------------------------------------

  @override
  Widget build(BuildContext context) {
    final controlsEnabled = sessionReady && !connecting && !stopping;

    return Scaffold(
      appBar: AppBar(title: const Text('Manual Control')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(
              Icons.gamepad_outlined,
              size: 55,
              color: Color(0xFF60A5FA),
            ),

            const SizedBox(height: 16),

            const Text(
              'Manual Driving',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            const Text(
              'Hold a direction button to send '
              'commands to the simulator.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),

            const SizedBox(height: 20),

            // CONNECTION STATUS
            Center(
              child: Text(
                connectionStatus,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: connectionStatus == 'API CONNECTED'
                      ? Colors.greenAccent
                      : connectionStatus == 'API DISCONNECTED'
                      ? Colors.redAccent
                      : Colors.amberAccent,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // RETRY BUTTON
            if (!sessionReady && !connecting)
              Center(
                child: OutlinedButton.icon(
                  onPressed: stopping ? null : retryConnection,
                  icon: const Icon(Icons.refresh),
                  label: const Text('RECONNECT'),
                ),
              ),

            const SizedBox(height: 20),

            // CURRENT COMMAND
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text(
                      'Current Command',
                      style: TextStyle(fontSize: 16),
                    ),

                    const SizedBox(height: 10),

                    Text(
                      currentCommand,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF60A5FA),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            // FORWARD
            Center(child: directionButton(Icons.keyboard_arrow_up, 'FORWARD')),

            const SizedBox(height: 12),

            // LEFT / BACKWARD / RIGHT
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                directionButton(Icons.keyboard_arrow_left, 'LEFT'),

                const SizedBox(width: 12),

                directionButton(Icons.keyboard_arrow_down, 'BACKWARD'),

                const SizedBox(width: 12),

                directionButton(Icons.keyboard_arrow_right, 'RIGHT'),
              ],
            ),

            const SizedBox(height: 30),

            // SPEED CONTROL
            Text(
              'Speed: ${speed.round()}%',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),

            Slider(
              value: speed,
              min: 10,
              max: 100,
              divisions: 18,
              label: '${speed.round()}%',
              onChanged: controlsEnabled
                  ? (value) {
                      setState(() {
                        speed = value;
                      });
                    }
                  : null,
            ),

            const SizedBox(height: 22),

            // STOP BUTTON
            SizedBox(
              height: 60,
              child: ElevatedButton.icon(
                onPressed: stopDriving,
                icon: const Icon(Icons.stop_circle),
                label: const Text(
                  'STOP',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB91C1C),
                  foregroundColor: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              'SIMULATION MODE\n'
              'Commands use a controller session '
              'and increasing sequence numbers. '
              'No physical motors are connected.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
