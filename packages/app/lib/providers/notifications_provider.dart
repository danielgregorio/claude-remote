import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../crypto/key_store.dart';
import 'connection_provider.dart';
import 'focused_session_provider.dart';
import 'settings_provider.dart';

/// ntfy notification event from the bridge.
class NtfyEvent {
  final String bridge;
  final String session;
  final String event; // needs_permission, needs_input, completed, error
  final String priority;
  final DateTime timestamp;

  NtfyEvent({
    required this.bridge,
    required this.session,
    required this.event,
    required this.priority,
    required this.timestamp,
  });

  factory NtfyEvent.fromJson(Map<String, dynamic> json) => NtfyEvent(
        bridge: json['bridge'] as String? ?? '',
        session: json['session'] as String? ?? '',
        event: json['event'] as String? ?? '',
        priority: json['priority'] as String? ?? 'medium',
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// Polls ntfy server for push notifications from the bridge.
///
/// Uses HTTP long-polling (Server-Sent Events style) to receive
/// notifications without requiring Firebase or any proprietary service.
///
/// No sensitive content is ever sent through ntfy — only event type
/// and session name.
class NtfyPoller {
  final String server;
  final String topic;
  Timer? _timer;
  DateTime _since = DateTime.now();

  final _controller = StreamController<NtfyEvent>.broadcast();
  Stream<NtfyEvent> get events => _controller.stream;

  NtfyPoller({required this.server, required this.topic});

  /// Start polling for notifications.
  void start() {
    // Poll every 30 seconds as a simple implementation.
    // A production version would use SSE or WebSocket long-polling.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _poll());
    _poll(); // Initial poll
  }

  Future<void> _poll() async {
    // TODO: Implement HTTP polling against ntfy server
    // final url = '$server/$topic/json?since=${_since.millisecondsSinceEpoch ~/ 1000}';
    // final response = await http.get(Uri.parse(url));
    // Parse NDJSON response lines into NtfyEvent objects
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
    _controller.close();
  }
}

/// Local notification display service with session filtering.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );
    _initialized = true;
  }

  /// Show a local notification for a bridge event.
  ///
  /// When [notifyOnlyPinned] is true, only events from sessions in
  /// [pinnedSessionIds] will produce notifications.
  Future<void> showNotification(
    NtfyEvent event, {
    bool notifyOnlyPinned = false,
    Set<String> pinnedSessionIds = const {},
  }) async {
    // Filter: skip if "only pinned" is on and this session isn't pinned
    if (notifyOnlyPinned && !pinnedSessionIds.contains(event.session)) {
      return;
    }

    await initialize();

    String title;
    String body;
    Importance importance;

    switch (event.event) {
      case 'needs_permission':
        title = 'Permission needed';
        body = 'Session "${event.session}" needs your approval';
        importance = Importance.high;
      case 'needs_input':
        title = 'Input needed';
        body = 'Session "${event.session}" is waiting for input';
        importance = Importance.high;
      case 'completed':
        title = 'Session completed';
        body = 'Session "${event.session}" has finished';
        importance = Importance.low;
      case 'error':
        title = 'Session error';
        body = 'Session "${event.session}" encountered an error';
        importance = Importance.defaultImportance;
      default:
        title = 'Claude Remote';
        body = 'Session "${event.session}": ${event.event}';
        importance = Importance.defaultImportance;
    }

    await _plugin.show(
      event.session.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'claude_remote_sessions',
          'Session Events',
          channelDescription: 'Notifications from Claude Code sessions',
          importance: importance,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          interruptionLevel: event.event == 'needs_permission'
              ? InterruptionLevel.timeSensitive
              : InterruptionLevel.active,
        ),
      ),
    );
  }
}

/// Global notification service provider.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});
