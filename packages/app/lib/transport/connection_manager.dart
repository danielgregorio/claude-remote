import 'dart:async';
import 'dart:math';

import '../crypto/key_store.dart';
import '../models/app_message.dart';
import '../models/bridge_message.dart';
import '../models/connection_state.dart';
import 'bridge_connection.dart';

/// Manages the connection to the bridge with auto-reconnect.
///
/// Tries endpoints in order: last known IP → mDNS → tunnel.
/// Exponential backoff on failure: 1s → 2s → 4s → 8s → max 30s.
class ConnectionManager {
  final KeyStore _keyStore;

  BridgeConnection? _connection;
  BridgeConnectionState _state = const BridgeConnectionState();
  Timer? _reconnectTimer;
  bool _shouldReconnect = true;

  final _stateController = StreamController<BridgeConnectionState>.broadcast();
  final _messageController = StreamController<BridgeMessage>.broadcast();

  /// Stream of connection state changes.
  Stream<BridgeConnectionState> get stateStream => _stateController.stream;

  /// Stream of decrypted messages from the bridge.
  Stream<BridgeMessage> get messages => _messageController.stream;

  /// Current connection state.
  BridgeConnectionState get state => _state;

  ConnectionManager({required KeyStore keyStore}) : _keyStore = keyStore;

  void _updateState(BridgeConnectionState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  /// Start connecting to the bridge.
  Future<void> connect() async {
    _shouldReconnect = true;
    await _attemptConnection();
  }

  /// Disconnect and stop reconnecting.
  Future<void> disconnect() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _connection?.close();
    _connection = null;
    _updateState(const BridgeConnectionState(
      phase: ConnectionPhase.disconnected,
    ));
  }

  Future<void> _attemptConnection() async {
    final port = await _keyStore.loadBridgePort();
    if (port == null) {
      _updateState(const BridgeConnectionState(
        phase: ConnectionPhase.disconnected,
        error: 'Not paired',
      ));
      return;
    }

    // Try LAN first (localhost/direct IP)
    // In a full implementation, this would try mDNS → last IP → tunnel
    final endpoints = await _buildEndpoints(port);

    for (final endpoint in endpoints) {
      _updateState(BridgeConnectionState(
        phase: ConnectionPhase.connecting,
        host: endpoint.host,
        port: endpoint.port,
        method: endpoint.method,
        reconnectAttempts: _state.reconnectAttempts,
      ));

      try {
        final conn = BridgeConnection(
          host: endpoint.host,
          port: endpoint.port,
          keyStore: _keyStore,
        );

        _updateState(_state.copyWith(phase: ConnectionPhase.handshaking));
        await conn.connect();

        _connection = conn;
        _updateState(BridgeConnectionState(
          phase: ConnectionPhase.connected,
          host: endpoint.host,
          port: endpoint.port,
          method: endpoint.method,
          reconnectAttempts: 0,
        ));

        // Forward messages
        conn.messages.listen(
          (msg) => _messageController.add(msg),
          onError: (e) => _messageController.addError(e),
          onDone: () => _onDisconnected(),
        );

        return; // Connected successfully
      } catch (e) {
        // Try next endpoint
        continue;
      }
    }

    // All endpoints failed — schedule reconnect
    _scheduleReconnect();
  }

  Future<List<_Endpoint>> _buildEndpoints(int port) async {
    final endpoints = <_Endpoint>[];

    // Try LAN (localhost for dev, would be mDNS/stored IP in production)
    endpoints.add(_Endpoint('localhost', port, ConnectionMethod.lan));

    // Try relay if available
    final relay = await _keyStore.loadRelay();
    if (relay != null) {
      endpoints.add(_Endpoint(relay.url, relay.port, ConnectionMethod.tunnel));
    }

    return endpoints;
  }

  void _onDisconnected() {
    _connection = null;
    if (_shouldReconnect) {
      _updateState(BridgeConnectionState(
        phase: ConnectionPhase.disconnected,
        reconnectAttempts: _state.reconnectAttempts + 1,
      ));
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    final attempts = _state.reconnectAttempts;
    final delay = min(30, pow(2, min(attempts, 5)).toInt());

    _updateState(_state.copyWith(
      phase: ConnectionPhase.disconnected,
      reconnectAttempts: attempts,
      error: 'Reconnecting in ${delay}s...',
    ));

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      if (_shouldReconnect) _attemptConnection();
    });
  }

  /// Send a message through the active connection.
  Future<void> send(AppMessage message) async {
    if (_connection == null || !_connection!.isConnected) {
      throw StateError('Not connected');
    }
    await _connection!.send(message);
  }

  /// Dispose resources.
  void dispose() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _connection?.close();
    _stateController.close();
    _messageController.close();
  }
}

class _Endpoint {
  final String host;
  final int port;
  final ConnectionMethod method;

  _Endpoint(this.host, this.port, this.method);
}
