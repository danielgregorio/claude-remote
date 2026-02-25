/**
 * Noise Protocol implementation for Claude Remote.
 *
 * Pattern: Noise_KK_25519_ChaChaPoly_BLAKE2b
 *
 * KK: both parties know each other's static keys beforehand (from QR pairing).
 * Provides mutual authentication from the first message + forward secrecy
 * via ephemeral Curve25519 DH.
 *
 * PSK is bound into the prologue (hashed alongside protocol identifier),
 * providing an additional authentication factor from the QR code pairing.
 * This prevents handshake completion unless both sides share the same PSK.
 *
 * Handshake flow (2 messages):
 *   Initiator (app)  -->  msg1 (e, es, ss)  -->  Responder (bridge)
 *   Initiator (app)  <--  msg2 (e, ee, se)  <--  Responder (bridge)
 *   [handshake complete — split produces transport cipher states]
 *
 * Uses noise-protocol (low-level) for KK pattern support.
 * Uses ChaCha20-Poly1305 AEAD with auto-incrementing nonces for transport.
 */

import noiseProtocol from 'noise-protocol';
import noiseCipher from 'noise-protocol/cipher';
import noiseCipherState from 'noise-protocol/cipher-state';
import { createHash } from 'node:crypto';
import { logger } from '../logger.js';
import type { BridgeKeys } from './keys.js';

const cipher = noiseCipher();
const cipherState = noiseCipherState({ cipher });

const MACLEN = cipherState.MACLEN; // 16 bytes for Poly1305

export interface NoiseSession {
  encrypt(plaintext: Buffer): Buffer;
  decrypt(ciphertext: Buffer): Buffer;
  remotePublicKey: Buffer;
  established: boolean;
}

/**
 * Build a prologue that binds the PSK into the handshake.
 * Both sides must use the same PSK for the handshake to succeed.
 */
function buildPrologue(psk: Buffer): Buffer {
  const hash = createHash('blake2b512');
  hash.update(Buffer.from('claude-remote/v1'));
  hash.update(psk);
  return hash.digest();
}

/**
 * Create a NoiseSession from split cipher states for transport encryption.
 */
function createSession(
  txState: Buffer,
  rxState: Buffer,
  remotePublicKey: Buffer,
): NoiseSession {
  return {
    remotePublicKey: Buffer.from(remotePublicKey),
    established: true,

    encrypt(plaintext: Buffer): Buffer {
      const out = Buffer.alloc(plaintext.length + MACLEN);
      cipherState.encryptWithAd(txState, out, Buffer.alloc(0), plaintext);
      return out.subarray(0, cipherState.encryptWithAd.bytesWritten);
    },

    decrypt(ciphertext: Buffer): Buffer {
      const out = Buffer.alloc(ciphertext.length);
      cipherState.decryptWithAd(rxState, out, Buffer.alloc(0), ciphertext);
      return out.subarray(0, cipherState.decryptWithAd.bytesWritten);
    },
  };
}

// Maximum handshake message size for KK pattern (ephemeral key + MAC)
const MAX_MSG_SIZE = 256;

/**
 * Bridge (responder) side of the Noise KK handshake.
 *
 * @param keys - Bridge's static keypair and PSK
 * @param remoteStaticKey - App's static public key (known from pairing)
 * @param message1 - First handshake message from the app (initiator)
 * @returns message2 to send back, and the established NoiseSession
 */
export function respondHandshake(
  keys: BridgeKeys,
  remoteStaticKey: Buffer,
  message1: Buffer,
): { message2: Buffer; session: NoiseSession } {
  const prologue = buildPrologue(keys.psk);
  const keypair = {
    publicKey: keys.staticPublicKey,
    secretKey: keys.staticSecretKey,
  };

  const state = noiseProtocol.initialize(
    'KK', false, prologue, keypair, null, remoteStaticKey,
  );

  // Process message 1 from initiator (e, es, ss)
  const payload1 = Buffer.alloc(MAX_MSG_SIZE);
  noiseProtocol.readMessage(state, message1, payload1);

  // Generate message 2 (e, ee, se) — completes handshake
  const msg2Buf = Buffer.alloc(MAX_MSG_SIZE);
  const split = noiseProtocol.writeMessage(state, Buffer.alloc(0), msg2Buf);

  if (!split) {
    noiseProtocol.destroy(state);
    throw new Error('Noise KK handshake did not complete after message 2');
  }

  const message2 = Buffer.from(msg2Buf.subarray(0, noiseProtocol.writeMessage.bytes));
  noiseProtocol.destroy(state);

  logger.info('Noise KK handshake completed (responder)');

  return {
    message2,
    session: createSession(split.tx, split.rx, remoteStaticKey),
  };
}

/**
 * App (initiator) side of the Noise KK handshake.
 * Exported for testing and potential in-process use.
 *
 * @param staticKeypair - Initiator's Curve25519 keypair
 * @param psk - Pre-shared key (from QR pairing)
 * @param remoteStaticKey - Bridge's static public key (from QR pairing)
 * @returns message1 to send, and a function to complete the handshake with message2
 */
export function initiateHandshake(
  staticKeypair: { publicKey: Buffer; secretKey: Buffer },
  psk: Buffer,
  remoteStaticKey: Buffer,
): { message1: Buffer; complete: (message2: Buffer) => NoiseSession } {
  const prologue = buildPrologue(psk);

  const state = noiseProtocol.initialize(
    'KK', true, prologue, staticKeypair, null, remoteStaticKey,
  );

  // Generate message 1 (e, es, ss)
  const msg1Buf = Buffer.alloc(MAX_MSG_SIZE);
  noiseProtocol.writeMessage(state, Buffer.alloc(0), msg1Buf);
  const message1 = Buffer.from(msg1Buf.subarray(0, noiseProtocol.writeMessage.bytes));

  return {
    message1,
    complete(message2: Buffer): NoiseSession {
      // Process message 2 (e, ee, se) — completes handshake
      const payload2 = Buffer.alloc(MAX_MSG_SIZE);
      const split = noiseProtocol.readMessage(state, message2, payload2);

      if (!split) {
        noiseProtocol.destroy(state);
        throw new Error('Noise KK handshake did not complete after message 2');
      }

      noiseProtocol.destroy(state);
      logger.info('Noise KK handshake completed (initiator)');

      return createSession(split.tx, split.rx, remoteStaticKey);
    },
  };
}
