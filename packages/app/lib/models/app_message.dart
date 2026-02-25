/// Messages from App -> Bridge, matching the protocol types.
sealed class AppMessage {
  Map<String, dynamic> toJson();
}

class ListSessionsMessage implements AppMessage {
  @override
  Map<String, dynamic> toJson() => {'type': 'list_sessions'};
}

class SubscribeMessage implements AppMessage {
  final String sessionId;
  SubscribeMessage({required this.sessionId});

  @override
  Map<String, dynamic> toJson() => {'type': 'subscribe', 'sessionId': sessionId};
}

class UnsubscribeMessage implements AppMessage {
  final String sessionId;
  UnsubscribeMessage({required this.sessionId});

  @override
  Map<String, dynamic> toJson() => {'type': 'unsubscribe', 'sessionId': sessionId};
}

class ApproveMessage implements AppMessage {
  final String sessionId;
  final String requestId;
  ApproveMessage({required this.sessionId, required this.requestId});

  @override
  Map<String, dynamic> toJson() =>
      {'type': 'approve', 'sessionId': sessionId, 'requestId': requestId};
}

class RejectMessage implements AppMessage {
  final String sessionId;
  final String requestId;
  RejectMessage({required this.sessionId, required this.requestId});

  @override
  Map<String, dynamic> toJson() =>
      {'type': 'reject', 'sessionId': sessionId, 'requestId': requestId};
}

class InputMessage implements AppMessage {
  final String sessionId;
  final String text;
  InputMessage({required this.sessionId, required this.text});

  @override
  Map<String, dynamic> toJson() =>
      {'type': 'input', 'sessionId': sessionId, 'text': text};
}
