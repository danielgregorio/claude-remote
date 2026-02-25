#!/usr/bin/env npx tsx
/**
 * Generate deterministic Noise KK test vectors for cross-platform verification.
 *
 * These vectors let the Dart (Flutter) implementation verify byte-compatibility
 * with the Node.js noise-protocol library.
 *
 * Usage:
 *   npx tsx packages/bridge/scripts/noise-test-vectors.ts
 *   npx tsx packages/bridge/scripts/noise-test-vectors.ts > test-vectors.json
 */

import noiseProtocol from 'noise-protocol';
import noiseCipher from 'noise-protocol/cipher';
import noiseCipherState from 'noise-protocol/cipher-state';
import { createHash } from 'node:crypto';

const cipher = noiseCipher();
const cipherState = noiseCipherState({ cipher });

// Use seedKeygen for deterministic keys
const INITIATOR_SEED = Buffer.alloc(32);
INITIATOR_SEED.write('initiator-seed-for-test-vectors!'); // exactly 32 chars

const RESPONDER_SEED = Buffer.alloc(32);
RESPONDER_SEED.write('responder-seed-for-test-vectors!'); // exactly 32 chars

const PSK = Buffer.alloc(32);
PSK.write('psk-for-test-vectors-00000000000'); // exactly 32 chars

function buildPrologue(psk: Buffer): Buffer {
  const hash = createHash('blake2b512');
  hash.update(Buffer.from('claude-remote/v1'));
  hash.update(psk);
  return hash.digest();
}

function generateVectors() {
  // Generate deterministic keypairs from seeds
  const initiatorKeys = noiseProtocol.seedKeygen(INITIATOR_SEED);
  const responderKeys = noiseProtocol.seedKeygen(RESPONDER_SEED);

  const prologue = buildPrologue(PSK);

  // --- Initiator writes message 1 ---
  const initiatorState = noiseProtocol.initialize(
    'KK', true, prologue,
    initiatorKeys, null, responderKeys.publicKey,
  );

  const msg1Buf = Buffer.alloc(256);
  noiseProtocol.writeMessage(initiatorState, Buffer.alloc(0), msg1Buf);
  const msg1 = Buffer.from(msg1Buf.subarray(0, noiseProtocol.writeMessage.bytes));

  // --- Responder reads message 1, writes message 2 ---
  const responderState = noiseProtocol.initialize(
    'KK', false, prologue,
    responderKeys, null, initiatorKeys.publicKey,
  );

  const payload1 = Buffer.alloc(256);
  noiseProtocol.readMessage(responderState, msg1, payload1);

  const msg2Buf = Buffer.alloc(256);
  const responderSplit = noiseProtocol.writeMessage(responderState, Buffer.alloc(0), msg2Buf);
  const msg2 = Buffer.from(msg2Buf.subarray(0, noiseProtocol.writeMessage.bytes));

  // --- Initiator reads message 2 ---
  const payload2 = Buffer.alloc(256);
  const initiatorSplit = noiseProtocol.readMessage(initiatorState, msg2, payload2);

  if (!responderSplit || !initiatorSplit) {
    throw new Error('Handshake did not complete');
  }

  // --- Transport encryption tests ---
  // Initiator sends a message (uses tx cipher state)
  const testPlaintext1 = Buffer.from('Hello from initiator!');
  const testCipher1 = Buffer.alloc(testPlaintext1.length + cipherState.MACLEN);
  cipherState.encryptWithAd(initiatorSplit.tx, testCipher1, Buffer.alloc(0), testPlaintext1);
  const encrypted1 = testCipher1.subarray(0, cipherState.encryptWithAd.bytesWritten);

  // Responder sends a message (uses tx cipher state)
  const testPlaintext2 = Buffer.from('Hello from responder!');
  const testCipher2 = Buffer.alloc(testPlaintext2.length + cipherState.MACLEN);
  cipherState.encryptWithAd(responderSplit.tx, testCipher2, Buffer.alloc(0), testPlaintext2);
  const encrypted2 = testCipher2.subarray(0, cipherState.encryptWithAd.bytesWritten);

  // Initiator sends a second message (nonce = 1 now)
  const testPlaintext3 = Buffer.from('Second message from initiator');
  const testCipher3 = Buffer.alloc(testPlaintext3.length + cipherState.MACLEN);
  cipherState.encryptWithAd(initiatorSplit.tx, testCipher3, Buffer.alloc(0), testPlaintext3);
  const encrypted3 = testCipher3.subarray(0, cipherState.encryptWithAd.bytesWritten);

  // Destroy states
  noiseProtocol.destroy(initiatorState);
  noiseProtocol.destroy(responderState);

  // Build test vectors
  const vectors = {
    _comment: 'Noise_KK_25519_ChaChaPoly_BLAKE2b test vectors for cross-platform verification',
    _generated: new Date().toISOString(),

    keys: {
      initiator: {
        seed: INITIATOR_SEED.toString('hex'),
        publicKey: Buffer.from(initiatorKeys.publicKey).toString('hex'),
        secretKey: Buffer.from(initiatorKeys.secretKey).toString('hex'),
      },
      responder: {
        seed: RESPONDER_SEED.toString('hex'),
        publicKey: Buffer.from(responderKeys.publicKey).toString('hex'),
        secretKey: Buffer.from(responderKeys.secretKey).toString('hex'),
      },
    },

    psk: PSK.toString('hex'),
    prologue: prologue.toString('hex'),

    handshake: {
      message1: {
        bytes: msg1.toString('hex'),
        length: msg1.length,
        ephemeralPublicKey: msg1.subarray(0, 32).toString('hex'),
        encryptedPayload: msg1.subarray(32).toString('hex'),
      },
      message2: {
        bytes: msg2.toString('hex'),
        length: msg2.length,
        ephemeralPublicKey: msg2.subarray(0, 32).toString('hex'),
        encryptedPayload: msg2.subarray(32).toString('hex'),
      },
    },

    transport: {
      _note: 'After handshake, initiator tx/responder rx use one key; responder tx/initiator rx use another',
      initiatorToResponder: [
        {
          nonce: 0,
          plaintext: testPlaintext1.toString('hex'),
          plaintextUtf8: testPlaintext1.toString('utf-8'),
          ciphertext: Buffer.from(encrypted1).toString('hex'),
        },
        {
          nonce: 1,
          plaintext: testPlaintext3.toString('hex'),
          plaintextUtf8: testPlaintext3.toString('utf-8'),
          ciphertext: Buffer.from(encrypted3).toString('hex'),
        },
      ],
      responderToInitiator: [
        {
          nonce: 0,
          plaintext: testPlaintext2.toString('hex'),
          plaintextUtf8: testPlaintext2.toString('utf-8'),
          ciphertext: Buffer.from(encrypted2).toString('hex'),
        },
      ],
    },
  };

  return vectors;
}

const vectors = generateVectors();
console.log(JSON.stringify(vectors, null, 2));
