import 'dart:async';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../crypto/key_store.dart';
import '../crypto/noise_kk.dart';
import '../crypto/noise_session.dart';
import '../models/app_message.dart';
import '../models/bridge_message.dart';
import 'message_codec.dart';

/// A single WebSocket connection to the bridge with Noise encryption.
///
/// Lifecycle:
/// 1. Connect WebSocket to ws://<host>:<port>/ws
/// 2. Send handshake frame: [0x01][32B pubkey][48B noise msg1]
/// 3. Receive: [48B noise msg2]
/// 4. Handshake complete → all frames are encrypted binary
class BridgeConnection {
  final String host;
  final int port;
  final KeyStore _keyStore;

  WebSocketChannel? _channel;
  NoiseSession? _session;
  MessageCodec? _codec;

  final _messageController = StreamController<BridgeMessage>.broadcast();

  /// Stream of decrypted messages from the bridge.
  Stream<BridgeMessage> get messages => _messageController.stream;

  /// Whether the connection is established and encrypted.
  bool get isConnected => _session != null && _channel != null;

  BridgeConnection({
    required this.host,
    required this.port,
    required KeyStore keyStore,
  }) : _keyStore = keyStore;

  /// Connect and perform Noise KK handshake.
  Future<void> connect() async {
    // Load keys
    final keyPair = await _keyStore.loadKeypair();
    final bridgePub = await _keyStore.loadBridgePublicKey();
    final psk = await _keyStore.loadPsk();

    if (keyPair == null || bridgePub == null || psk == null) {
      throw StateError('Not paired — cannot connect');
    }

    final privateKey = Uint8List.fromList(await keyPair.extractPrivateKeyBytes());
    final publicKey = Uint8List.fromList((await keyPair.extractPublicKey()).bytes);

    // Build prologue
    final prologue = await NoiseKK.buildPrologue(psk);

    // Initialize Noise KK handshake
    final handshake = NoiseKK(
      staticPrivate: privateKey,
      staticPublic: publicKey,
      remoteStaticPublic: bridgePub,
    );

    // Generate msg1
    final msg1 = await handshake.writeMessage1(prologue);

    // Connect WebSocket
    final uri = Uri.parse('ws://$host:$port/ws');
    _channel = WebSocketChannel.connect(uri);
    await _channel!.ready;

    // Send handshake frame: [0x01 version][32B our pubkey][48B msg1]
    final handshakeFrame = Uint8List(1 + 32 + msg1.length);
    handshakeFrame[0] = 0x01; // protocol version
    handshakeFrame.setRange(1, 33, publicKey);
    handshakeFrame.setRange(33, 33 + msg1.length, msg1);
    _channel!.sink.add(handshakeFrame);

    // Wait for msg2 response
    final completer = Completer<Uint8List>();
    late StreamSubscription sub;
    sub = _channel!.stream.listen(
      (data) {
        sub.cancel();
        if (data is List<int>) {
          completer.complete(Uint8List.fromList(data));
        } else {
          completer.completeError(
            StateError('Expected binary handshake response, got ${data.runtimeType}'),
          );
        }
      },
      onError: (error) {
        sub.cancel();
        completer.completeError(error);
      },
    );

    final msg2 = await completer.future;

    // Complete handshake
    _session = await handshake.readMessage2(msg2);
    _codec = MessageCodec(_session!);

    // Start listening for encrypted messages
    _channel!.stream.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
    );
  }

  void _onData(dynamic data) {
    if (data is! List<int> || _codec == null) return;
    _codec!.decode(Uint8List.fromList(data)).then(
      (message) => _messageController.add(message),
      onError: (e) => _messageController.addError(e),
    );
  }

  void _onError(Object error) {
    _messageController.addError(error);
  }

  void _onDone() {
    _session = null;
    _codec = null;
    _messageController.close();
  }

  /// Send an encrypted message to the bridge.
  Future<void> send(AppMessage message) async {
    if (_codec == null || _channel == null) {
      throw StateError('Not connected');
    }
    final encrypted = await _codec!.encode(message);
    _channel!.sink.add(encrypted);
  }

  /// Close the connection.
  Future<void> close() async {
    await _channel?.sink.close();
    _channel = null;
    _session = null;
    _codec = null;
  }
}
