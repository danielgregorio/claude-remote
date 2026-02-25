import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/app_message.dart';
import '../../models/connection_state.dart';
import '../../providers/connection_provider.dart';
import '../../providers/focused_session_provider.dart';
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
    final pinnedIds = ref.watch(focusedSessionsProvider);
    final activeSessions = ref.watch(activeSessionsProvider);
    final completedSessions = ref.watch(completedSessionsProvider);

    // Separate pinned sessions from the rest
    final pinnedSessions =
        sessions.where((s) => pinnedIds.contains(s.id)).toList();
    final unpinnedActive =
        activeSessions.where((s) => !pinnedIds.contains(s.id)).toList();
    final unpinnedCompleted =
        completedSessions.where((s) => !pinnedIds.contains(s.id)).toList();

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
                  if (pinnedSessions.isNotEmpty) ...[
                    _SectionHeader(title: 'Pinned', count: pinnedSessions.length),
                    const SizedBox(height: 8),
                    ...pinnedSessions.map((s) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SessionCard(
                            session: s,
                            isPinned: true,
                            onTap: () => context.push('/session/${s.id}'),
                            onTogglePin: () => ref
                                .read(focusedSessionsProvider.notifier)
                                .toggle(s.id),
                          ),
                        )),
                    const SizedBox(height: 16),
                  ],
                  if (unpinnedActive.isNotEmpty) ...[
                    _SectionHeader(title: 'Active', count: unpinnedActive.length),
                    const SizedBox(height: 8),
                    ...unpinnedActive.map((s) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SessionCard(
                            session: s,
                            onTap: () => context.push('/session/${s.id}'),
                            onTogglePin: () => ref
                                .read(focusedSessionsProvider.notifier)
                                .toggle(s.id),
                          ),
                        )),
                    const SizedBox(height: 16),
                  ],
                  if (unpinnedCompleted.isNotEmpty) ...[
                    _SectionHeader(
                        title: 'Completed', count: unpinnedCompleted.length),
                    const SizedBox(height: 8),
                    ...unpinnedCompleted.map((s) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SessionCard(
                            session: s,
                            onTap: () => context.push('/session/${s.id}'),
                            onTogglePin: () => ref
                                .read(focusedSessionsProvider.notifier)
                                .toggle(s.id),
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
