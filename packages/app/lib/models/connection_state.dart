/// How we're connected to the bridge.
enum ConnectionMethod { mdns, lan, tunnel }

/// Overall connection lifecycle state.
enum ConnectionPhase { disconnected, discovering, connecting, handshaking, connected }

/// Full connection state exposed to UI.
class BridgeConnectionState {
  final ConnectionPhase phase;
  final ConnectionMethod? method;
  final String? host;
  final int? port;
  final String? error;
  final int reconnectAttempts;

  const BridgeConnectionState({
    this.phase = ConnectionPhase.disconnected,
    this.method,
    this.host,
    this.port,
    this.error,
    this.reconnectAttempts = 0,
  });

  bool get isConnected => phase == ConnectionPhase.connected;
  bool get isReconnecting =>
      phase == ConnectionPhase.disconnected && reconnectAttempts > 0;

  BridgeConnectionState copyWith({
    ConnectionPhase? phase,
    ConnectionMethod? method,
    String? host,
    int? port,
    String? error,
    int? reconnectAttempts,
  }) =>
      BridgeConnectionState(
        phase: phase ?? this.phase,
        method: method ?? this.method,
        host: host ?? this.host,
        port: port ?? this.port,
        error: error ?? this.error,
        reconnectAttempts: reconnectAttempts ?? this.reconnectAttempts,
      );
}
