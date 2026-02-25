/// Noise KK state machine for the initiator (app) side.
///
/// Protocol: Noise_KK_25519_ChaChaPoly_BLAKE2b
///
/// KK: both parties know each other's static keys beforehand (from QR pairing).
/// Provides mutual authentication + forward secrecy via ephemeral DH.
///
/// PSK is bound into the prologue as BLAKE2b-512("claude-remote/v1" || PSK),
/// providing an additional authentication factor.
///
/// Handshake (2 messages):
///   Initiator (app) --> msg1 (e, es, ss) --> Responder (bridge)
///   Initiator (app) <-- msg2 (e, ee, se) <-- Responder (bridge)
///   [split -> tx/rx CipherStates for transport]
///
/// Cross-platform compatible with the Node.js `noise-protocol` npm package.
/// All crypto primitives are identical: X25519, ChaCha20-Poly1305 IETF,
/// BLAKE2b-512, HMAC-BLAKE2b, HKDF.
library;

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'package:noise_kk_test/crypto/noise_session.dart';

// ---------------------------------------------------------------------------
// Constants matching noise-protocol npm
// ---------------------------------------------------------------------------

const _hashLen = 64; // BLAKE2b-512 output
const _blockLen = 128; // BLAKE2b block size (HMAC pad size)
const _keyLen = 32; // ChaCha20 key
const _nonceLen = 8; // Noise nonce (not IETF 12-byte)
const _macLen = 16; // Poly1305 MAC
const _dhLen = 32; // X25519 DH output

/// ASCII bytes of the protocol name.
final _protocolName = Uint8List.fromList(
  'Noise_KK_25519_ChaChaPoly_BLAKE2b'.codeUnits,
);

// ---------------------------------------------------------------------------
// Crypto primitives (matching noise-protocol npm exactly)
// ---------------------------------------------------------------------------

final _blake2b = Blake2b(hashLengthInBytes: _hashLen);
final _x25519 = X25519();
final _chacha = Chacha20.poly1305Aead();

/// BLAKE2b-512 hash of concatenated [parts]. Unkeyed, 64-byte output.
Future<Uint8List> _hash(List<Uint8List> parts) async {
  // Concatenate all parts into a single buffer
  var totalLen = 0;
  for (final p in parts) {
    totalLen += p.length;
  }
  final data = Uint8List(totalLen);
  var offset = 0;
  for (final p in parts) {
    data.setRange(offset, offset + p.length, p);
    offset += p.length;
  }
  final hash = await _blake2b.hash(data);
  return Uint8List.fromList(hash.bytes);
}

/// HMAC-BLAKE2b — textbook HMAC construction over BLAKE2b-512.
///
/// Matches the hmac-blake2b npm package exactly:
///   innerHash = BLAKE2b(innerPad || data...)
///   result    = BLAKE2b(outerPad || innerHash)
Future<Uint8List> _hmac(Uint8List key, List<Uint8List> data) async {
  // Normalize key to _blockLen bytes
  Uint8List hmacKey;
  if (key.length > _blockLen) {
    final hashed = await _hash([key]);
    hmacKey = Uint8List(_blockLen);
    hmacKey.setRange(0, hashed.length, hashed);
  } else {
    hmacKey = Uint8List(_blockLen);
    hmacKey.setRange(0, key.length, key);
  }

  // XOR pads
  final outerPad = Uint8List(_blockLen);
  final innerPad = Uint8List(_blockLen);
  for (var i = 0; i < _blockLen; i++) {
    outerPad[i] = 0x5c ^ hmacKey[i];
    innerPad[i] = 0x36 ^ hmacKey[i];
  }

  // Inner: BLAKE2b(innerPad || data...)
  final innerHash = await _hash([innerPad, ...data]);

  // Outer: BLAKE2b(outerPad || innerHash)
  return _hash([outerPad, innerHash]);
}

/// 2-output HKDF using HMAC-BLAKE2b.
///
/// tempKey = HMAC(ck, ikm)
/// out1    = HMAC(tempKey, [0x01])
/// out2    = HMAC(tempKey, [out1, 0x02])
///
/// Each output is 64 bytes (BLAKE2b-512). Callers truncate to 32 for keys.
Future<(Uint8List, Uint8List)> _hkdf2(Uint8List ck, Uint8List ikm) async {
  final tempKey = await _hmac(ck, [ikm]);
  final out1 = await _hmac(tempKey, [Uint8List.fromList([0x01])]);
  final out2 = await _hmac(tempKey, [out1, Uint8List.fromList([0x02])]);
  return (out1, out2);
}

/// Convert an integer nonce counter to 8-byte little-endian bytes.
Uint8List _nonceToBytes(int n) {
  final bytes = Uint8List(_nonceLen);
  var value = n;
  for (var i = 0; i < _nonceLen; i++) {
    bytes[i] = value & 0xff;
    value >>= 8;
  }
  return bytes;
}

/// Expand 8-byte Noise nonce to 12-byte IETF nonce: [4 zero bytes][8-byte nonce].
///
/// This matches cipher.js: `ElongatedNonce.set(n, 4)`.
Uint8List _expandNonce(Uint8List nonce8) {
  final nonce12 = Uint8List(12);
  nonce12.setRange(4, 12, nonce8);
  return nonce12;
}

/// ChaCha20-Poly1305 IETF encrypt. Returns ciphertext || MAC (len + 16).
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
  // noise-protocol stores ciphertext || MAC
  final result = Uint8List(secretBox.cipherText.length + secretBox.mac.bytes.length);
  result.setRange(0, secretBox.cipherText.length, secretBox.cipherText);
  result.setRange(secretBox.cipherText.length, result.length, secretBox.mac.bytes);
  return result;
}

/// ChaCha20-Poly1305 IETF decrypt. Input is ciphertext || MAC.
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

/// X25519 Diffie-Hellman: shared_secret = privateKey * remotePublicKey.
Future<Uint8List> _dh(Uint8List privateKey, Uint8List publicKey) async {
  final keyPair = SimpleKeyPairData(
    privateKey,
    publicKey: SimplePublicKey(
      // We need our own public key here, but for DH only private + remote matter.
      // Construct a dummy — sharedSecretKey only uses privateKey + remotePublicKey.
      privateKey, // placeholder, overridden below
      type: KeyPairType.x25519,
    ),
    type: KeyPairType.x25519,
  );

  // The cryptography package needs a full keypair, but only uses the private key.
  // We compute the actual public key from the private key for correctness.
  final actualKeyPair = await _regenerateKeyPair(privateKey);
  final shared = await _x25519.sharedSecretKey(
    keyPair: actualKeyPair,
    remotePublicKey: SimplePublicKey(publicKey, type: KeyPairType.x25519),
  );
  return Uint8List.fromList(await shared.extractBytes());
}

/// Reconstruct a full X25519 keypair from a private key.
Future<SimpleKeyPair> _regenerateKeyPair(Uint8List privateKey) async {
  // The keypair stores private key bytes and derives public key.
  // For X25519, public = clamp(private) * basepoint.
  // We use the cryptography package's newKeyPairFromSeed if available,
  // or construct it manually.
  final kp = await _x25519.newKeyPairFromSeed(privateKey);
  return kp;
}

// ---------------------------------------------------------------------------
// Noise KK state machine — Initiator (app) side
// ---------------------------------------------------------------------------

/// Noise KK handshake initiator.
///
/// Usage:
/// ```dart
/// final handshake = NoiseKK(
///   staticPrivate: myPrivateKey,
///   staticPublic: myPublicKey,
///   remoteStaticPublic: bridgePublicKey,
/// );
/// final msg1 = await handshake.writeMessage1(prologue);
/// // send msg1, receive msg2
/// final session = await handshake.readMessage2(msg2);
/// // use session.encrypt() / session.decrypt() for transport
/// ```
class NoiseKK {
  // Symmetric state
  Uint8List _ck; // chaining key, 64 bytes
  Uint8List _h; // handshake hash, 64 bytes
  Uint8List? _cipherKey; // 32 bytes or null (no key = pass-through)
  int _cipherNonce; // auto-incrementing counter

  // Our static keys
  final Uint8List _staticPrivate; // 32 bytes
  final Uint8List _staticPublic; // 32 bytes
  final Uint8List _remoteStaticPublic; // 32 bytes

  // Ephemeral keys (generated during writeMessage1)
  Uint8List? _ephemeralPrivate;
  Uint8List? _ephemeralPublic;

  NoiseKK({
    required Uint8List staticPrivate,
    required Uint8List staticPublic,
    required Uint8List remoteStaticPublic,
  })  : _staticPrivate = Uint8List.fromList(staticPrivate),
        _staticPublic = Uint8List.fromList(staticPublic),
        _remoteStaticPublic = Uint8List.fromList(remoteStaticPublic),
        _ck = Uint8List(_hashLen),
        _h = Uint8List(_hashLen),
        _cipherNonce = 0;

  // -- Symmetric state operations --

  /// InitializeSymmetric: set h and ck from protocol name.
  void _initializeSymmetric() {
    // Protocol name is 33 bytes <= HASHLEN (64), so zero-pad into h
    _h = Uint8List(_hashLen);
    _h.setRange(0, _protocolName.length, _protocolName);

    // ck = h (copy)
    _ck = Uint8List.fromList(_h);

    // No cipher key yet
    _cipherKey = null;
    _cipherNonce = 0;
  }

  /// MixHash: h = BLAKE2b(h || data).
  Future<void> _mixHash(Uint8List data) async {
    _h = await _hash([_h, data]);
  }

  /// MixKey: update chaining key and install new cipher key.
  ///
  /// (ck, tempKey) = HKDF(ck, inputKeyMaterial)
  /// cipherKey = tempKey[0:32]
  /// nonce = 0
  Future<void> _mixKey(Uint8List ikm) async {
    final (newCk, tempKey) = await _hkdf2(_ck, ikm);
    _ck = newCk;
    _cipherKey = tempKey.sublist(0, _keyLen); // truncate 64 → 32
    _cipherNonce = 0;
  }

  /// EncryptAndHash: encrypt plaintext with AD=h, mix ciphertext into h.
  ///
  /// If no cipher key is set, pass through plaintext unchanged.
  Future<Uint8List> _encryptAndHash(Uint8List plaintext) async {
    Uint8List ciphertext;
    if (_cipherKey == null) {
      // No key — pass through
      ciphertext = plaintext;
    } else {
      final nonce = _nonceToBytes(_cipherNonce);
      ciphertext = await _aeadEncrypt(_cipherKey!, nonce, _h, plaintext);
      _cipherNonce++;
    }
    await _mixHash(ciphertext);
    return ciphertext;
  }

  /// DecryptAndHash: decrypt ciphertext with AD=h, mix ciphertext into h.
  Future<Uint8List> _decryptAndHash(Uint8List ciphertext) async {
    Uint8List plaintext;
    if (_cipherKey == null) {
      plaintext = ciphertext;
    } else {
      final nonce = _nonceToBytes(_cipherNonce);
      plaintext = await _aeadDecrypt(_cipherKey!, nonce, _h, ciphertext);
      _cipherNonce++;
    }
    await _mixHash(ciphertext);
    return plaintext;
  }

  /// Split: derive transport cipher keys from final chaining key.
  ///
  /// For initiator (readMessage):
  ///   cs1 = rx (tempKey1[0:32])
  ///   cs2 = tx (tempKey2[0:32])
  Future<NoiseSession> _split() async {
    final (out1, out2) = await _hkdf2(_ck, Uint8List(0));

    // Initiator: rx = out1[0:32], tx = out2[0:32]
    // (The noise-protocol npm calls split(rx, tx) for readMessage,
    //  which assigns cs1=rx=tempKey1, cs2=tx=tempKey2)
    final rxKey = out1.sublist(0, _keyLen);
    final txKey = out2.sublist(0, _keyLen);

    return NoiseSession(
      txKey: txKey,
      rxKey: rxKey,
      remotePublicKey: Uint8List.fromList(_remoteStaticPublic),
    );
  }

  // -- Handshake messages --

  /// Build prologue from PSK: BLAKE2b-512("claude-remote/v1" || PSK).
  static Future<Uint8List> buildPrologue(Uint8List psk) async {
    return _hash([
      Uint8List.fromList('claude-remote/v1'.codeUnits),
      psk,
    ]);
  }

  /// Write message 1: e, es, ss → 48 bytes (with empty payload).
  ///
  /// Call this first, send the returned bytes to the bridge.
  Future<Uint8List> writeMessage1(Uint8List prologue) async {
    // 1. Initialize symmetric state
    _initializeSymmetric();

    // 2. Mix prologue
    await _mixHash(prologue);

    // 3. Pre-messages: mixHash both static public keys
    //    KK pre-messages: -> s, <- s
    //    Initiator hashes own spk, then remote spk
    await _mixHash(_staticPublic);
    await _mixHash(_remoteStaticPublic);

    // 4. Message 1 tokens: e, es, ss

    // e: generate ephemeral keypair
    final ephKeyPair = await _x25519.newKeyPair();
    _ephemeralPrivate =
        Uint8List.fromList(await ephKeyPair.extractPrivateKeyBytes());
    _ephemeralPublic =
        Uint8List.fromList((await ephKeyPair.extractPublicKey()).bytes);

    // Write ephemeral public key (32 bytes)
    final msg = BytesBuilder();
    msg.add(_ephemeralPublic!);
    await _mixHash(_ephemeralPublic!);

    // es: DH(esk, rs) — initiator's ephemeral × responder's static
    final esDh = await _dh(_ephemeralPrivate!, _remoteStaticPublic);
    await _mixKey(esDh);

    // ss: DH(ssk, rs) — both static keys
    final ssDh = await _dh(_staticPrivate, _remoteStaticPublic);
    await _mixKey(ssDh);

    // Encrypt empty payload (produces 16-byte MAC)
    final encrypted = await _encryptAndHash(Uint8List(0));
    msg.add(encrypted);

    return msg.toBytes(); // 32 + 16 = 48 bytes
  }

  /// Read message 2: e, ee, se → completes handshake.
  ///
  /// Returns a [NoiseSession] for transport encryption.
  Future<NoiseSession> readMessage2(Uint8List msg2) async {
    if (msg2.length < 48) {
      throw ArgumentError('Message 2 too short: ${msg2.length} bytes, need >= 48');
    }

    // e: read remote ephemeral public key (32 bytes)
    final re = msg2.sublist(0, _dhLen);
    await _mixHash(re);

    // ee: DH(esk, re) — both ephemeral keys
    final eeDh = await _dh(_ephemeralPrivate!, re);
    await _mixKey(eeDh);

    // se: DH(ssk, re) — initiator's static × responder's ephemeral
    final seDh = await _dh(_staticPrivate, re);
    await _mixKey(seDh);

    // Decrypt payload (should be empty — 16-byte MAC)
    await _decryptAndHash(msg2.sublist(_dhLen));

    // Split → transport cipher states
    return _split();
  }
}
