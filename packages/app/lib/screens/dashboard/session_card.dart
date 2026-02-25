import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/session_info.dart';
import '../../theme.dart';
import '../../widgets/status_badge.dart';

class SessionCard extends StatelessWidget {
  final SessionInfo session;
  final VoidCallback? onTap;
  final VoidCallback? onTogglePin;
  final bool isPinned;

  const SessionCard({
    super.key,
    required this.session,
    this.onTap,
    this.onTogglePin,
    this.isPinned = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: isPinned
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppColors.active.withAlpha(100), width: 1),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: () {
          HapticFeedback.mediumImpact();
          onTogglePin?.call();
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _statusDot(session.status),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isPinned) ...[
                          Icon(Icons.push_pin, size: 14, color: AppColors.active),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            session.name,
                            style: Theme.of(context).textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        StatusBadge(
                          label: _statusLabel(session.status),
                          color: _statusColor(session.status),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatDuration(session.durationSeconds),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.white54),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      session.cwd,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.white38),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusDot(SessionStatus status) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _statusColor(status),
      ),
    );
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

  String _statusLabel(SessionStatus status) {
    switch (status) {
      case SessionStatus.active:
        return 'active';
      case SessionStatus.waitingInput:
        return 'needs input';
      case SessionStatus.waitingPermission:
        return 'needs permission';
      case SessionStatus.idle:
        return 'idle';
      case SessionStatus.completed:
        return 'completed';
      case SessionStatus.error:
        return 'error';
    }
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m';
    return '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m';
  }
}
