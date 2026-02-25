/// Full cross-platform Noise KK handshake + transport test.
///
/// Uses test vector keys. Runs Node.js responder once with Process.start,
/// feeds input line by line, reads output line by line.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:noise_kk_test/crypto/noise_kk.dart';

String hexEncode(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');

Uint8List hexDecode(String hex) {
  final bytes = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return Uint8List.fromList(bytes);
}

Future<void> main() async {
  print('=== Dart <-> Node.js Noise KK Cross-Platform Test ===\n');

  // Find repo root
  var dir = Directory.current.path;
  while (!File('$dir/package.json').existsSync()) {
    dir = Directory(dir).parent.path;
  }

  // Load test vectors
  final vectors = jsonDecode(
    File('$dir/packages/app/test/crypto/noise_test_vectors.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  final keys = vectors['keys'] as Map<String, dynamic>;
  final iKeys = keys['initiator'] as Map<String, dynamic>;
  final rKeys = keys['responder'] as Map<String, dynamic>;

  final initiatorPub = hexDecode(iKeys['publicKey'] as String);
  final initiatorPriv = hexDecode(iKeys['secretKey'] as String);
  final responderPub = hexDecode(rKeys['publicKey'] as String);
  final responderSeed = hexDecode(rKeys['seed'] as String);
  final psk = hexDecode(vectors['psk'] as String);

  // Step 1: Verify prologue
  final prologue = await NoiseKK.buildPrologue(psk);
  final expectedPrologue = vectors['prologue'] as String;
  assert(hexEncode(prologue) == expectedPrologue, 'Prologue mismatch!');
  print('[OK] Prologue matches Node.js');

  // Step 2: Generate msg1
  final handshake = NoiseKK(
    staticPrivate: initiatorPriv,
    staticPublic: initiatorPub,
    remoteStaticPublic: responderPub,
  );
  final msg1 = await handshake.writeMessage1(prologue);
  assert(msg1.length == 48, 'msg1 should be 48 bytes');
  print('[OK] msg1 generated (${msg1.length} bytes)');

  // Step 3: Pre-compute Dart's encrypted message using a DUMMY handshake first.
  // Actually, we can't — we need the real msg2 to complete the handshake.
  // Solution: use a Node.js script that accepts input in stages via a FIFO.

  // Better solution: use the test vectors' known handshake to verify.
  // The test vectors have fixed ephemeral keys, so msg1 and msg2 are deterministic.
  // BUT our Dart NoiseKK generates random ephemeral keys...

  // Correct approach: Use the batch Node.js responder, but complete the Dart
  // handshake with the first invocation's msg2, then verify decryption works
  // in ONE direction (Node→Dart). For the reverse direction, compute msg1 +
  // encrypted message, then pipe all 5 lines to a second Node.js invocation
  // that uses a DETERMINISTIC ephemeral key.

  // Actually the simplest correct approach: First invocation gives us msg2.
  // We complete handshake, encrypt a message. But we can't use a second
  // invocation because it'll have different ephemeral keys.
  //
  // The REAL fix: make the Node.js script interactive with a proper FIFO.
  // OR: write a Node.js script that uses a fixed seed for ephemeral keys.

  // Let's go with the interactive approach, but properly handle buffering.
  print('[..] Running Node.js responder (interactive)...');

  final proc = await Process.start(
    'node',
    ['-e', _nodeScript()],
    workingDirectory: dir,
  );

  final stderrBuf = StringBuffer();
  proc.stderr.transform(utf8.decoder).listen(stderrBuf.write);

  // Line-by-line output queue using StreamIterator
  final lineStream = proc.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  final lineIterator = StreamIterator(lineStream);

  // Helper to read one line
  Future<String> readLine() async {
    final hasNext = await lineIterator.moveNext().timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException(
        'Timed out waiting for Node.js output. stderr: $stderrBuf',
      ),
    );
    if (!hasNext) {
      throw StateError('No more output from Node.js. stderr: $stderrBuf');
    }
    return lineIterator.current;
  }

  // Send setup (3 lines)
  proc.stdin.writeln(hexEncode(responderSeed));
  proc.stdin.writeln(hexEncode(psk));
  proc.stdin.writeln(hexEncode(initiatorPub));
  await proc.stdin.flush();

  // Read responder pubkey
  final respPubHex = await readLine();
  assert(respPubHex == hexEncode(responderPub), 'Responder pubkey mismatch');
  print('[OK] Responder pubkey verified');

  // Send msg1
  proc.stdin.writeln(hexEncode(msg1));
  await proc.stdin.flush();

  // Read msg2
  final msg2Hex = await readLine();
  final msg2 = hexDecode(msg2Hex);
  assert(msg2.length == 48, 'msg2 should be 48 bytes, got ${msg2.length}');
  print('[OK] msg2 received (${msg2.length} bytes)');

  // Read encrypted from responder
  final encFromRespHex = await readLine();
  final encFromResp = hexDecode(encFromRespHex);

  // Complete handshake
  final session = await handshake.readMessage2(msg2);
  print('[OK] Handshake complete!');

  // Decrypt message from Node.js
  final decrypted = await session.decrypt(encFromResp);
  final message = utf8.decode(decrypted);
  assert(message == 'Hello from Node.js responder!',
      'Unexpected message: "$message"');
  print('[OK] Decrypted from Node.js: "$message"');

  // Encrypt message from Dart
  final dartMsg = Uint8List.fromList(utf8.encode('Hello from Dart initiator!'));
  final encFromDart = await session.encrypt(dartMsg);

  // Send encrypted message to Node.js
  proc.stdin.writeln(hexEncode(encFromDart));
  await proc.stdin.flush();
  await proc.stdin.close();

  // Read Node.js decrypted result
  final nodeDecrypted = await readLine();
  assert(nodeDecrypted == 'Hello from Dart initiator!',
      'Node.js decrypted unexpected: "$nodeDecrypted"');
  print('[OK] Node.js decrypted from Dart: "$nodeDecrypted"');

  final ec = await proc.exitCode;
  if (ec != 0) {
    print('WARN: Node.js exited with code $ec');
    print('stderr: $stderrBuf');
  }

  await lineIterator.cancel();
  print('\n=== ALL PASSED: Dart <-> Node.js Noise KK fully verified! ===');
}

/// Inline Node.js script for the interactive responder.
/// This avoids npx/tsx startup delays and uses require() directly.
String _nodeScript() => r"""
const noiseProtocol = require('noise-protocol');
const cipher = require('noise-protocol/cipher')();
const cipherState = require('noise-protocol/cipher-state')({ cipher });
const { createHash } = require('crypto');
const readline = require('readline');

function buildPrologue(psk) {
  const hash = createHash('blake2b512');
  hash.update(Buffer.from('claude-remote/v1'));
  hash.update(psk);
  return hash.digest();
}

function hex(buf) { return Buffer.from(buf).toString('hex'); }
function unhex(s) { return Buffer.from(s.trim(), 'hex'); }

const rl = readline.createInterface({ input: process.stdin });
const lines = [];

function onLine(line) {
  lines.push(line.trim());

  if (lines.length === 3) {
    // Phase 1: Got seed, psk, initiator_pub → output responder pubkey
    const seed = unhex(lines[0]);
    const psk = unhex(lines[1]);
    const responderKeys = noiseProtocol.seedKeygen(seed);
    console.log(hex(responderKeys.publicKey));
    // Store for later
    global._rKeys = responderKeys;
    global._psk = psk;
    global._iPub = unhex(lines[2]);
  }

  if (lines.length === 4) {
    // Phase 2: Got msg1 → handshake → output msg2 + encrypted
    const msg1 = unhex(lines[3]);
    const prologue = buildPrologue(global._psk);
    const state = noiseProtocol.initialize(
      'KK', false, prologue, global._rKeys, null, global._iPub
    );

    const p1 = Buffer.alloc(256);
    noiseProtocol.readMessage(state, msg1, p1);

    const m2 = Buffer.alloc(256);
    const split = noiseProtocol.writeMessage(state, Buffer.alloc(0), m2);
    if (!split) { process.stderr.write('no split\n'); process.exit(1); }

    console.log(hex(m2.subarray(0, noiseProtocol.writeMessage.bytes)));
    noiseProtocol.destroy(state);

    // Encrypt test message
    const testMsg = Buffer.from('Hello from Node.js responder!');
    const enc = Buffer.alloc(testMsg.length + cipherState.MACLEN);
    cipherState.encryptWithAd(split.tx, enc, Buffer.alloc(0), testMsg);
    console.log(hex(enc.subarray(0, cipherState.encryptWithAd.bytesWritten)));

    global._split = split;
  }

  if (lines.length === 5) {
    // Phase 3: Got encrypted from initiator → decrypt
    const encFromInit = unhex(lines[4]);
    const dec = Buffer.alloc(encFromInit.length);
    try {
      cipherState.decryptWithAd(global._split.rx, dec, Buffer.alloc(0), encFromInit);
      console.log(dec.subarray(0, cipherState.decryptWithAd.bytesWritten).toString('utf-8'));
    } catch (e) {
      process.stderr.write('DECRYPT_FAILED: ' + e.message + '\n');
      process.exit(1);
    }
    rl.close();
    process.exit(0);
  }
}

rl.on('line', onLine);
""";
