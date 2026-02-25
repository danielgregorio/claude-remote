import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_message.dart';
import '../../models/session_info.dart';
import '../../providers/connection_provider.dart';
import '../../providers/session_detail_provider.dart';
import '../../providers/sessions_provider.dart';
import '../../theme.dart';
import 'permission_dialog.dart';
import 'input_bar.dart';

class SessionDetailScreen extends ConsumerStatefulWidget {
  final String sessionId;

  const SessionDetailScreen({super.key, required this.sessionId});

  @override
  ConsumerState<SessionDetailScreen> createState() =>
      _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen> {
  final _outputLines = <String>[];
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Subscribe to this session
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        ref.read(connectionManagerProvider).send(
              SubscribeMessage(sessionId: widget.sessionId),
            );
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    // Unsubscribe
    try {
      ref.read(connectionManagerProvider).send(
            UnsubscribeMessage(sessionId: widget.sessionId),
          );
    } catch (_) {}
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(sessionsProvider);
    final session = sessions
        .cast<SessionInfo?>()
        .firstWhere((s) => s?.id == widget.sessionId, orElse: () => null);

    // Listen to output
    ref.listen(sessionOutputProvider(widget.sessionId), (prev, next) {
      next.whenData((line) {
        setState(() => _outputLines.add(line));
        // Auto-scroll to bottom
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
            );
          }
        });
      });
    });

    // Listen to permission requests
    ref.listen(permissionRequestProvider(widget.sessionId), (prev, next) {
      next.whenData((request) {
        showDialog(
          context: context,
          builder: (_) => PermissionDialog(
            request: request,
            onApprove: () => _respond(true, request.requestId),
            onReject: () => _respond(false, request.requestId),
          ),
        );
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(session?.name ?? 'Session'),
        actions: [
          if (session != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Chip(
                label: Text(
                  session.status.name,
                  style: const TextStyle(fontSize: 12),
                ),
                backgroundColor: _statusColor(session.status),
                side: BorderSide.none,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _outputLines.isEmpty
                ? const Center(
                    child: Text(
                      'Waiting for output...',
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _outputLines.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          _outputLines[index],
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (session?.status == SessionStatus.waitingInput ||
              session?.status == SessionStatus.active)
            InputBar(
              onSubmit: (text) {
                ref.read(connectionManagerProvider).send(
                      InputMessage(
                        sessionId: widget.sessionId,
                        text: text,
                      ),
                    );
              },
            ),
        ],
      ),
    );
  }

  void _respond(bool approve, String requestId) {
    final message = approve
        ? ApproveMessage(
            sessionId: widget.sessionId, requestId: requestId)
        : RejectMessage(
            sessionId: widget.sessionId, requestId: requestId);
    ref.read(connectionManagerProvider).send(message);
  }

  Color _statusColor(SessionStatus status) {
    switch (status) {
      case SessionStatus.active:
        return AppColors.active;
      case SessionStatus.waitingInput:
      case SessionStatus.waitingPermission:
        return AppColors.waiting;
      case SessionStatus.completed:
      case SessionStatus.idle:
        return AppColors.completed;
      case SessionStatus.error:
        return AppColors.error;
    }
  }
}
