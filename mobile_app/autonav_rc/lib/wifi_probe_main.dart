import 'package:flutter/material.dart';

import 'services/local_https_client.dart';

void main() {
  runApp(const HttpsProbeApp());
}

class HttpsProbeApp extends StatelessWidget {
  const HttpsProbeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const HttpsProbeScreen(),
    );
  }
}

class HttpsProbeScreen extends StatefulWidget {
  const HttpsProbeScreen({super.key});

  @override
  State<HttpsProbeScreen> createState() => _HttpsProbeScreenState();
}

class _HttpsProbeScreenState extends State<HttpsProbeScreen> {
  bool testing = false;
  String result = 'Press TEST WI-FI CONNECTION';

  Future<void> testHttps() async {
    if (testing) return;

    setState(() {
      testing = true;
      result = 'Checking encrypted connection...';
    });

    final client = LocalHttpsClient(
      allowedHost: '192.168.1.13',
      allowedPort: 8443,
    );

    try {
      final health = await client
          .get(Uri.parse('https://192.168.1.13:8443/api/v1/health'))
          .timeout(const Duration(seconds: 8));

      final pairing = await client
          .get(Uri.parse('https://192.168.1.13:8443/api/v1/pairing/status'))
          .timeout(const Duration(seconds: 8));

      final protected = await client
          .get(Uri.parse('https://192.168.1.13:8443/api/v1/robot/status'))
          .timeout(const Duration(seconds: 8));

      if (!mounted) return;

      final passed =
          health.statusCode == 200 &&
          pairing.statusCode == 200 &&
          protected.statusCode == 401;

      setState(() {
        result = passed
            ? 'WI-FI HTTPS CONNECTION SUCCESSFUL\n\n'
                  'Certificate verified\n'
                  'Health: ${health.statusCode}\n'
                  'Pairing: ${pairing.statusCode}\n'
                  'Unauthorized access: ${protected.statusCode}\n\n'
                  'Encrypted API connection verified.'
            : 'HTTPS CHECK INCOMPLETE\n\n'
                  'Health: ${health.statusCode}\n'
                  'Pairing: ${pairing.statusCode}\n'
                  'Protected endpoint: ${protected.statusCode}';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        result = 'HTTPS CONNECTION FAILED\n\n$error';
      });
    } finally {
      client.close();

      if (mounted) {
        setState(() {
          testing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AutoNav Wi-Fi Test')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.lock_outline, size: 72, color: Colors.green),
              const SizedBox(height: 20),
              const Text(
                'Secure Connection Verification',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Tests certificate verification '
                'and protected API access. '
                'No motor commands are sent.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: testing ? null : testHttps,
                icon: const Icon(Icons.security),
                label: const Text('TEST WI-FI CONNECTION'),
              ),
              const SizedBox(height: 24),
              if (testing) const LinearProgressIndicator(),
              const SizedBox(height: 12),
              SelectableText(result, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
