import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/app_message.dart';
import '../../models/connection_state.dart';
import '../../providers/connection_provider.dart';
import '../../providers/sessions_provider.dart';
import '../../widgets/status_badge.dart';
import 'connection_indicator.dart';
import 'session_card.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    // Connect and request sessions on first load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final manager = ref.read(connectionManagerProvider);
      manager.connect();
    });
  }

  void _refreshSessions() {
    try {
      ref.read(connectionManagerProvider).send(ListSessionsMessage());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final connState = ref.watch(currentConnectionStateProvider);
    final sessions = ref.watch(sessionsProvider);
    final activeSessions = ref.watch(activeSessionsProvider);
    final completedSessions = ref.watch(completedSessionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Claude Remote'),
        actions: [
          ConnectionIndicator(state: connState),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refreshSessions(),
        child: sessions.isEmpty
            ? _buildEmptyState(context, connState)
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (activeSessions.isNotEmpty) ...[
                    _SectionHeader(title: 'Active', count: activeSessions.length),
                    const SizedBox(height: 8),
                    ...activeSessions.map((s) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SessionCard(
                            session: s,
                            onTap: () => context.push('/session/${s.id}'),
                          ),
                        )),
                    const SizedBox(height: 16),
                  ],
                  if (completedSessions.isNotEmpty) ...[
                    _SectionHeader(
                        title: 'Completed', count: completedSessions.length),
                    const SizedBox(height: 8),
                    ...completedSessions.map((s) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SessionCard(
                            session: s,
                            onTap: () => context.push('/session/${s.id}'),
                          ),
                        )),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, BridgeConnectionState connState) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            connState.isConnected ? Icons.inbox_outlined : Icons.wifi_off,
            size: 64,
            color: Colors.white30,
          ),
          const SizedBox(height: 16),
          Text(
            connState.isConnected
                ? 'No active sessions'
                : 'Connecting to bridge...',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white54,
                ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Colors.white54,
              ),
        ),
        const SizedBox(width: 8),
        StatusBadge(label: '$count', color: Colors.white24),
      ],
    );
  }
}
