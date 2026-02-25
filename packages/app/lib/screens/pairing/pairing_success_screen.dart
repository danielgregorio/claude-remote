import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/connection_provider.dart';
import '../../theme.dart';

class PairingSuccessScreen extends ConsumerWidget {
  final String bridgeName;

  const PairingSuccessScreen({super.key, required this.bridgeName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 80,
                  color: AppColors.connected,
                ),
                const SizedBox(height: 24),
                Text(
                  'Paired!',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'Connected to $bridgeName',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white70,
                      ),
                ),
                const SizedBox(height: 48),
                FilledButton(
                  onPressed: () {
                    // Start connection and navigate to dashboard
                    ref.read(connectionManagerProvider).connect();
                    context.go('/');
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: Text('Continue to Dashboard'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
