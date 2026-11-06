import 'package:flutter/material.dart';

import 'authenticated_client.dart';

class PairingRecoveryBanner extends StatelessWidget {
  const PairingRecoveryBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: PairingRecoveryState.pairingRequired,
      builder: (context, pairingRequired, _) {
        return Stack(
          children: [
            child,
            if (pairingRequired)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: SafeArea(
                  top: false,
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(12),
                    color: const Color(0xFF7F1D1D),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.phonelink_erase,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Pairing expired. '
                              'Open Settings → '
                              'Pair AutoNav RC '
                              'to reconnect.',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Dismiss warning',
                            onPressed: () {
                              PairingRecoveryState.clear();
                            },
                            icon: const Icon(Icons.close, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
