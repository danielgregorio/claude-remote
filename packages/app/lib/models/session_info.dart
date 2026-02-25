/// Status of a Claude Code session.
enum SessionStatus {
  active,
  waitingInput,
  waitingPermission,
  idle,
  completed,
  error;

  static SessionStatus fromString(String s) {
    switch (s) {
      case 'active':
        return SessionStatus.active;
      case 'waiting_input':
        return SessionStatus.waitingInput;
      case 'waiting_permission':
        return SessionStatus.waitingPermission;
      case 'idle':
        return SessionStatus.idle;
      case 'completed':
        return SessionStatus.completed;
      case 'error':
        return SessionStatus.error;
      default:
        return SessionStatus.active;
    }
  }

  String toWireString() {
    switch (this) {
      case SessionStatus.active:
        return 'active';
      case SessionStatus.waitingInput:
        return 'waiting_input';
      case SessionStatus.waitingPermission:
        return 'waiting_permission';
      case SessionStatus.idle:
        return 'idle';
      case SessionStatus.completed:
        return 'completed';
      case SessionStatus.error:
        return 'error';
    }
  }

  bool get isLive =>
      this == active || this == waitingInput || this == waitingPermission || this == idle;
}

/// Information about a Claude Code session, matching the protocol type.
class SessionInfo {
  final String id;
  final String name;
  final SessionStatus status;
  final String cwd;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int outputLines;
  final int durationSeconds;
  final String? model;

  const SessionInfo({
    required this.id,
    required this.name,
    required this.status,
    required this.cwd,
    required this.startedAt,
    this.endedAt,
    this.outputLines = 0,
    this.durationSeconds = 0,
    this.model,
  });

  factory SessionInfo.fromJson(Map<String, dynamic> json) => SessionInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        status: SessionStatus.fromString(json['status'] as String),
        cwd: json['cwd'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String),
        endedAt: json['endedAt'] != null
            ? DateTime.parse(json['endedAt'] as String)
            : null,
        outputLines: json['outputLines'] as int? ?? 0,
        durationSeconds: json['durationSeconds'] as int? ?? 0,
        model: json['model'] as String?,
      );

  SessionInfo copyWith({SessionStatus? status, DateTime? endedAt, int? outputLines}) =>
      SessionInfo(
        id: id,
        name: name,
        status: status ?? this.status,
        cwd: cwd,
        startedAt: startedAt,
        endedAt: endedAt ?? this.endedAt,
        outputLines: outputLines ?? this.outputLines,
        durationSeconds: durationSeconds,
        model: model,
      );
}
