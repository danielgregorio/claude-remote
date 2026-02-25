import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bridge_message.dart';
import '../models/session_info.dart';
import 'connection_provider.dart';

/// Maintains the list of sessions, updated from bridge messages.
class SessionsNotifier extends StateNotifier<List<SessionInfo>> {
  final Ref _ref;
  StreamSubscription<BridgeMessage>? _sub;

  SessionsNotifier(this._ref) : super([]) {
    _listen();
  }

  void _listen() {
    final manager = _ref.read(connectionManagerProvider);
    _sub = manager.messages.listen(_onMessage);
  }

  void _onMessage(BridgeMessage message) {
    if (message is SessionListMessage) {
      state = message.sessions;
    } else if (message is SessionStatusMessage) {
      state = [
        for (final s in state)
          if (s.id == message.sessionId)
            s.copyWith(status: message.status)
          else
            s,
      ];
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final sessionsProvider =
    StateNotifierProvider<SessionsNotifier, List<SessionInfo>>((ref) {
  return SessionsNotifier(ref);
});

/// Sessions filtered by active status.
final activeSessionsProvider = Provider<List<SessionInfo>>((ref) {
  final sessions = ref.watch(sessionsProvider);
  return sessions.where((s) => s.status.isLive).toList();
});

/// Sessions filtered by completed status.
final completedSessionsProvider = Provider<List<SessionInfo>>((ref) {
  final sessions = ref.watch(sessionsProvider);
  return sessions.where((s) => !s.status.isLive).toList();
});
