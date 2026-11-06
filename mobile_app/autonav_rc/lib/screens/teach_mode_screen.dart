import '../services/api_config.dart';
import '../services/authenticated_client.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class TeachModeScreen extends StatefulWidget {
  const TeachModeScreen({super.key, this.httpClient});

  final http.Client? httpClient;

  @override
  State<TeachModeScreen> createState() => _TeachModeScreenState();
}

class _TeachModeScreenState extends State<TeachModeScreen> {
  late final http.Client client;
  late final bool ownsClient;

  static const String baseUrl = '$autoNavApiOrigin/api/v1/teach';

  bool busy = false;
  bool active = false;
  bool connected = false;

  String message = 'Connecting...';

  double exploration = 0;
  int observationCount = 0;
  int uniqueCells = 0;
  int lastNewCells = 0;

  List<List<int>> grid = [];

  int? robotRow;
  int? robotCol;

  @override
  void initState() {
    super.initState();

    ownsClient = widget.httpClient == null;
    client = widget.httpClient ?? AuthenticatedClient();

    refresh();
  }

  Future<Map<String, dynamic>> request(
    String endpoint, {
    Map<String, dynamic>? body,
    bool post = false,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');

    final response =
        await (post
                ? client.post(
                    uri,
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(body ?? {}),
                  )
                : client.get(uri))
            .timeout(const Duration(seconds: 5));

    final decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid Teach Mode response');
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['success'] != true) {
      throw Exception(
        decoded['detail'] ?? 'API request failed: ${response.statusCode}',
      );
    }

    return decoded;
  }

  void applyMap(Map<String, dynamic> data) {
    final source = data['map'] is Map
        ? Map<String, dynamic>.from(data['map'] as Map)
        : data;

    final rawGrid = source['grid'];

    if (rawGrid is! List) {
      throw const FormatException('Occupancy grid missing');
    }

    final parsed = rawGrid.map((row) {
      if (row is! List) {
        throw const FormatException('Invalid map row');
      }

      return row.map((cell) {
        if (cell is! int || !{-1, 0, 1}.contains(cell)) {
          throw const FormatException('Invalid occupancy cell');
        }
        return cell;
      }).toList();
    }).toList();

    if (parsed.isEmpty ||
        parsed.first.isEmpty ||
        parsed.any((row) => row.length != parsed.first.length)) {
      throw const FormatException('Invalid grid dimensions');
    }

    grid = parsed;

    final progress = source['exploration_percentage'];
    if (progress is num) {
      exploration = progress.toDouble();
    }

    final count = source['observation_count'];
    if (count is int) {
      observationCount = count;
    }

    uniqueCells = grid.expand((row) => row).where((cell) => cell != -1).length;

    final position = source['robot_position'];

    if (position is Map) {
      robotRow = position['row'] as int?;
      robotCol = position['col'] as int?;
    } else {
      robotRow = null;
      robotCol = null;
    }
  }

  Future<void> refresh() async {
    if (busy) return;

    setState(() => busy = true);

    try {
      final status = await request('/status');
      final hasMap = status['map_available'] == true;

      Map<String, dynamic>? mapData;

      if (hasMap) {
        mapData = await request('/map');
      }

      if (!mounted) return;

      setState(() {
        connected = true;
        active = status['teach_active'] == true;

        if (mapData != null) {
          applyMap(mapData);
        } else {
          grid = [];
          exploration = 0;
          observationCount = 0;
          uniqueCells = 0;
          robotRow = null;
          robotCol = null;
        }

        message = active
            ? 'Mapping session active'
            : hasMap
            ? 'Map available'
            : 'Ready to start mapping';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        connected = false;
        message = 'Connection error: $error';
      });
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> runAction(
    String endpoint,
    String successMessage, {
    Map<String, dynamic>? body,
  }) async {
    if (busy) return;

    setState(() => busy = true);

    try {
      final result = await request(endpoint, post: true, body: body);

      Map<String, dynamic>? mapData;

      if (endpoint == '/finish') {
        mapData = await request('/map');
      } else if (result['map'] is Map) {
        mapData = result;
      }

      if (!mounted) return;

      setState(() {
        connected = true;

        if (endpoint == '/start') {
          active = true;
          lastNewCells = 0;
        } else if (endpoint == '/finish') {
          active = false;
        }

        if (mapData != null) {
          applyMap(mapData);
        }

        if (result['new_cells'] is int) {
          lastNewCells = result['new_cells'] as int;
        }

        message = successMessage;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        message = 'Operation failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Widget mapView() {
    if (grid.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text(
            'No map yet. Start Teach Mode.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final height = grid.length;
    final width = grid.first.length;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: AspectRatio(
          aspectRatio: width / height,
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: width * height,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: width,
              crossAxisSpacing: 1,
              mainAxisSpacing: 1,
            ),
            itemBuilder: (context, index) {
              final row = index ~/ width;
              final col = index % width;

              final isRobot = row == robotRow && col == robotCol;

              Color color;

              switch (grid[row][col]) {
                case 0:
                  color = const Color(0xFFDCE6F0);
                  break;
                case 1:
                  color = const Color(0xFF334155);
                  break;
                default:
                  color = const Color(0xFF64748B);
              }

              return Container(
                key: Key('teach_cell_${row}_$col'),
                color: isRobot ? const Color(0xFF22C55E) : color,
                child: isRobot
                    ? const FittedBox(
                        child: Icon(Icons.navigation, color: Colors.black),
                      )
                    : null,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget actionButton(
    String title,
    VoidCallback? onPressed, {
    IconData icon = Icons.play_arrow,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(title),
      ),
    );
  }

  Widget moveButton(String direction, IconData icon) {
    return SizedBox(
      width: 78,
      height: 56,
      child: ElevatedButton(
        onPressed: !busy && connected && active
            ? () => runAction(
                '/move',
                'Moved $direction',
                body: {'direction': direction, 'steps': 1},
              )
            : null,
        style: ElevatedButton.styleFrom(padding: EdgeInsets.zero),
        child: Icon(icon, size: 28),
      ),
    );
  }

  @override
  void dispose() {
    if (ownsClient) {
      client.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teach Mode'),
        actions: [
          IconButton(
            tooltip: 'Refresh Teach Mode',
            onPressed: busy ? null : refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Indoor Mapping',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Explore the simulated environment '
              'and discover map cells.',
            ),
            const SizedBox(height: 14),
            Text(
              connected ? 'API CONNECTED' : 'API DISCONNECTED',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: connected ? Colors.greenAccent : Colors.orangeAccent,
              ),
            ),
            const SizedBox(height: 8),
            Text(message),
            if (busy) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      'Exploration: '
                      '${exploration.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: (exploration / 100).clamp(0.0, 1.0),
                    ),
                    const SizedBox(height: 10),
                    Text('Unique explored cells: $uniqueCells'),
                    Text('Total observations: $observationCount'),
                    Text('New cells in last scan: $lastNewCells'),
                    Text(active ? 'Status: MAPPING' : 'Status: NOT MAPPING'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            mapView(),
            const SizedBox(height: 12),
            const Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text('⬜ Free'),
                Text('⬛ Occupied'),
                Text('◼ Unknown'),
                Text('🟩 Robot'),
              ],
            ),
            const SizedBox(height: 24),
            actionButton(
              'START MAPPING',
              !busy && connected && !active
                  ? () => runAction('/start', 'Teach Mode started')
                  : null,
              icon: Icons.play_arrow,
            ),
            const SizedBox(height: 16),
            const Text(
              'Explore using the arrow controls',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Center(child: moveButton('UP', Icons.keyboard_arrow_up)),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                moveButton('LEFT', Icons.keyboard_arrow_left),
                const SizedBox(width: 12),
                moveButton('DOWN', Icons.keyboard_arrow_down),
                const SizedBox(width: 12),
                moveButton('RIGHT', Icons.keyboard_arrow_right),
              ],
            ),
            const SizedBox(height: 18),
            actionButton(
              'SCAN ENVIRONMENT',
              !busy && connected && active
                  ? () => runAction('/observe', 'Simulated scan completed')
                  : null,
              icon: Icons.sensors,
            ),
            const SizedBox(height: 8),
            actionButton(
              'SAVE MAP',
              !busy && connected && active
                  ? () => runAction('/finish', 'Map saved successfully')
                  : null,
              icon: Icons.save,
            ),
            const SizedBox(height: 18),
            const Text(
              'SIMULATION ONLY: Arrow buttons move '
              'a virtual exploration position. '
              'No physical motors are activated.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}
