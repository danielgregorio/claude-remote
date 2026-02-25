import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages cryptographic keys in platform-secure storage.
///
/// Stores:
/// - App's static Curve25519 keypair (generated on first pairing)
/// - Bridge's static public key (from QR code)
/// - Pre-shared key (from QR code)
class KeyStore {
  static const _keyPrivate = 'claude_remote_static_private';
  static const _keyPublic = 'claude_remote_static_public';
  static const _keyBridgePub = 'claude_remote_bridge_public';
  static const _keyPsk = 'claude_remote_psk';
  static const _keyBridgeName = 'claude_remote_bridge_name';
  static const _keyBridgePort = 'claude_remote_bridge_port';
  static const _keyBridgeMdns = 'claude_remote_bridge_mdns';
  static const _keyRelayUrl = 'claude_remote_relay_url';
  static const _keyRelayPort = 'claude_remote_relay_port';

  final FlutterSecureStorage _storage;

  KeyStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// Check if we have a paired bridge.
  Future<bool> get isPaired async {
    final pk = await _storage.read(key: _keyBridgePub);
    return pk != null;
  }

  /// Generate a new X25519 keypair and store it.
  Future<SimpleKeyPair> generateAndStoreKeypair() async {
    final algorithm = X25519();
    final keyPair = await algorithm.newKeyPair();

    final privateBytes = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();

    await _storage.write(
      key: _keyPrivate,
      value: base64Encode(Uint8List.fromList(privateBytes)),
    );
    await _storage.write(
      key: _keyPublic,
      value: base64Encode(Uint8List.fromList(publicKey.bytes)),
    );

    return keyPair;
  }

  /// Load the stored keypair, or null if not yet generated.
  Future<SimpleKeyPair?> loadKeypair() async {
    final privB64 = await _storage.read(key: _keyPrivate);
    final pubB64 = await _storage.read(key: _keyPublic);
    if (privB64 == null || pubB64 == null) return null;

    final privateBytes = base64Decode(privB64);
    final publicBytes = base64Decode(pubB64);

    return SimpleKeyPairData(
      privateBytes,
      publicKey: SimplePublicKey(publicBytes, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
  }

  /// Store bridge info from pairing payload.
  Future<void> storeBridgeInfo({
    required Uint8List bridgePublicKey,
    required Uint8List psk,
    required String bridgeName,
    required int port,
    required String mdnsService,
    String? relayUrl,
    int? relayPort,
  }) async {
    await _storage.write(
      key: _keyBridgePub,
      value: base64Encode(bridgePublicKey),
    );
    await _storage.write(key: _keyPsk, value: base64Encode(psk));
    await _storage.write(key: _keyBridgeName, value: bridgeName);
    await _storage.write(key: _keyBridgePort, value: port.toString());
    await _storage.write(key: _keyBridgeMdns, value: mdnsService);
    if (relayUrl != null) {
      await _storage.write(key: _keyRelayUrl, value: relayUrl);
      await _storage.write(key: _keyRelayPort, value: relayPort.toString());
    }
  }

  /// Load bridge public key, or null if not paired.
  Future<Uint8List?> loadBridgePublicKey() async {
    final b64 = await _storage.read(key: _keyBridgePub);
    if (b64 == null) return null;
    return base64Decode(b64);
  }

  /// Load pre-shared key, or null if not paired.
  Future<Uint8List?> loadPsk() async {
    final b64 = await _storage.read(key: _keyPsk);
    if (b64 == null) return null;
    return base64Decode(b64);
  }

  /// Load bridge name.
  Future<String?> loadBridgeName() async =>
      _storage.read(key: _keyBridgeName);

  /// Load bridge port.
  Future<int?> loadBridgePort() async {
    final s = await _storage.read(key: _keyBridgePort);
    return s != null ? int.tryParse(s) : null;
  }

  /// Load relay info.
  Future<({String url, int port})?> loadRelay() async {
    final url = await _storage.read(key: _keyRelayUrl);
    final portStr = await _storage.read(key: _keyRelayPort);
    if (url == null || portStr == null) return null;
    return (url: url, port: int.parse(portStr));
  }

  /// Clear all stored keys (unpair).
  Future<void> clear() async {
    await _storage.deleteAll();
  }
}
