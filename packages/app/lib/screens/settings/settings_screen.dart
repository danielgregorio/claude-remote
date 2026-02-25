import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/connection_provider.dart';
import '../../theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connState = ref.watch(currentConnectionStateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Bridge info
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bridge Connection',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(
                    label: 'Status',
                    value: connState.isConnected ? 'Connected' : 'Disconnected',
                    color: connState.isConnected
                        ? AppColors.connected
                        : AppColors.disconnected,
                  ),
                  if (connState.host != null)
                    _InfoRow(
                      label: 'Host',
                      value: '${connState.host}:${connState.port}',
                    ),
                  if (connState.method != null)
                    _InfoRow(
                      label: 'Method',
                      value: connState.method!.name.toUpperCase(),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Actions
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: const Text('Reconnect'),
                  onTap: () {
                    ref.read(connectionManagerProvider).disconnect();
                    ref.read(connectionManagerProvider).connect();
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.link_off, color: AppColors.error),
                  title: const Text('Unpair',
                      style: TextStyle(color: AppColors.error)),
                  subtitle: const Text('Remove pairing and all stored keys'),
                  onTap: () => _confirmUnpair(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Version
          Center(
            child: Text(
              'Claude Remote v0.1.0',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.white38),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmUnpair(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unpair?'),
        content: const Text(
          'This will remove all stored keys and disconnect from the bridge. '
          'You will need to scan a new QR code to pair again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref.read(connectionManagerProvider).disconnect();
              await ref.read(keyStoreProvider).clear();
              if (context.mounted) {
                context.go('/pair');
              }
            },
            child: const Text('Unpair'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _InfoRow({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54)),
          Text(
            value,
            style: TextStyle(color: color ?? Colors.white),
          ),
        ],
      ),
    );
  }
}
