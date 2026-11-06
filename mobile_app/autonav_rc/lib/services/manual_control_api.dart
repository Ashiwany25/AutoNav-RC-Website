import 'api_config.dart';
import 'authenticated_client.dart';

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ManualControlApi {
  ManualControlApi({
    http.Client? client,
    this.baseUrl = '$autoNavApiOrigin/api/v1',
  }) : _client = client ?? AuthenticatedClient(),
       _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final String baseUrl;

  static const Duration requestTimeout = Duration(seconds: 3);

  Future<void> _queue = Future<void>.value();
  int _generation = 0;
  int _nextSequence = 0;
  String? _sessionId;
  bool _disposed = false;

  String? get sessionId => _sessionId;
  bool get hasSession => _sessionId != null;

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _queue.then((_) {
      if (_disposed) {
        throw StateError('Manual Control API is disposed');
      }
      return operation();
    });

    _queue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );

    return result;
  }

  int _newSequence() => ++_nextSequence;

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

  Future<Map<String, dynamic>> createSession() {
    _generation++;

    return _enqueue(() async {
      _sessionId = null;

      final response = await _client
          .post(
            Uri.parse('$baseUrl/manual/session'),
            headers: {'Content-Type': 'application/json'},
            body: '{}',
          )
          .timeout(requestTimeout);

      final result = _decodeResponse(response);
      final session = result['session_id'];
      final nextSequence = result['next_sequence'];

      if (session is! String || session.isEmpty) {
        throw const FormatException('Invalid session ID');
      }

      if (nextSequence is! int || nextSequence < 1) {
        throw const FormatException('Invalid sequence number');
      }

      _sessionId = session;
      _nextSequence = nextSequence - 1;

      return result;
    });
  }

  Future<Map<String, dynamic>> drive({
    required String direction,
    required int speed,
  }) {
    const allowedDirections = {'FORWARD', 'BACKWARD', 'LEFT', 'RIGHT'};

    if (!allowedDirections.contains(direction)) {
      return Future.error(ArgumentError('Invalid direction: $direction'));
    }

    if (speed < 0 || speed > 100) {
      return Future.error(ArgumentError('Invalid speed: $speed'));
    }

    // Reject missing sessions before sending HTTP.
    // Keep the check inside the queue too, because
    // a session can change while a command is waiting.
    if (_sessionId == null) {
      return Future.error(
        StateError('No controller session. Reconnect first.'),
      );
    }

    final requestGeneration = _generation;

    return _enqueue(() async {
      if (requestGeneration != _generation) {
        throw StateError('Drive canceled by STOP or new session');
      }

      final session = _sessionId;
      if (session == null) {
        throw StateError('No controller session. Reconnect first.');
      }

      final sequence = _newSequence();

      final response = await _client
          .post(
            Uri.parse('$baseUrl/manual/drive'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'direction': direction,
              'speed': speed,
              'sequence': sequence,
              'session_id': session,
            }),
          )
          .timeout(requestTimeout);

      return _decodeResponse(response);
    });
  }

  Future<Map<String, dynamic>> stop() {
    // Invalidate older queued drive commands.
    _generation++;

    return _enqueue(() async {
      final sequence = _newSequence();

      final body = <String, dynamic>{'sequence': sequence};

      // STOP is allowed without a session.
      if (_sessionId != null) {
        body['session_id'] = _sessionId;
      }

      final response = await _client
          .post(
            Uri.parse('$baseUrl/manual/stop'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(requestTimeout);

      return _decodeResponse(response);
    });
  }

  Future<Map<String, dynamic>> status() {
    return _enqueue(() async {
      final response = await _client
          .get(Uri.parse('$baseUrl/manual/status'))
          .timeout(requestTimeout);

      return _decodeResponse(response);
    });
  }

  void dispose() {
    _generation++;
    _disposed = true;

    if (_ownsClient) {
      _client.close();
    }
  }
}
