import 'package:flutter/material.dart';

import '../../models/connection_state.dart';
import '../../theme.dart';

class ConnectionIndicator extends StatelessWidget {
  final BridgeConnectionState state;

  const ConnectionIndicator({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _tooltip,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, size: 16, color: _color),
            const SizedBox(width: 4),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color get _color {
    switch (state.phase) {
      case ConnectionPhase.connected:
        return AppColors.connected;
      case ConnectionPhase.connecting:
      case ConnectionPhase.handshaking:
      case ConnectionPhase.discovering:
        return AppColors.reconnecting;
      case ConnectionPhase.disconnected:
        return state.isReconnecting
            ? AppColors.reconnecting
            : AppColors.disconnected;
    }
  }

  IconData get _icon {
    switch (state.method) {
      case ConnectionMethod.mdns:
      case ConnectionMethod.lan:
        return Icons.home;
      case ConnectionMethod.tunnel:
        return Icons.language;
      case null:
        return Icons.wifi_off;
    }
  }

  String get _tooltip {
    switch (state.phase) {
      case ConnectionPhase.connected:
        final method = state.method == ConnectionMethod.tunnel ? 'tunnel' : 'LAN';
        return 'Connected ($method) - ${state.host}:${state.port}';
      case ConnectionPhase.connecting:
        return 'Connecting...';
      case ConnectionPhase.handshaking:
        return 'Handshaking...';
      case ConnectionPhase.discovering:
        return 'Discovering bridge...';
      case ConnectionPhase.disconnected:
        if (state.isReconnecting) {
          return 'Reconnecting (attempt ${state.reconnectAttempts})';
        }
        return 'Disconnected';
    }
  }
}
