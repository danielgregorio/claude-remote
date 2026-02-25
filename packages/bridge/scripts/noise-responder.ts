#!/usr/bin/env npx tsx
/**
 * Noise KK responder for cross-platform handshake testing.
 *
 * Reads ALL input from stdin, then outputs ALL results.
 *
 * Input (4 or 5 lines):
 *   Line 1: responder_seed_hex
 *   Line 2: psk_hex
 *   Line 3: initiator_pub_hex
 *   Line 4: msg1_hex
 *   Line 5: (optional) encrypted_from_initiator_hex
 *
 * Output:
 *   Line 1: responder_pub_hex
 *   Line 2: msg2_hex
 *   Line 3: encrypted_from_responder_hex ("Hello from Node.js responder!")
 *   Line 4: (if line 5 provided) decrypted_from_initiator_utf8
 */

import noiseProtocol from 'noise-protocol';
import noiseCipher from 'noise-protocol/cipher';
import noiseCipherState from 'noise-protocol/cipher-state';
import { createHash } from 'node:crypto';

const cipher = noiseCipher();
const cipherState = noiseCipherState({ cipher });

function buildPrologue(psk: Buffer): Buffer {
  const hash = createHash('blake2b512');
  hash.update(Buffer.from('claude-remote/v1'));
  hash.update(psk);
  return hash.digest();
}

function hexToBuffer(hex: string): Buffer {
  return Buffer.from(hex.trim(), 'hex');
}

const chunks: Buffer[] = [];
process.stdin.on('data', (chunk) => chunks.push(chunk));
process.stdin.on('end', () => {
  try {
    const input = Buffer.concat(chunks).toString('utf-8');
    const lines = input.trim().split('\n').map(l => l.trim()).filter(l => l.length > 0);

    if (lines.length < 4) {
      process.stderr.write(`Expected >= 4 lines, got ${lines.length}\n`);
      process.exit(1);
    }

    const responderSeed = hexToBuffer(lines[0]);
    const psk = hexToBuffer(lines[1]);
    const initiatorPub = hexToBuffer(lines[2]);
    const msg1 = hexToBuffer(lines[3]);

    // Generate responder keys
    const responderKeys = noiseProtocol.seedKeygen(responderSeed);
    const prologue = buildPrologue(psk);

    // Line 1: responder public key
    console.log(Buffer.from(responderKeys.publicKey).toString('hex'));

    // Handshake
    const state = noiseProtocol.initialize(
      'KK', false, prologue,
      responderKeys, null, initiatorPub,
    );

    const payload1 = Buffer.alloc(256);
    noiseProtocol.readMessage(state, msg1, payload1);

    const msg2Buf = Buffer.alloc(256);
    const split = noiseProtocol.writeMessage(state, Buffer.alloc(0), msg2Buf);
    if (!split) {
      process.stderr.write('Handshake did not complete\n');
      process.exit(1);
    }

    const msg2 = Buffer.from(msg2Buf.subarray(0, noiseProtocol.writeMessage.bytes));
    // Line 2: msg2
    console.log(msg2.toString('hex'));

    noiseProtocol.destroy(state);

    // Line 3: encrypted test message from responder
    const testMessage = Buffer.from('Hello from Node.js responder!');
    const encrypted = Buffer.alloc(testMessage.length + cipherState.MACLEN);
    cipherState.encryptWithAd(split.tx, encrypted, Buffer.alloc(0), testMessage);
    console.log(Buffer.from(encrypted.subarray(0, cipherState.encryptWithAd.bytesWritten)).toString('hex'));

    // Line 4: decrypt message from initiator (if provided)
    if (lines.length >= 5) {
      const encFromInitiator = hexToBuffer(lines[4]);
      const decBuf = Buffer.alloc(encFromInitiator.length);
      cipherState.decryptWithAd(split.rx, decBuf, Buffer.alloc(0), encFromInitiator);
      console.log(decBuf.subarray(0, cipherState.decryptWithAd.bytesWritten).toString('utf-8'));
    }

  } catch (e) {
    process.stderr.write(`ERROR: ${(e as Error).message}\n${(e as Error).stack}\n`);
    process.exit(1);
  }
});
