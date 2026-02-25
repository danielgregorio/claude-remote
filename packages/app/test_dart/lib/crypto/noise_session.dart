/// Transport encryption/decryption after a Noise KK handshake.
///
/// Each side holds a tx and rx CipherState. The tx CipherState encrypts
/// outgoing messages, and the rx CipherState decrypts incoming messages.
///
/// Nonces auto-increment on each operation. Both sides must process messages
/// in order — if a message is lost, nonces will go out of sync.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const _keyLen = 32;
const _nonceLen = 8;
const _macLen = 16;

final _chacha = Chacha20.poly1305Aead();

/// A Noise transport session for post-handshake encrypted communication.
class NoiseSession {
  final Uint8List _txKey; // 32 bytes
  final Uint8List _rxKey; // 32 bytes
  int _txNonce;
  int _rxNonce;

  /// The remote peer's static Curve25519 public key.
  final Uint8List remotePublicKey;

  /// Whether the session is established and ready for transport.
  bool get established => true;

  NoiseSession({
    required Uint8List txKey,
    required Uint8List rxKey,
    required this.remotePublicKey,
  })  : _txKey = Uint8List.fromList(txKey),
        _rxKey = Uint8List.fromList(rxKey),
        _txNonce = 0,
        _rxNonce = 0;

  /// Encrypt a plaintext message for sending.
  ///
  /// Returns ciphertext || MAC (plaintext.length + 16 bytes).
  Future<Uint8List> encrypt(Uint8List plaintext) async {
    final nonce8 = _nonceToBytes(_txNonce++);
    return _aeadEncrypt(_txKey, nonce8, Uint8List(0), plaintext);
  }

  /// Decrypt an incoming ciphertext message.
  ///
  /// Input must be ciphertext || MAC.
  Future<Uint8List> decrypt(Uint8List ciphertextWithMac) async {
    final nonce8 = _nonceToBytes(_rxNonce++);
    return _aeadDecrypt(_rxKey, nonce8, Uint8List(0), ciphertextWithMac);
  }

  /// Encrypt a JSON-serializable message.
  Future<Uint8List> encryptJson(Map<String, dynamic> json) async {
    final plaintext = utf8.encode(jsonEncode(json));
    return encrypt(Uint8List.fromList(plaintext));
  }

  /// Decrypt a message and parse as JSON.
  Future<Map<String, dynamic>> decryptJson(Uint8List ciphertextWithMac) async {
    final plaintext = await decrypt(ciphertextWithMac);
    return jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
  }
}

/// Convert nonce counter to 8-byte little-endian.
Uint8List _nonceToBytes(int n) {
  final bytes = Uint8List(_nonceLen);
  var value = n;
  for (var i = 0; i < _nonceLen; i++) {
    bytes[i] = value & 0xff;
    value >>= 8;
  }
  return bytes;
}

/// Expand 8-byte Noise nonce to 12-byte IETF nonce.
Uint8List _expandNonce(Uint8List nonce8) {
  final nonce12 = Uint8List(12);
  nonce12.setRange(4, 12, nonce8);
  return nonce12;
}

/// ChaCha20-Poly1305 IETF encrypt.
Future<Uint8List> _aeadEncrypt(
  Uint8List key,
  Uint8List nonce8,
  Uint8List ad,
  Uint8List plaintext,
) async {
  final nonce12 = _expandNonce(nonce8);
  final secretBox = await _chacha.encrypt(
    plaintext,
    secretKey: SecretKey(key),
    nonce: nonce12,
    aad: ad,
  );
  final result = Uint8List(secretBox.cipherText.length + secretBox.mac.bytes.length);
  result.setRange(0, secretBox.cipherText.length, secretBox.cipherText);
  result.setRange(secretBox.cipherText.length, result.length, secretBox.mac.bytes);
  return result;
}

/// ChaCha20-Poly1305 IETF decrypt.
Future<Uint8List> _aeadDecrypt(
  Uint8List key,
  Uint8List nonce8,
  Uint8List ad,
  Uint8List ciphertextWithMac,
) async {
  final nonce12 = _expandNonce(nonce8);
  final ctLen = ciphertextWithMac.length - _macLen;
  final cipherText = ciphertextWithMac.sublist(0, ctLen);
  final mac = Mac(ciphertextWithMac.sublist(ctLen));

  final secretBox = SecretBox(cipherText, nonce: nonce12, mac: mac);
  final plaintext = await _chacha.decrypt(
    secretBox,
    secretKey: SecretKey(key),
    aad: ad,
  );
  return Uint8List.fromList(plaintext);
}
