import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'authenticated_client.dart';

class NavigationHeartbeatService {
  NavigationHeartbeatService({
    http.Client? client,
    String? baseUrl,
    this.interval = const Duration(milliseconds: 500),
    this.requestTimeout = const Duration(milliseconds: 1500),
    this.onConnectionLost,
    this.onTerminalStatus,
  }) : _client = client ?? AuthenticatedClient(),
       _ownsClient = client == null,
       _baseUrl = baseUrl ?? autoNavApiOrigin;

  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;

  final Duration interval;
  final Duration requestTimeout;
  final void Function(String reason)? onConnectionLost;
  final void Function(Map<String, dynamic> status)? onTerminalStatus;

  Timer? _timer;
  bool _active = false;
  bool _sending = false;
  bool _disposed = false;
  int _generation = 0;

  String? lastFailure;
  Map<String, dynamic>? _terminalStatus;

  bool get isActive => _active;

  Future<bool> sendOnce() async {
    if (_disposed || _sending) return false;

    _sending = true;
    lastFailure = null;
    _terminalStatus = null;

    try {
      final response = await _client
          .post(Uri.parse('$_baseUrl/api/v1/teach/navigation/sim/heartbeat'))
          .timeout(requestTimeout);

      if (response.statusCode == 200) {
        return true;
      }

      if (response.statusCode == 409) {
        final statusResponse = await _client
            .get(Uri.parse('$_baseUrl/api/v1/teach/navigation/sim/status'))
            .timeout(requestTimeout);

        if (statusResponse.statusCode == 200) {
          final decoded = jsonDecode(statusResponse.body);

          if (decoded is Map<String, dynamic> &&
              decoded['simulation'] == true &&
              decoded['physical_motors_active'] == false) {
            final state = decoded['navigation_state'];

            if (state == 'ARRIVED' ||
                state == 'STOPPED' ||
                state == 'BLOCKED' ||
                state == 'CONNECTION_LOST') {
              _terminalStatus = decoded;
              return true;
            }
          }
        }
      }

      var detail = response.body;

      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['detail'] != null) {
          detail = decoded['detail'].toString();
        }
      } catch (_) {}

      if (detail.length > 180) {
        detail = detail.substring(0, 180);
      }

      lastFailure = 'Heartbeat HTTP ${response.statusCode}: $detail';

      debugPrint('AutoNav: $lastFailure');
      return false;
    } on TimeoutException {
      lastFailure = 'Heartbeat request timed out.';
      debugPrint('AutoNav: $lastFailure');
      return false;
    } catch (error) {
      lastFailure = 'Heartbeat request error: $error';
      debugPrint('AutoNav: $lastFailure');
      return false;
    } finally {
      _sending = false;
    }
  }

  void _finishTerminalStatus() {
    final status = _terminalStatus;
    stop();

    if (status != null) {
      onTerminalStatus?.call(status);
    }
  }

  Future<bool> start() async {
    if (_disposed) return false;

    stop();
    _active = true;

    final generation = _generation;
    final success = await sendOnce();

    if (!_active || generation != _generation) {
      return false;
    }

    if (_terminalStatus != null) {
      _finishTerminalStatus();
      return false;
    }

    if (!success) {
      _fail(lastFailure ?? 'Initial heartbeat failed.');
      return false;
    }

    _timer = Timer.periodic(interval, (_) => _tick(generation));

    return true;
  }

  Future<void> _tick(int generation) async {
    if (!_active || _disposed || generation != _generation || _sending) {
      return;
    }

    final success = await sendOnce();

    if (!_active || generation != _generation) {
      return;
    }

    if (_terminalStatus != null) {
      _finishTerminalStatus();
      return;
    }

    if (!success) {
      _fail(lastFailure ?? 'Controller heartbeat lost.');
    }
  }

  void _fail(String reason) {
    stop();
    onConnectionLost?.call(reason);
  }

  void stop() {
    _active = false;
    _generation++;
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    if (_disposed) return;

    stop();
    _disposed = true;

    if (_ownsClient) {
      _client.close();
    }
  }
}
