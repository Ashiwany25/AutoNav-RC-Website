import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class LocalHttpsClient extends http.BaseClient {
  LocalHttpsClient({
    required this.allowedHost,
    this.allowedPort = 8443,
    this.certificateAsset = 'assets/certs/autonav-cert.pem',
  });

  final String allowedHost;
  final int allowedPort;
  final String certificateAsset;

  Future<http.Client>? _clientFuture;
  bool _closed = false;

  bool isAllowedUrl(Uri uri) {
    return uri.scheme == 'https' &&
        uri.host == allowedHost &&
        uri.port == allowedPort &&
        uri.userInfo.isEmpty;
  }

  Future<http.Client> _initializeClient() async {
    final certificate = await rootBundle.load(certificateAsset);

    final bytes = certificate.buffer.asUint8List(
      certificate.offsetInBytes,
      certificate.lengthInBytes,
    );

    final context = SecurityContext(withTrustedRoots: false);

    context.setTrustedCertificatesBytes(bytes);

    final ioClient = HttpClient(context: context);

    // Deliberately do not set
    // badCertificateCallback.
    //
    // A failed TLS validation must cause
    // the request to fail.
    ioClient.connectionTimeout = const Duration(seconds: 5);

    if (_closed) {
      ioClient.close(force: true);
      throw StateError('HTTPS client is closed.');
    }

    return IOClient(ioClient);
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) {
      throw StateError('HTTPS client is closed.');
    }

    if (!isAllowedUrl(request.url)) {
      throw http.ClientException(
        'Blocked: only the configured '
        'AutoNav HTTPS server is permitted.',
        request.url,
      );
    }

    final client = await (_clientFuture ??= _initializeClient());

    if (_closed) {
      throw StateError('HTTPS client is closed.');
    }

    return client.send(request);
  }

  @override
  void close() {
    if (_closed) return;

    _closed = true;

    final future = _clientFuture;

    if (future != null) {
      unawaited(
        future.then(
          (client) => client.close(),
          onError: (Object error, StackTrace stack) {},
        ),
      );
    }
  }
}
