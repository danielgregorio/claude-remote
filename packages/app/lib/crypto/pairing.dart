import 'dart:typed_data';
import '../models/pairing_payload.dart';
import 'key_store.dart';

/// Result of a successful pairing operation.
class PairingResult {
  final PairingPayload payload;
  final Uint8List appPublicKey;

  PairingResult({required this.payload, required this.appPublicKey});
}

/// Handles the pairing flow: parse QR -> generate keys -> store.
class PairingService {
  final KeyStore _keyStore;

  PairingService(this._keyStore);

  /// Parse a QR code value and complete pairing.
  ///
  /// 1. Parse the claude-remote:// URI
  /// 2. Generate app's X25519 keypair
  /// 3. Store everything in secure storage
  Future<PairingResult> pair(String qrValue) async {
    // Parse QR code
    final payload = PairingPayload.fromUri(qrValue);

    // Validate key sizes
    if (payload.bridgePublicKey.length != 32) {
      throw FormatException(
        'Invalid bridge public key length: ${payload.bridgePublicKey.length}',
      );
    }
    if (payload.psk.length != 32) {
      throw FormatException(
        'Invalid PSK length: ${payload.psk.length}',
      );
    }

    // Generate app keypair
    final keyPair = await _keyStore.generateAndStoreKeypair();
    final publicKey = await keyPair.extractPublicKey();

    // Store bridge info
    await _keyStore.storeBridgeInfo(
      bridgePublicKey: payload.bridgePublicKey,
      psk: payload.psk,
      bridgeName: payload.name,
      port: payload.lanPort,
      mdnsService: payload.mdnsService,
      relayUrl: payload.relayUrl,
      relayPort: payload.relayPort,
    );

    return PairingResult(
      payload: payload,
      appPublicKey: Uint8List.fromList(publicKey.bytes),
    );
  }

  /// Check if the app is already paired.
  Future<bool> get isPaired => _keyStore.isPaired;

  /// Unpair from the current bridge.
  Future<void> unpair() => _keyStore.clear();
}
