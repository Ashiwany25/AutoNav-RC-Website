import 'screens/pairing_screen.dart';

import 'package:flutter/material.dart';

import 'screens/indoor_map_screen.dart';
import 'screens/manual_control_screen.dart';
import 'screens/teach_mode_screen.dart';
import 'screens/saved_map_navigation_screen.dart';

void main() {
  runApp(const AutoNavApp());
}

class AutoNavApp extends StatelessWidget {
  const AutoNavApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AutoNav RC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF111827),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          brightness: Brightness.dark,
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  static const Color cardColor = Color(0xFF1E293B);

  static const Color accentColor = Color(0xFF60A5FA);

  void openScreen(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  void showFeatureMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void handleControl(BuildContext context, String title) {
    switch (title) {
      case 'Manual Control':
        openScreen(context, const ManualControlScreen());
        break;

      case 'Indoor Map':
        openScreen(context, const IndoorMapScreen());
        break;

      case 'Teach Mode':
        openScreen(context, const TeachModeScreen());
        break;

      case 'Saved Map Navigation':
        openScreen(context, const SavedMapNavigationScreen());
        break;

      case 'Settings':
        openScreen(context, const PairingScreen());
        break;

      default:
        showFeatureMessage(
          context,
          '$title will be implemented '
          'in the next stages.',
        );
    }
  }

  Widget controlCard(BuildContext context, String title, IconData icon) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => handleControl(context, title),
      child: Ink(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 36, color: accentColor),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Robot Status',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Chip(
                label: Text('DEMO MODE'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          SizedBox(height: 20),
          Wrap(
            spacing: 20,
            runSpacing: 18,
            children: [
              _StatusItem(
                icon: Icons.wifi_off,
                label: 'Connection',
                value: 'Not connected',
              ),
              _StatusItem(
                icon: Icons.battery_unknown,
                label: 'Battery',
                value: 'Unavailable',
              ),
            ],
          ),
          SizedBox(height: 20),
          _StatusItem(
            icon: Icons.directions_car_outlined,
            label: 'Operating Mode',
            value: 'Idle',
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        title: const Text(
          'AutoNav RC',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PairingScreen()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Welcome to AutoNav RC',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Your indoor autonomous companion',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 24),
            buildStatusCard(),
            const SizedBox(height: 28),
            const Text(
              'Quick Controls',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.25,
              children: [
                controlCard(context, 'Manual Control', Icons.gamepad_outlined),
                controlCard(context, 'Indoor Map', Icons.map_outlined),
                controlCard(context, 'Auto Navigation', Icons.route_outlined),
                controlCard(context, 'Teach Mode', Icons.map_outlined),
                controlCard(context, 'Saved Map Navigation', Icons.route),
                controlCard(context, 'Settings', Icons.settings_outlined),
              ],
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 60,
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  showFeatureMessage(
                    context,
                    'Emergency STOP is not connected '
                    'to a physical robot yet.',
                  );
                },
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text(
                  'EMERGENCY STOP',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB91C1C),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Demo interface only. '
              'Hardware control is not active.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusItem extends StatelessWidget {
  const _StatusItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color(0xFF60A5FA), size: 25),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                softWrap: true,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
