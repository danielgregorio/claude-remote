import 'session_info.dart';

/// Messages from Bridge -> App, matching the protocol types.
sealed class BridgeMessage {
  factory BridgeMessage.fromJson(Map<String, dynamic> json) {
    switch (json['type'] as String) {
      case 'session_list':
        return SessionListMessage.fromJson(json);
      case 'session_output':
        return SessionOutputMessage.fromJson(json);
      case 'session_status':
        return SessionStatusMessage.fromJson(json);
      case 'permission_request':
        return PermissionRequestMessage.fromJson(json);
      case 'question':
        return QuestionMessage.fromJson(json);
      case 'bridge_status':
        return BridgeStatusMessage.fromJson(json);
      default:
        throw FormatException('Unknown bridge message type: ${json['type']}');
    }
  }
}

class SessionListMessage implements BridgeMessage {
  final List<SessionInfo> sessions;

  SessionListMessage({required this.sessions});

  factory SessionListMessage.fromJson(Map<String, dynamic> json) =>
      SessionListMessage(
        sessions: (json['sessions'] as List)
            .map((s) => SessionInfo.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

class SessionOutputMessage implements BridgeMessage {
  final String sessionId;
  final String content;
  final DateTime timestamp;

  SessionOutputMessage({
    required this.sessionId,
    required this.content,
    required this.timestamp,
  });

  factory SessionOutputMessage.fromJson(Map<String, dynamic> json) =>
      SessionOutputMessage(
        sessionId: json['sessionId'] as String,
        content: json['content'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}

class SessionStatusMessage implements BridgeMessage {
  final String sessionId;
  final SessionStatus status;
  final String? detail;

  SessionStatusMessage({
    required this.sessionId,
    required this.status,
    this.detail,
  });

  factory SessionStatusMessage.fromJson(Map<String, dynamic> json) =>
      SessionStatusMessage(
        sessionId: json['sessionId'] as String,
        status: SessionStatus.fromString(json['status'] as String),
        detail: json['detail'] as String?,
      );
}

class PermissionRequestMessage implements BridgeMessage {
  final String sessionId;
  final String requestId;
  final String tool;
  final String description;
  final Map<String, dynamic>? input;

  PermissionRequestMessage({
    required this.sessionId,
    required this.requestId,
    required this.tool,
    required this.description,
    this.input,
  });

  factory PermissionRequestMessage.fromJson(Map<String, dynamic> json) =>
      PermissionRequestMessage(
        sessionId: json['sessionId'] as String,
        requestId: json['requestId'] as String,
        tool: json['tool'] as String,
        description: json['description'] as String,
        input: json['input'] as Map<String, dynamic>?,
      );
}

class QuestionMessage implements BridgeMessage {
  final String sessionId;
  final String requestId;
  final String question;

  QuestionMessage({
    required this.sessionId,
    required this.requestId,
    required this.question,
  });

  factory QuestionMessage.fromJson(Map<String, dynamic> json) =>
      QuestionMessage(
        sessionId: json['sessionId'] as String,
        requestId: json['requestId'] as String,
        question: json['question'] as String,
      );
}

class BridgeStatusMessage implements BridgeMessage {
  final int uptime;
  final int activeSessions;
  final String version;

  BridgeStatusMessage({
    required this.uptime,
    required this.activeSessions,
    required this.version,
  });

  factory BridgeStatusMessage.fromJson(Map<String, dynamic> json) =>
      BridgeStatusMessage(
        uptime: json['uptime'] as int,
        activeSessions: json['activeSessions'] as int,
        version: json['version'] as String,
      );
}
