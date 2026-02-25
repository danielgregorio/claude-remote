import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/session_info.dart';
import 'sessions_provider.dart';

/// Manages which sessions the user has "pinned" for priority notifications
/// and quick access.
///
/// When multiple Claude Code sessions are running simultaneously, the user
/// can pin specific sessions to:
/// 1. Receive notifications only for pinned sessions (if setting enabled)
/// 2. See pinned sessions highlighted at the top of the dashboard
/// 3. Quick-switch between pinned sessions from the detail screen
class FocusedSessionsNotifier extends StateNotifier<Set<String>> {
  static const _storageKey = 'focused_session_ids';
  final FlutterSecureStorage _storage;

  FocusedSessionsNotifier({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage(),
        super({}) {
    _load();
  }

  Future<void> _load() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw != null && raw.isNotEmpty) {
      state = raw.split(',').toSet();
    }
  }

  Future<void> _persist() async {
    await _storage.write(key: _storageKey, value: state.join(','));
  }

  /// Pin a session for focus notifications and quick access.
  Future<void> pin(String sessionId) async {
    state = {...state, sessionId};
    await _persist();
  }

  /// Unpin a session.
  Future<void> unpin(String sessionId) async {
    state = {...state}..remove(sessionId);
    await _persist();
  }

  /// Toggle pin state.
  Future<void> toggle(String sessionId) async {
    if (state.contains(sessionId)) {
      await unpin(sessionId);
    } else {
      await pin(sessionId);
    }
  }

  /// Check if a session is pinned.
  bool isPinned(String sessionId) => state.contains(sessionId);

  /// Remove completed/stale sessions that no longer exist.
  Future<void> cleanup(List<String> activeSessionIds) async {
    final active = activeSessionIds.toSet();
    final cleaned = state.intersection(active);
    if (cleaned.length != state.length) {
      state = cleaned;
      await _persist();
    }
  }
}

/// Set of pinned session IDs.
final focusedSessionsProvider =
    StateNotifierProvider<FocusedSessionsNotifier, Set<String>>((ref) {
  return FocusedSessionsNotifier();
});

/// Whether a specific session is pinned.
final isSessionPinnedProvider = Provider.family<bool, String>((ref, sessionId) {
  final focused = ref.watch(focusedSessionsProvider);
  return focused.contains(sessionId);
});

/// Pinned sessions sorted to the top, then active, then completed.
final sortedSessionsProvider = Provider<List<SessionInfo>>((ref) {
  final sessions = ref.watch(sessionsProvider);
  final pinned = ref.watch(focusedSessionsProvider);

  final pinnedSessions = <SessionInfo>[];
  final unpinnedActive = <SessionInfo>[];
  final unpinnedCompleted = <SessionInfo>[];

  for (final s in sessions) {
    if (pinned.contains(s.id)) {
      pinnedSessions.add(s);
    } else if (s.status.isLive) {
      unpinnedActive.add(s);
    } else {
      unpinnedCompleted.add(s);
    }
  }

  return [...pinnedSessions, ...unpinnedActive, ...unpinnedCompleted];
});
