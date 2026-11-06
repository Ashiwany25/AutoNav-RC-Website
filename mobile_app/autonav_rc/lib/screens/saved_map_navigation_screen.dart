import '../services/api_config.dart';
import '../services/authenticated_client.dart';
import '../services/navigation_heartbeat_service.dart';
import 'dynamic_obstacle_screen.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class SavedMapNavigationScreen extends StatefulWidget {
  const SavedMapNavigationScreen({super.key, this.httpClient});

  final http.Client? httpClient;

  @override
  State<SavedMapNavigationScreen> createState() =>
      _SavedMapNavigationScreenState();
}

class _SavedMapNavigationScreenState extends State<SavedMapNavigationScreen>
    with WidgetsBindingObserver {
  static const String baseUrl = '$autoNavApiOrigin/api/v1';

  late final http.Client client;
  late final bool ownsClient;
  NavigationHeartbeatService? heartbeatService;

  List<List<int>> grid = [];
  List<(int, int)> plannedPath = [];
  List<(int, int)> livePath = [];

  int? robotRow;
  int? robotCol;
  int? goalRow;
  int? goalCol;

  double exploration = 0;
  int currentStep = 0;
  int totalSteps = 0;
  int remainingSteps = 0;

  bool loading = true;
  bool planning = false;
  bool commandBusy = false;
  bool stopBusy = false;
  bool connected = false;

  String navigationState = 'IDLE';
  String message = 'Loading saved Teach Mode map...';
  String? errorMessage;

  Timer? statusTimer;
  int responseGeneration = 0;
  bool statusPolling = false;
  bool pendingRetarget = false;

  bool get isNavigating => navigationState == 'NAVIGATING';

  bool get isProcessing => loading || planning || commandBusy || stopBusy;

  @override
  void initState() {
    super.initState();

    ownsClient = widget.httpClient == null;
    client = widget.httpClient ?? AuthenticatedClient();

    WidgetsBinding.instance.addObserver(this);

    if (autoNavWifiMode) {
      heartbeatService = NavigationHeartbeatService(
        client: client,
        baseUrl: autoNavApiOrigin,
        onConnectionLost: handleHeartbeatLoss,
        onTerminalStatus: handleTerminalHeartbeatStatus,
      );
    }

    loadSavedMap();
  }

  void handleTerminalHeartbeatStatus(Map<String, dynamic> status) {
    if (!mounted || stopBusy) return;

    if (navigationState == 'STOPPED' &&
        status['navigation_state'] == 'NAVIGATING') {
      return;
    }

    stopPolling();
    responseGeneration++;

    try {
      setState(() {
        applySimulationStatus(status);
        connected = true;
        errorMessage = navigationState == 'CONNECTION_LOST'
            ? 'Controller heartbeat expired. '
                  'Simulation stopped.'
            : null;

        message = navigationState == 'ARRIVED'
            ? 'Destination reached successfully.'
            : 'Simulation state: $navigationState';
      });
    } catch (error) {
      handleHeartbeatLoss('Unable to verify terminal navigation state: $error');
    }
  }

  void handleHeartbeatLoss(String reason) {
    if (!mounted || !isNavigating) return;

    heartbeatService?.stop();
    stopPolling();
    responseGeneration++;

    final generation = responseGeneration;

    unawaited(reconcileHeartbeatFailure(reason, generation));
  }

  Future<void> reconcileHeartbeatFailure(String reason, int generation) async {
    try {
      final status = await request('/teach/navigation/sim/status');

      if (!mounted || generation != responseGeneration) {
        return;
      }

      final state = status['navigation_state'];

      if (state == 'ARRIVED' ||
          state == 'STOPPED' ||
          state == 'BLOCKED' ||
          state == 'CONNECTION_LOST') {
        setState(() {
          applySimulationStatus(status);
          connected = true;
          errorMessage = state == 'CONNECTION_LOST'
              ? 'Heartbeat expired. Simulation stopped.'
              : null;
          message = state == 'ARRIVED'
              ? 'Destination reached successfully.'
              : 'Simulation state: $state';
        });
        return;
      }
    } catch (_) {
      // The server state could not be verified.
    }

    if (!mounted || generation != responseGeneration) {
      return;
    }

    setState(() {
      connected = false;
      navigationState = 'CONNECTION_UNVERIFIED';
      errorMessage = '$reason Server STOP is not yet confirmed.';
      message =
          'Heartbeat failed. Movement is not confirmed. '
          'Navigation will not restart automatically.';
    });
  }

  Future<void> sendBackgroundStop() async {
    // Separate client so this request is not
    // cancelled when the screen is disposed.
    final stopClient = AuthenticatedClient();

    try {
      final response = await stopClient
          .post(Uri.parse('$baseUrl/teach/navigation/sim/stop'))
          .timeout(const Duration(seconds: 2));

      if (response.statusCode != 200) {
        debugPrint(
          'AutoNav background STOP returned '
          'HTTP ${response.statusCode}',
        );
      }
    } catch (error) {
      debugPrint('AutoNav background STOP unconfirmed: $error');
    } finally {
      stopClient.close();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      if (heartbeatService?.isActive ?? false) {
        // Attempt STOP immediately when the app
        // leaves the foreground. The backend watchdog
        // remains the fallback if Wi-Fi is unavailable.
        unawaited(sendBackgroundStop());
        heartbeatService?.stop();
        stopPolling();
        responseGeneration++;

        if (mounted) {
          setState(() {
            connected = false;
            navigationState = 'CONNECTION_UNVERIFIED';
            errorMessage =
                'App left the foreground. '
                'Heartbeat stopped; server STOP '
                'is not yet confirmed.';
            message =
                'Reopen navigation and verify '
                'the simulator before starting again.';
          });
        }
      }
    }
  }

  Future<Map<String, dynamic>> request(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');

    final http.Response response;

    if (body == null) {
      response = await client.get(uri).timeout(const Duration(seconds: 5));
    } else {
      response = await client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 5));
    }

    final dynamic decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid AutoNav API response');
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['success'] != true) {
      throw Exception(
        decoded['detail'] ??
            decoded['message'] ??
            'HTTP ${response.statusCode}',
      );
    }

    return decoded;
  }

  (int, int) parsePosition(dynamic value) {
    if (value is! Map || value['row'] is! int || value['col'] is! int) {
      throw const FormatException('Invalid position from API');
    }

    return (value['row'] as int, value['col'] as int);
  }

  List<(int, int)> parsePath(dynamic raw) {
    if (raw is! List) {
      throw const FormatException('Invalid navigation path');
    }

    return raw.map(parsePosition).toList();
  }

  bool inBounds(int row, int col) {
    return grid.isNotEmpty &&
        row >= 0 &&
        col >= 0 &&
        row < grid.length &&
        col < grid.first.length;
  }

  void applySavedMap(Map<String, dynamic> data) {
    final raw = data['grid'];

    if (raw is! List || raw.isEmpty) {
      throw const FormatException('Saved occupancy grid is missing');
    }

    final parsed = <List<int>>[];

    for (final rawRow in raw) {
      if (rawRow is! List || rawRow.isEmpty) {
        throw const FormatException('Invalid map row');
      }

      final row = <int>[];

      for (final cell in rawRow) {
        if (cell is! int || (cell != -1 && cell != 0 && cell != 1)) {
          throw const FormatException('Invalid occupancy cell');
        }

        row.add(cell);
      }

      parsed.add(row);
    }

    final width = parsed.first.length;

    if (parsed.any((row) => row.length != width) ||
        data['width'] != width ||
        data['height'] != parsed.length) {
      throw const FormatException('Saved map dimensions are invalid');
    }

    grid = parsed;

    final rawPosition = data['robot_position'];

    if (rawPosition != null) {
      final position = parsePosition(rawPosition);
      robotRow = position.$1;
      robotCol = position.$2;
    } else {
      robotRow = null;
      robotCol = null;
    }

    final progress = data['exploration_percentage'];

    exploration = progress is num ? progress.toDouble() : 0;

    plannedPath = [];
    livePath = [];
    pendingRetarget = false;
    goalRow = null;
    goalCol = null;
  }

  void applySimulationStatus(Map<String, dynamic> response) {
    final state = response['navigation_state'];

    if (state is! String ||
        response['simulation'] != true ||
        response['physical_motors_active'] != false) {
      throw const FormatException('Unexpected simulator status');
    }

    final position = response['position'];

    if (position != null) {
      final point = parsePosition(position);

      if (!inBounds(point.$1, point.$2) || grid[point.$1][point.$2] != 0) {
        throw const FormatException('Simulator position is not on free space');
      }

      robotRow = point.$1;
      robotCol = point.$2;
    }

    final rawGoal = response['goal'];

    if (rawGoal != null && goalRow == null && goalCol == null) {
      final point = parsePosition(rawGoal);
      goalRow = point.$1;
      goalCol = point.$2;
    }

    final route = parsePath(response['path']);

    for (final point in route) {
      if (!inBounds(point.$1, point.$2) || grid[point.$1][point.$2] != 0) {
        throw const FormatException('Simulator route crosses unsafe cells');
      }
    }

    navigationState = state;
    livePath = route;

    currentStep = response['current_step'] is int
        ? response['current_step'] as int
        : 0;

    totalSteps = response['total_steps'] is int
        ? response['total_steps'] as int
        : 0;

    remainingSteps = response['remaining_steps'] is int
        ? response['remaining_steps'] as int
        : 0;

    if (!isNavigating) {
      stopPolling();
      heartbeatService?.stop();
    }
  }

  void startPolling() {
    statusTimer?.cancel();

    statusTimer = Timer.periodic(
      const Duration(milliseconds: 700),
      (_) => refreshSimulationStatus(),
    );
  }

  void stopPolling() {
    statusTimer?.cancel();
    statusTimer = null;
  }

  Future<void> refreshSimulationStatus() async {
    if (statusPolling || stopBusy || commandBusy) {
      return;
    }

    statusPolling = true;
    final generation = responseGeneration;

    try {
      final response = await request('/teach/navigation/sim/status');

      if (!mounted || generation != responseGeneration) {
        return;
      }

      setState(() {
        applySimulationStatus(response);
      });
    } catch (error) {
      if (!mounted || generation != responseGeneration) {
        return;
      }

      stopPolling();
      heartbeatService?.stop();

      setState(() {
        connected = false;
        navigationState = 'CONNECTION_UNVERIFIED';
        errorMessage = 'Could not verify simulator position: $error';
        message =
            'Simulator status unavailable. '
            'Movement is not confirmed.';
      });
    } finally {
      statusPolling = false;
    }
  }

  Future<void> loadSavedMap() async {
    if (isProcessing && !loading) return;

    responseGeneration++;
    stopPolling();
    heartbeatService?.stop();

    setState(() {
      loading = true;
      errorMessage = null;
    });

    try {
      final data = await request('/teach/map');

      if (!mounted) return;

      setState(() {
        applySavedMap(data);
        connected = true;
        loading = false;
        navigationState = 'IDLE';
        message = 'Saved Teach Mode map loaded';
      });

      // Recover an active simulator after reopening
      // the screen. Older mock servers may not provide
      // this optional simulator endpoint.
      try {
        final status = await request('/teach/navigation/sim/status');

        if (!mounted) return;

        setState(() {
          applySimulationStatus(status);
        });

        if (isNavigating) {
          startPolling();
        }
      } catch (_) {
        // Map preview still works without status recovery.
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        connected = false;
        grid = [];
        plannedPath = [];
        livePath = [];
        loading = false;
        message = 'Unable to load saved map';
        errorMessage = '$error';
      });
    }
  }

  void selectDestination(int row, int col) {
    if (isProcessing || grid.isEmpty) return;

    if (grid[row][col] != 0) {
      setState(() {
        goalRow = null;
        goalCol = null;
        plannedPath = [];
        errorMessage =
            'Select an explored FREE cell. '
            'Unknown cells and obstacles are blocked.';
      });
      return;
    }

    setState(() {
      goalRow = row;
      goalCol = col;
      plannedPath = [];
      pendingRetarget = isNavigating;
      errorMessage = null;
      message = 'Destination selected: ($row, $col)';
    });
  }

  Future<void> planRoute() async {
    if (!connected ||
        isProcessing ||
        goalRow == null ||
        goalCol == null ||
        isNavigating) {
      return;
    }

    final row = goalRow!;
    final col = goalCol!;

    setState(() {
      planning = true;
      errorMessage = null;
      plannedPath = [];
      message = 'Checking safe A* route...';
    });

    try {
      final response = await request(
        '/teach/navigation/plan',
        body: {
          'goal': {'row': row, 'col': col},
        },
      );

      if (response['map_source'] != 'saved_teach_mode' ||
          response['execution_started'] != false) {
        throw const FormatException('Unexpected route planner response');
      }

      final route = parsePath(response['path']);

      if (route.isEmpty || route.last != (row, col)) {
        throw const FormatException('Planner returned an invalid destination');
      }

      for (final point in route) {
        if (!inBounds(point.$1, point.$2) || grid[point.$1][point.$2] != 0) {
          throw const FormatException(
            'Route crosses unknown or occupied cells',
          );
        }
      }

      if (!mounted) return;

      setState(() {
        plannedPath = route;
        message =
            'Safe A* route found: '
            '${route.length - 1} steps';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        plannedPath = [];
        errorMessage = 'Route unavailable: $error';
        message = 'Route planning rejected';
      });
    } finally {
      if (mounted) {
        setState(() {
          planning = false;
        });
      }
    }
  }

  Future<void> startSimulation() async {
    if (!connected ||
        isProcessing ||
        goalRow == null ||
        goalCol == null ||
        (plannedPath.isEmpty && !pendingRetarget)) {
      return;
    }

    final row = goalRow!;
    final col = goalCol!;

    responseGeneration++;

    setState(() {
      commandBusy = true;
      errorMessage = null;
      message = 'Starting virtual robot...';
    });

    try {
      final response = await request(
        '/teach/navigation/sim/start',
        body: {
          'goal': {'row': row, 'col': col},
        },
      );

      if (!mounted) return;

      setState(() {
        applySimulationStatus(response);
        pendingRetarget = false;
        plannedPath = [];
        message = isNavigating
            ? 'Virtual robot is moving'
            : 'Virtual robot state: $navigationState';
      });

      if (isNavigating) {
        var heartbeatReady = true;

        if (heartbeatService != null && !heartbeatService!.isActive) {
          heartbeatReady = await heartbeatService!.start();
        }

        if (!mounted) return;

        if (heartbeatReady && navigationState == 'NAVIGATING') {
          startPolling();
        }
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        errorMessage = 'Simulation start failed: $error';
        message = 'Virtual robot did not start';
      });
    } finally {
      if (mounted) {
        setState(() {
          commandBusy = false;
        });
      }
    }
  }

  Future<void> stopSimulation() async {
    if (stopBusy) return;

    // Invalidate pending status responses from earlier navigation.
    responseGeneration++;
    final stopGeneration = responseGeneration;

    stopPolling();
    heartbeatService?.stop();

    setState(() {
      stopBusy = true;
      errorMessage = null;
      message = 'Sending STOP to simulator...';
    });

    try {
      final response = await request('/teach/navigation/sim/stop', body: {});

      if (!mounted || stopGeneration != responseGeneration) {
        return;
      }

      // Never display STOPPED based only on a button press.
      // The backend STOP response must confirm the state.
      if (response['navigation_state'] != 'STOPPED') {
        throw StateError(
          'Backend STOP returned '
          '${response['navigation_state']}',
        );
      }

      setState(() {
        applySimulationStatus(response);
        plannedPath = [];
        livePath = [];
        pendingRetarget = false;
        connected = true;
        errorMessage = null;
        message = 'Virtual robot stopped';
      });

      // Independently read the authoritative backend state.
      final verified = await request('/teach/navigation/sim/status');

      if (!mounted || stopGeneration != responseGeneration) {
        return;
      }

      if (verified['navigation_state'] != 'STOPPED') {
        throw StateError(
          'Backend status after STOP is '
          '${verified['navigation_state']}',
        );
      }

      setState(() {
        applySimulationStatus(verified);
        plannedPath = [];
        livePath = [];
        connected = true;
        errorMessage = null;
        message = 'Virtual robot stopped';
      });
    } catch (error) {
      if (!mounted || stopGeneration != responseGeneration) {
        return;
      }

      setState(() {
        errorMessage = 'STOP verification failed: $error';
        message = 'Check server status before restarting';
      });
    } finally {
      if (mounted && stopGeneration == responseGeneration) {
        setState(() {
          stopBusy = false;
        });
      }
    }
  }

  Color cellColor(int row, int col, Set<(int, int)> route) {
    if (grid[row][col] == -1) {
      return const Color(0xFF64748B);
    }

    if (grid[row][col] == 1) {
      return const Color(0xFF1E293B);
    }

    if (row == robotRow && col == robotCol) {
      return const Color(0xFF22C55E);
    }

    if (row == goalRow && col == goalCol) {
      return const Color(0xFFEF4444);
    }

    if (route.contains((row, col))) {
      return const Color(0xFF3B82F6);
    }

    return const Color(0xFFE2E8F0);
  }

  Widget buildMap() {
    if (grid.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('No saved map available.')),
      );
    }

    final rows = grid.length;
    final cols = grid.first.length;

    final route = (isNavigating ? livePath : plannedPath).toSet();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: AspectRatio(
          aspectRatio: cols / rows,
          child: GridView.builder(
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: 1,
              mainAxisSpacing: 1,
            ),
            itemCount: rows * cols,
            itemBuilder: (context, index) {
              final row = index ~/ cols;
              final col = index % cols;

              final isRobot = row == robotRow && col == robotCol;

              final isGoal = row == goalRow && col == goalCol;

              return GestureDetector(
                key: Key('saved_cell_${row}_$col'),
                onTap: () => selectDestination(row, col),
                child: Container(
                  color: cellColor(row, col, route),
                  alignment: Alignment.center,
                  child: FittedBox(
                    child: Text(
                      isRobot
                          ? 'R'
                          : isGoal
                          ? 'G'
                          : '',
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    responseGeneration++;
    stopPolling();

    WidgetsBinding.instance.removeObserver(this);

    if (heartbeatService?.isActive ?? false) {
      unawaited(sendBackgroundStop());
    }

    heartbeatService?.dispose();

    if (ownsClient) {
      client.close();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleRoute = isNavigating ? livePath : plannedPath;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Map Navigation'),
        actions: [
          IconButton(
            tooltip: 'Dynamic Obstacles',
            icon: const Icon(Icons.warning_amber_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const DynamicObstacleScreen(),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Reload Saved Map',
            onPressed: isProcessing ? null : loadSavedMap,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Tap-to-Plan Navigation',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose a safe explored destination '
              'and simulate a virtual journey.',
            ),
            const SizedBox(height: 14),
            Text(
              connected ? 'API CONNECTED' : 'API DISCONNECTED',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: connected ? Colors.greenAccent : Colors.orangeAccent,
              ),
            ),
            const SizedBox(height: 10),
            Text(message),
            if (errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                errorMessage!,
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            ],
            if (isProcessing) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 16),
            Text(
              'Exploration: '
              '${exploration.toStringAsFixed(1)}%',
            ),
            const SizedBox(height: 8),
            Text('Navigation state: $navigationState'),
            const SizedBox(height: 8),
            Text(
              robotRow == null
                  ? 'Robot position unavailable'
                  : 'Robot: ($robotRow, $robotCol)',
            ),
            const SizedBox(height: 12),
            if (!loading) buildMap(),
            const SizedBox(height: 16),
            const Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text('◼ Unknown'),
                Text('⬜ Free'),
                Text('⬛ Wall'),
                Text('🟩 Robot'),
                Text('🟥 Goal'),
                Text('🟦 Route'),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              goalRow == null
                  ? 'No destination selected'
                  : 'Selected destination: '
                        '($goalRow, $goalCol)',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Planned route: '
              '${visibleRoute.isEmpty ? 0 : visibleRoute.length - 1} steps',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text('Progress: $currentStep / $totalSteps steps'),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: totalSteps > 0
                  ? (currentStep / totalSteps).clamp(0.0, 1.0)
                  : 0,
            ),
            const SizedBox(height: 8),
            Text('Remaining steps: $remainingSteps'),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed:
                    connected &&
                        !isProcessing &&
                        !isNavigating &&
                        goalRow != null
                    ? planRoute
                    : null,
                icon: const Icon(Icons.route),
                label: const Text('PLAN SAFE ROUTE'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed:
                    connected &&
                        !isProcessing &&
                        (plannedPath.isNotEmpty || pendingRetarget) &&
                        goalRow != null
                    ? startSimulation
                    : null,
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  pendingRetarget ? 'UPDATE DESTINATION' : 'START SIMULATION',
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: stopBusy ? null : stopSimulation,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('STOP SIMULATION'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB91C1C),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'SIMULATION ONLY: Route planning and '
              'movement use the saved occupancy map. '
              'No physical motors are controlled. '
              'Unknown space is always blocked.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
