import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ManualControlApi {
  ManualControlApi({
    http.Client? client,
    this.baseUrl = 'http://127.0.0.1:8000/api/v1',
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final String baseUrl;

  // Keeps requests ordered within this API instance.
  Future<void> _queue = Future<void>.value();

  // A STOP invalidates older commands that
  // are still waiting in the local queue.
  int _generation = 0;

  bool _disposed = false;

  static const Duration requestTimeout = Duration(seconds: 3);

  // ------------------------------------------
  // SERIALIZE HTTP OPERATIONS
  // ------------------------------------------

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _queue.then((_) {
      if (_disposed) {
        throw StateError('Manual Control API is disposed');
      }

      return operation();
    });

    // Keep the queue usable even if an
    // individual HTTP request fails.
    _queue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );

    return result;
  }

  // ------------------------------------------
  // MANUAL DRIVE
  // ------------------------------------------

  Future<Map<String, dynamic>> drive({
    required String direction,
    required int speed,
  }) async {
    const allowedDirections = {'FORWARD', 'BACKWARD', 'LEFT', 'RIGHT'};

    if (!allowedDirections.contains(direction)) {
      throw ArgumentError('Invalid direction: $direction');
    }

    if (speed < 0 || speed > 100) {
      throw ArgumentError('Speed must be between 0 and 100');
    }

    final requestGeneration = _generation;

    return _enqueue(() async {
      // Do not send an old command if STOP
      // was requested while it was queued.
      if (requestGeneration != _generation) {
        throw StateError('Drive command canceled by STOP');
      }

      final response = await _client
          .post(
            Uri.parse('$baseUrl/manual/drive'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'direction': direction, 'speed': speed}),
          )
          .timeout(requestTimeout);

      return _decodeResponse(response);
    });
  }

  // ------------------------------------------
  // MANUAL STOP
  // ------------------------------------------

  Future<Map<String, dynamic>> stop() {
    // Invalidate older queued drive commands
    // immediately, before waiting for HTTP.
    _generation++;

    return _enqueue(() async {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/manual/stop'),
            headers: {'Content-Type': 'application/json'},
            body: '{}',
          )
          .timeout(requestTimeout);

      return _decodeResponse(response);
    });
  }

  // ------------------------------------------
  // MANUAL STATUS
  // ------------------------------------------

  Future<Map<String, dynamic>> status() {
    return _enqueue(() async {
      final response = await _client
          .get(Uri.parse('$baseUrl/manual/status'))
          .timeout(requestTimeout);

      return _decodeResponse(response);
    });
  }

  // ------------------------------------------
  // RESPONSE VALIDATION
  // ------------------------------------------

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final dynamic decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid API response');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'API error ${response.statusCode}: '
        '${decoded['detail'] ?? response.body}',
      );
    }

    if (decoded['success'] != true) {
      throw Exception('API did not confirm success');
    }

    return decoded;
  }

  // ------------------------------------------
  // CLEANUP
  // ------------------------------------------

  void dispose() {
    _generation++;
    _disposed = true;

    // Close only clients created by this service.
    if (_ownsClient) {
      _client.close();
    }
  }
}
