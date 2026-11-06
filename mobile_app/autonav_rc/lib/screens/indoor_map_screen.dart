import '../services/api_config.dart';
import '../services/authenticated_client.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class IndoorMapScreen extends StatefulWidget {
  const IndoorMapScreen({super.key, this.httpClient});

  // Optional client for automated tests.
  final http.Client? httpClient;

  @override
  State<IndoorMapScreen> createState() => _IndoorMapScreenState();
}

class _IndoorMapScreenState extends State<IndoorMapScreen> {
  // Development API through USB ADB reverse.
  static const String baseUrl = autoNavApiOrigin;

  static const Color freeColor = Color(0xFFE8EFF5);
  static const Color obstacleColor = Color(0xFF526174);
  static const Color robotColor = Color(0xFF24946C);
  static const Color goalColor = Color(0xFF287BD5);
  static const Color routeColor = Color(0xFFF59E0B);

  late final http.Client client;

  List<List<int>> grid = [];
  List<(int, int)> plannedPath = [];

  int robotRow = 0;
  int robotCol = 0;

  int? goalRow;
  int? goalCol;

  int currentStep = 0;
  int totalSteps = 0;
  int remainingSteps = 0;

  int refreshCount = 0;
  int responseGeneration = 0;

  double resolution = 0.1;

  String mapName = 'Indoor Map';
  String navigationState = 'IDLE';
  String? errorMessage;

  bool loading = true;
  bool refreshing = false;
  bool commandBusy = false;

  // Step 40.10: Track verified API connection.
  bool apiConnected = false;

  Timer? refreshTimer;

  @override
  void initState() {
    super.initState();

    client = widget.httpClient ?? AuthenticatedClient();

    refreshData(forceMap: true);

    refreshTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => refreshData(),
    );
  }

  @override
  void dispose() {
    refreshTimer?.cancel();

    // An injected test client belongs to its caller.
    if (widget.httpClient == null) {
      client.close();
    }

    super.dispose();
  }

  // --------------------------------------------------
  // HTTP API REQUESTS
  // --------------------------------------------------

  Future<Map<String, dynamic>> requestJson(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final uri = Uri.parse('$baseUrl$path');

    late http.Response response;

    if (method == 'GET') {
      response = await client.get(uri).timeout(const Duration(seconds: 5));
    } else if (method == 'POST') {
      response = await client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body ?? {}),
          )
          .timeout(const Duration(seconds: 5));
    } else {
      throw Exception('Unsupported HTTP method: $method');
    }

    dynamic decoded;

    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const FormatException('Server returned invalid JSON');
    }

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected API response format');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'HTTP ${response.statusCode}: '
        '${decoded['detail'] ?? decoded['message'] ?? 'Request failed'}',
      );
    }

    if (decoded['success'] == false) {
      throw Exception(
        '${decoded['message'] ?? decoded['detail'] ?? 'Request rejected'}',
      );
    }

    return decoded;
  }

  // --------------------------------------------------
  // VALIDATE OCCUPANCY GRID
  // --------------------------------------------------

  List<List<int>> parseGrid(dynamic rawGrid) {
    if (rawGrid is! List || rawGrid.isEmpty) {
      throw const FormatException('Missing occupancy grid');
    }

    final result = <List<int>>[];

    for (final rawRow in rawGrid) {
      if (rawRow is! List) {
        throw const FormatException('Invalid grid row');
      }

      result.add(
        rawRow.map<int>((cell) {
          if (cell is! int || (cell != 0 && cell != 1)) {
            throw const FormatException('Invalid occupancy cell');
          }

          return cell;
        }).toList(),
      );
    }

    final cols = result.first.length;

    if (cols == 0 || result.any((row) => row.length != cols)) {
      throw const FormatException('Invalid grid dimensions');
    }

    return result;
  }

  // --------------------------------------------------
  // VALIDATE ROBOT POSITION
  // --------------------------------------------------

  (int, int) parsePosition(dynamic data) {
    if (data is! Map) {
      throw const FormatException('Missing position');
    }

    final row = data['row'];
    final col = data['col'];

    if (row is! int || col is! int) {
      throw const FormatException('Invalid position coordinates');
    }

    return (row, col);
  }

  // --------------------------------------------------
  // VALIDATE A* ROUTE
  // --------------------------------------------------

  List<(int, int)> parsePath(dynamic data) {
    if (data is! List || data.isEmpty) {
      throw const FormatException('No valid A* route returned');
    }

    return data.map<(int, int)>((point) => parsePosition(point)).toList();
  }

  // --------------------------------------------------
  // REFRESH MAP AND NAVIGATION STATUS
  // --------------------------------------------------

  Future<void> refreshData({bool forceMap = false}) async {
    if (refreshing || commandBusy) return;

    refreshing = true;

    // Older responses must not overwrite results
    // after a newer START or STOP command.
    final requestGeneration = responseGeneration;

    try {
      refreshCount++;

      List<List<int>>? latestGrid;
      String? latestMapName;
      double? latestResolution;
      (int, int)? mapPosition;

      // Refresh map every third polling cycle.
      if (forceMap || grid.isEmpty || refreshCount % 3 == 0) {
        final mapData = await requestJson('GET', '/api/v1/maps/current');

        latestGrid = parseGrid(mapData['grid']);

        if (mapData['height'] != latestGrid.length ||
            mapData['width'] != latestGrid.first.length) {
          throw const FormatException('Map dimensions do not match');
        }

        latestMapName = mapData['map_name']?.toString();

        if (mapData['resolution'] is num) {
          latestResolution = (mapData['resolution'] as num).toDouble();
        }

        mapPosition = parsePosition(mapData['robot_position']);
      }

      // Navigation status is authoritative
      // for the simulated robot position.
      final statusData = await requestJson('GET', '/api/v1/navigation/status');

      final latestState =
          statusData['navigation_state']?.toString() ?? 'UNKNOWN';

      (int, int)? statusPosition;

      if (statusData['position'] != null) {
        statusPosition = parsePosition(statusData['position']);
      }

      final latestPosition = statusPosition ?? mapPosition;

      // Ignore data from an outdated poll.
      if (!mounted || commandBusy || requestGeneration != responseGeneration) {
        return;
      }

      setState(() {
        if (latestGrid != null) {
          grid = latestGrid;
        }

        if (latestMapName != null) {
          mapName = latestMapName;
        }

        if (latestResolution != null) {
          resolution = latestResolution;
        }

        if (latestPosition != null) {
          robotRow = latestPosition.$1;
          robotCol = latestPosition.$2;
        }

        navigationState = latestState;

        currentStep = statusData['current_step'] is int
            ? statusData['current_step'] as int
            : 0;

        totalSteps = statusData['total_steps'] is int
            ? statusData['total_steps'] as int
            : 0;

        remainingSteps = statusData['remaining_steps'] is int
            ? statusData['remaining_steps'] as int
            : 0;

        // Clear inactive routes.
        if (latestState == 'STOPPED' ||
            latestState == 'ARRIVED' ||
            latestState == 'BLOCKED') {
          plannedPath = [];
        }

        // Validate a previously selected destination.
        if (goalRow != null && goalCol != null && grid.isNotEmpty) {
          final invalidGoal =
              goalRow! < 0 ||
              goalCol! < 0 ||
              goalRow! >= grid.length ||
              goalCol! >= grid.first.length ||
              grid[goalRow!][goalCol!] != 0;

          if (invalidGoal) {
            goalRow = null;
            goalCol = null;
            plannedPath = [];
          }
        }

        // Step 40.10: Both API queries succeeded.
        apiConnected = true;

        errorMessage = null;
        loading = false;
      });
    } catch (error) {
      // Ignore errors from outdated requests.
      if (!mounted || commandBusy || requestGeneration != responseGeneration) {
        return;
      }

      setState(() {
        // Step 40.10: Mark connection unavailable.
        apiConnected = false;

        errorMessage = 'Connection error: $error';

        loading = false;

        // Avoid showing an unverified active route.
        plannedPath = [];
      });
    } finally {
      refreshing = false;
    }
  }

  // --------------------------------------------------
  // USER MESSAGES
  // --------------------------------------------------

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  // --------------------------------------------------
  // SELECT DESTINATION
  // --------------------------------------------------

  void selectDestination(int row, int col) {
    if (commandBusy || grid.isEmpty) return;

    if (grid[row][col] != 0) {
      showMessage('Obstacle cell cannot be selected.');
      return;
    }

    setState(() {
      goalRow = row;
      goalCol = col;

      // Clear the old route when the goal changes.
      plannedPath = [];
    });

    showMessage('Destination selected: ($row, $col)');
  }

  // --------------------------------------------------
  // START / UPDATE NAVIGATION
  // --------------------------------------------------

  Future<void> startNavigation() async {
    if (!apiConnected || commandBusy || goalRow == null || goalCol == null) {
      return;
    }

    final targetRow = goalRow!;
    final targetCol = goalCol!;

    // Invalidate previously started status polls.
    responseGeneration++;

    setState(() {
      commandBusy = true;
      errorMessage = null;
    });

    try {
      final payload = {
        'goal': {'row': targetRow, 'col': targetCol},
      };

      // Python performs A* planning and applies
      // the existing SafetyController clearance.
      final planResponse = await requestJson(
        'POST',
        '/api/v1/navigation/plan',
        payload,
      );

      final newPath = parsePath(planResponse['path']);

      // START only after successful planning.
      await requestJson('POST', '/api/v1/navigation/start', payload);

      if (!mounted) return;

      setState(() {
        plannedPath = newPath;
        navigationState = 'NAVIGATING';

        currentStep = 0;
        totalSteps = newPath.length - 1;
        remainingSteps = totalSteps;
      });

      showMessage(
        'Navigation started: '
        '${newPath.length - 1} steps',
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        plannedPath = [];
      });

      showMessage('Navigation failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          commandBusy = false;
        });

        // Refresh state after the command.
        await refreshData();
      }
    }
  }

  // --------------------------------------------------
  // STOP SIMULATED ROBOT
  // --------------------------------------------------

  Future<void> stopNavigation() async {
    if (commandBusy) return;

    // Invalidate old status polls.
    responseGeneration++;

    setState(() {
      commandBusy = true;
    });

    try {
      await requestJson('POST', '/api/v1/navigation/stop');

      if (!mounted) return;

      setState(() {
        navigationState = 'STOPPED';

        plannedPath = [];

        goalRow = null;
        goalCol = null;

        remainingSteps = 0;
      });

      showMessage('Simulated robot stopped.');
    } catch (error) {
      // A failed STOP is unconfirmed.
      showMessage('STOP request failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          commandBusy = false;
        });

        await refreshData();
      }
    }
  }

  // --------------------------------------------------
  // REMAINING A* ROUTE
  // --------------------------------------------------

  Set<(int, int)> get remainingRoute {
    if (plannedPath.isEmpty) {
      return {};
    }

    final robotIndex = plannedPath.indexOf((robotRow, robotCol));

    if (robotIndex >= 0) {
      return plannedPath.skip(robotIndex + 1).toSet();
    }

    // The route may be out of sync with the robot.
    // Display the last planned route with a warning.
    return plannedPath.toSet();
  }

  Color cellColor(int row, int col, Set<(int, int)> routeCells) {
    if (row == robotRow && col == robotCol) {
      return robotColor;
    }

    if (grid[row][col] == 1) {
      return obstacleColor;
    }

    if (row == goalRow && col == goalCol) {
      return goalColor;
    }

    if (routeCells.contains((row, col))) {
      return routeColor;
    }

    return freeColor;
  }

  // --------------------------------------------------
  // BUILD THE INDOOR MAP
  // --------------------------------------------------

  Widget buildGrid() {
    final rows = grid.length;
    final cols = grid.first.length;

    final routeCells = remainingRoute;

    return AspectRatio(
      aspectRatio: cols / rows,
      child: GridView.builder(
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rows * cols,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
        ),
        itemBuilder: (context, index) {
          final row = index ~/ cols;
          final col = index % cols;

          final isRobot = row == robotRow && col == robotCol;

          final isGoal = row == goalRow && col == goalCol;

          return GestureDetector(
            onTap: () => selectDestination(row, col),
            child: Container(
              decoration: BoxDecoration(
                color: cellColor(row, col, routeCells),
                border: Border.all(color: Colors.white, width: 0.4),
              ),
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  isRobot
                      ? 'R'
                      : isGoal
                      ? 'G'
                      : '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // --------------------------------------------------
  // MAP LEGEND
  // --------------------------------------------------

  Widget legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  // --------------------------------------------------
  // CONNECTION INDICATOR
  // --------------------------------------------------

  Widget buildConnectionIndicator() {
    final connected = apiConnected;

    return Row(
      children: [
        Icon(
          connected ? Icons.wifi : Icons.wifi_off,
          color: connected ? Colors.greenAccent : Colors.redAccent,
          size: 20,
        ),

        const SizedBox(width: 8),

        Text(
          connected ? 'API CONNECTED' : 'API DISCONNECTED',
          style: TextStyle(
            color: connected ? Colors.greenAccent : Colors.redAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------
  // BUILD SCREEN
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isNavigating = navigationState == 'NAVIGATING';

    final routeOutOfSync =
        plannedPath.isNotEmpty && !plannedPath.contains((robotRow, robotCol));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Indoor Map'),
        actions: [
          IconButton(
            tooltip: 'Refresh Map',
            onPressed: commandBusy ? null : () => refreshData(forceMap: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              mapName,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            Text(
              'Resolution: $resolution m/cell',
              style: const TextStyle(color: Colors.white70),
            ),

            const SizedBox(height: 16),

            // Step 40.10: Connection status.
            buildConnectionIndicator(),

            const SizedBox(height: 12),

            Text(
              'Navigation status: $navigationState',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 16),

            if (errorMessage != null) ...[
              Text(
                errorMessage!,
                style: const TextStyle(color: Colors.redAccent),
              ),

              const SizedBox(height: 8),

              OutlinedButton.icon(
                onPressed: () => refreshData(forceMap: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),

              const SizedBox(height: 16),
            ],

            if (loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (grid.isNotEmpty) ...[
              buildGrid(),

              const SizedBox(height: 18),

              Wrap(
                alignment: WrapAlignment.center,
                spacing: 14,
                runSpacing: 10,
                children: [
                  legendItem(robotColor, 'Robot'),
                  legendItem(goalColor, 'Goal'),
                  legendItem(routeColor, 'A* Path'),
                  legendItem(obstacleColor, 'Obstacle'),
                  legendItem(freeColor, 'Free'),
                ],
              ),

              const SizedBox(height: 20),

              Text(
                'Robot: ($robotRow, $robotCol)',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                goalRow == null
                    ? 'No destination selected'
                    : 'Destination: ($goalRow, $goalCol)',
              ),

              const SizedBox(height: 12),

              Text(
                'A* path positions: '
                '${plannedPath.length}',
              ),

              if (routeOutOfSync) ...[
                const SizedBox(height: 6),

                const Text(
                  'Showing last planned route. '
                  'Current robot route is not verified.',
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                ),
              ],

              const SizedBox(height: 12),

              Text(
                'Progress: $currentStep / '
                '$totalSteps steps',
              ),

              const SizedBox(height: 6),

              LinearProgressIndicator(
                value: totalSteps > 0
                    ? (currentStep / totalSteps).clamp(0.0, 1.0)
                    : 0.0,
                minHeight: 7,
                borderRadius: BorderRadius.circular(8),
              ),

              const SizedBox(height: 8),

              Text('Remaining steps: $remainingSteps'),

              const SizedBox(height: 24),

              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  // Step 40.10:
                  // Disable START while disconnected.
                  onPressed: !apiConnected || commandBusy || goalRow == null
                      ? null
                      : startNavigation,
                  icon: const Icon(Icons.navigation_outlined),
                  label: Text(
                    commandBusy
                        ? 'Processing...'
                        : isNavigating
                        ? 'Update Destination'
                        : 'Start Navigation',
                  ),
                ),
              ),

              const SizedBox(height: 12),

              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  // STOP is not disabled merely because
                  // the last connection check failed.
                  onPressed: commandBusy ? null : stopNavigation,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('STOP SIMULATED ROBOT'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB91C1C),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 20),

            const Text(
              'Simulation mode only. '
              'A* planning uses the Python '
              'SafetyController. '
              'Physical motors are not connected.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
