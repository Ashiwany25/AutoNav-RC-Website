import '../services/api_config.dart';
import '../services/authenticated_client.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class DynamicObstacleScreen extends StatefulWidget {
  const DynamicObstacleScreen({super.key, this.httpClient});

  final http.Client? httpClient;

  @override
  State<DynamicObstacleScreen> createState() => _DynamicObstacleScreenState();
}

class _DynamicObstacleScreenState extends State<DynamicObstacleScreen> {
  static const baseUrl = '$autoNavApiOrigin/api/v1';

  late final http.Client client;
  late final bool ownsClient;

  Timer? timer;

  bool busy = true;
  bool polling = false;
  bool connected = false;

  String state = 'UNKNOWN';
  String message = 'Loading simulation...';

  int? selectedRow;
  int? selectedCol;
  int? robotRow;
  int? robotCol;
  int? goalRow;
  int? goalCol;

  int replanCount = 0;

  List<List<int>> grid = [];
  Set<(int, int)> obstacles = {};
  Set<(int, int)> route = {};

  @override
  void initState() {
    super.initState();

    ownsClient = widget.httpClient == null;
    client = widget.httpClient ?? AuthenticatedClient();

    initialize();

    timer = Timer.periodic(
      const Duration(milliseconds: 700),
      (_) => refreshStatus(),
    );
  }

  Future<Map<String, dynamic>> api(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$baseUrl$path');

    final response =
        await (body == null
                ? client.get(uri)
                : client.post(
                    uri,
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(body),
                  ))
            .timeout(const Duration(seconds: 5));

    final decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid API response');
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['success'] != true) {
      throw Exception(
        decoded['detail'] ?? 'Request failed: ${response.statusCode}',
      );
    }

    return decoded;
  }

  (int, int) point(dynamic data) {
    if (data is! Map || data['row'] is! int || data['col'] is! int) {
      throw const FormatException('Invalid position');
    }

    return (data['row'] as int, data['col'] as int);
  }

  void applyStatus(Map<String, dynamic> data) {
    if (data['simulation'] != true || data['physical_motors_active'] != false) {
      throw const FormatException('Not a verified simulation response');
    }

    final dynamic rawObstacles = data['dynamic_obstacles'];

    final dynamic rawPath = data['path'];

    if (rawObstacles is! List || rawPath is! List) {
      throw const FormatException('Missing simulator map information');
    }

    obstacles = rawObstacles.map(point).toSet();
    route = rawPath.map(point).toSet();

    final position = data['position'];
    final goal = data['goal'];

    if (position != null) {
      final p = point(position);
      robotRow = p.$1;
      robotCol = p.$2;
    } else {
      robotRow = null;
      robotCol = null;
    }

    if (goal != null) {
      final p = point(goal);
      goalRow = p.$1;
      goalCol = p.$2;
    } else {
      goalRow = null;
      goalCol = null;
    }

    state = data['navigation_state']?.toString() ?? 'UNKNOWN';

    replanCount = data['replan_count'] is int ? data['replan_count'] as int : 0;
  }

  Future<void> initialize() async {
    try {
      final saved = await api('/teach/map');

      final rawGrid = saved['grid'];

      if (rawGrid is! List || rawGrid.isEmpty) {
        throw const FormatException('Saved map is missing');
      }

      final parsed = <List<int>>[];

      for (final rawRow in rawGrid) {
        if (rawRow is! List || rawRow.isEmpty) {
          throw const FormatException('Invalid map row');
        }

        final row = <int>[];

        for (final cell in rawRow) {
          if (cell is! int || (cell != -1 && cell != 0 && cell != 1)) {
            throw const FormatException('Invalid map cell');
          }
          row.add(cell);
        }

        parsed.add(row);
      }

      if (parsed.any((row) => row.length != parsed.first.length)) {
        throw const FormatException('Map must be rectangular');
      }

      final status = await api('/teach/navigation/sim/status');

      if (!mounted) return;

      setState(() {
        grid = parsed;
        applyStatus(status);
        connected = true;
        busy = false;
        message = 'Tap a free cell to edit obstacles';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        busy = false;
        connected = false;
        message = 'Connection error: $error';
      });
    }
  }

  Future<void> refreshStatus() async {
    if (busy || polling || grid.isEmpty) return;

    polling = true;

    try {
      final data = await api('/teach/navigation/sim/status');

      if (!mounted) return;

      setState(() {
        applyStatus(data);
        connected = true;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        connected = false;
        message = 'Status unavailable: $error';
      });
    } finally {
      polling = false;
    }
  }

  void selectCell(int row, int col) {
    if (busy || grid[row][col] != 0) {
      setState(() {
        message = 'Only saved free cells can be edited';
      });
      return;
    }

    setState(() {
      selectedRow = row;
      selectedCol = col;
      message = 'Selected cell: ($row, $col)';
    });
  }

  Future<void> changeObstacle(bool occupied) async {
    if (busy || !connected || selectedRow == null || selectedCol == null) {
      return;
    }

    setState(() {
      busy = true;
    });

    try {
      final response = await api(
        '/teach/navigation/sim/obstacle',
        body: {'row': selectedRow, 'col': selectedCol, 'occupied': occupied},
      );

      if (!mounted) return;

      setState(() {
        applyStatus(response);

        final replanned = response['replanned'] == true;

        message = replanned
            ? 'Safe route automatically recalculated'
            : state == 'BLOCKED'
            ? 'Movement blocked for safety'
            : occupied
            ? 'Obstacle added'
            : 'Obstacle removed';

        connected = true;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        message = 'Obstacle update failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  Color colorFor(int row, int col) {
    if (grid[row][col] == -1) {
      return const Color(0xFF64748B);
    }

    if (grid[row][col] == 1) {
      return const Color(0xFF1E293B);
    }

    if (obstacles.contains((row, col))) {
      return const Color(0xFFFB923C);
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

  Widget buildGrid() {
    if (grid.isEmpty) {
      return const Text('No map available');
    }

    final rows = grid.length;
    final cols = grid.first.length;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: AspectRatio(
          aspectRatio: cols / rows,
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: rows * cols,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: 1,
              mainAxisSpacing: 1,
            ),
            itemBuilder: (context, index) {
              final row = index ~/ cols;
              final col = index % cols;

              final selected = selectedRow == row && selectedCol == col;

              return GestureDetector(
                key: Key('obstacle_cell_${row}_$col'),
                onTap: () => selectCell(row, col),
                child: Container(
                  decoration: BoxDecoration(
                    color: colorFor(row, col),
                    border: Border.all(
                      color: selected ? Colors.yellowAccent : Colors.white24,
                      width: selected ? 2.5 : 0.5,
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
    timer?.cancel();

    if (ownsClient) {
      client.close();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = selectedRow != null && selectedCol != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dynamic Obstacles'),
        actions: [
          IconButton(
            tooltip: 'Refresh Obstacles',
            onPressed: busy ? null : initialize,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Simulated Obstacle Editor',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(connected ? 'API CONNECTED' : 'API DISCONNECTED'),
            const SizedBox(height: 8),
            Text('Navigation state: $state'),
            Text('Automatic replans: $replanCount'),
            Text('Dynamic obstacles: ${obstacles.length}'),
            const SizedBox(height: 10),
            Text(message),
            if (busy) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 18),
            buildGrid(),
            const SizedBox(height: 14),
            const Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text('⬜ Free'),
                Text('⬛ Wall'),
                Text('◼ Unknown'),
                Text('🟧 Dynamic'),
                Text('🟩 Robot'),
                Text('🟦 Route'),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              hasSelection
                  ? 'Selected: ($selectedRow, $selectedCol)'
                  : 'Tap a free cell to select it',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: connected && !busy && hasSelection
                  ? () => changeObstacle(true)
                  : null,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('ADD OBSTACLE'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: connected && !busy && hasSelection
                  ? () => changeObstacle(false)
                  : null,
              icon: const Icon(Icons.remove_circle_outline),
              label: const Text('REMOVE OBSTACLE'),
            ),
            const SizedBox(height: 18),
            const Text(
              'SIMULATION ONLY. Obstacles are temporary '
              'and do not modify the saved Teach Mode map. '
              'Unsafe movement must stop when safe '
              'replanning is impossible.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
