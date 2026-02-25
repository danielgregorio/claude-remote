/// Full cross-platform handshake test: Dart initiator ↔ Node.js responder.
///
/// Spawns the Node.js noise-responder.ts script and performs a complete
/// Noise KK handshake + transport encryption over stdin/stdout pipes.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';

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

void main() {
  group('Dart ↔ Node.js Noise KK handshake', () {
    test('complete handshake + transport encryption', () async {
      final x25519 = X25519();

      // Generate initiator (Dart) keypair
      final initiatorKp = await x25519.newKeyPair();
      final initiatorPriv =
          Uint8List.fromList(await initiatorKp.extractPrivateKeyBytes());
      final initiatorPub =
          Uint8List.fromList((await initiatorKp.extractPublicKey()).bytes);

      // Use a fixed seed for the responder (Node.js) so it's deterministic
      final responderSeed = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        responderSeed[i] = (i * 7 + 13) & 0xff;
      }

      // PSK
      final psk = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        psk[i] = (i * 3 + 42) & 0xff;
      }

      // Start Node.js responder — find the repo root
      var repoRoot = Directory.current.path;
      while (!File('$repoRoot/package.json').existsSync()) {
        repoRoot = Directory(repoRoot).parent.path;
      }
      final process = await Process.start(
        'npx',
        ['tsx', 'packages/bridge/scripts/noise-responder.ts'],
        workingDirectory: repoRoot,
      );

      // Collect stderr for debugging
      final stderrBuf = StringBuffer();
      process.stderr.transform(utf8.decoder).listen(stderrBuf.write);

      // Send: responder_seed, psk, initiator_pub
      process.stdin.writeln(hexEncode(responderSeed));
      process.stdin.writeln(hexEncode(psk));
      process.stdin.writeln(hexEncode(initiatorPub));
      await process.stdin.flush();

      // Read responder public key
      final stdoutLines = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      final lineIterator = StreamIterator(stdoutLines);

      // Line 1: responder public key
      expect(await lineIterator.moveNext(), isTrue,
          reason: 'Expected responder public key line. stderr: $stderrBuf');
      final responderPubHex = lineIterator.current;
      final responderPub = hexDecode(responderPubHex);
      expect(responderPub.length, equals(32),
          reason: 'Responder public key should be 32 bytes');

      // Build prologue
      final prologue = await NoiseKK.buildPrologue(psk);

      // Create initiator handshake
      final initiator = NoiseKK(
        staticPrivate: initiatorPriv,
        staticPublic: initiatorPub,
        remoteStaticPublic: responderPub,
      );

      // Write msg1
      final msg1 = await initiator.writeMessage1(prologue);
      expect(msg1.length, equals(48));

      // Send msg1 to Node.js
      process.stdin.writeln(hexEncode(msg1));
      await process.stdin.flush();

      // Line 2: msg2 from responder
      expect(await lineIterator.moveNext(), isTrue,
          reason: 'Expected msg2 line. stderr: $stderrBuf');
      final msg2Hex = lineIterator.current;
      final msg2 = hexDecode(msg2Hex);
      expect(msg2.length, equals(48),
          reason: 'msg2 should be 48 bytes, got ${msg2.length}');

      // Complete handshake
      final session = await initiator.readMessage2(msg2);
      expect(session.established, isTrue);

      // Line 3: encrypted message from responder
      expect(await lineIterator.moveNext(), isTrue,
          reason: 'Expected encrypted message from responder. stderr: $stderrBuf');
      final encFromResponderHex = lineIterator.current;
      final encFromResponder = hexDecode(encFromResponderHex);

      // Decrypt message from responder
      final decrypted = await session.decrypt(encFromResponder);
      final message = utf8.decode(decrypted);
      expect(message, equals('Hello from Node.js responder!'));

      // Encrypt a message from Dart → Node.js
      final dartMessage =
          Uint8List.fromList(utf8.encode('Hello from Dart initiator!'));
      final encFromDart = await session.encrypt(dartMessage);
      process.stdin.writeln(hexEncode(encFromDart));
      await process.stdin.flush();

      // Line 4: Node.js decrypted our message
      expect(await lineIterator.moveNext(), isTrue,
          reason:
              'Expected decrypted message confirmation. stderr: $stderrBuf');
      final decryptedByNode = lineIterator.current;
      expect(decryptedByNode, equals('Hello from Dart initiator!'));

      // Clean up
      await lineIterator.cancel();
      await process.stdin.close();
      final exitCode = await process.exitCode;
      expect(exitCode, equals(0),
          reason: 'Node.js process should exit cleanly. stderr: $stderrBuf');
    }, timeout: Timeout(Duration(seconds: 60)));
  });
}
