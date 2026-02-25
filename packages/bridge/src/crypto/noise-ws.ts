/**
 * Noise-encrypted WebSocket wrapper.
 *
 * Handshake protocol over WebSocket:
 * 1. Client sends binary: [0x01 (version)] [32 bytes client pubkey] [48 bytes Noise msg1]
 * 2. Bridge responds binary: [48 bytes Noise msg2]
 * 3. All subsequent messages: encrypted binary frames (ciphertext + 16-byte MAC)
 *
 * The client's public key is sent in cleartext so the bridge can identify
 * which paired device is connecting and look up the correct KK pre-shared key.
 * This is safe because it's a PUBLIC key — no secrecy needed.
 */

import type { WebSocket } from 'ws';
import { respondHandshake, type NoiseSession } from './noise.js';
import { loadPairedDevices, type BridgeKeys } from './keys.js';
import { logger } from '../logger.js';

const HANDSHAKE_VERSION = 0x01;
const PUBKEY_LEN = 32;
const HANDSHAKE_MSG1_LEN = 48;
const EXPECTED_FIRST_MSG_LEN = 1 + PUBKEY_LEN + HANDSHAKE_MSG1_LEN; // 81 bytes

export type NoiseMessageHandler = (message: string) => void;

/**
 * Wraps a raw WebSocket with Noise encryption.
 * Handles the handshake automatically, then provides encrypted send/receive.
 */
export class NoiseWebSocketServer {
  private session: NoiseSession | null = null;
  private messageHandler: NoiseMessageHandler | null = null;
  private closeHandler: (() => void) | null = null;

  constructor(
    private socket: WebSocket,
    private keys: BridgeKeys,
    private dataDir: string,
  ) {
    this.socket.binaryType = 'nodebuffer';
    this.socket.once('message', (data: Buffer) => this.handleHandshake(data));
    this.socket.on('close', () => this.closeHandler?.());
    this.socket.on('error', (err: Error) => {
      logger.warn({ err }, 'WebSocket error');
    });
  }

  private handleHandshake(data: Buffer): void {
    try {
      if (data.length < EXPECTED_FIRST_MSG_LEN) {
        throw new Error(`Invalid handshake: expected ${EXPECTED_FIRST_MSG_LEN} bytes, got ${data.length}`);
      }

      const version = data[0];
      if (version !== HANDSHAKE_VERSION) {
        throw new Error(`Unsupported protocol version: ${version}`);
      }

      const clientPubKey = data.subarray(1, 1 + PUBKEY_LEN);
      const msg1 = data.subarray(1 + PUBKEY_LEN, 1 + PUBKEY_LEN + HANDSHAKE_MSG1_LEN);

      // Verify client is a paired device
      const paired = loadPairedDevices(this.dataDir);
      const clientKeyB64 = clientPubKey.toString('base64');
      const device = paired.find(d => d.publicKey === clientKeyB64);
      if (!device) {
        throw new Error('Unknown device — not paired');
      }

      // Perform Noise KK handshake (responder)
      const { message2, session } = respondHandshake(
        this.keys,
        clientPubKey,
        msg1,
      );

      this.session = session;

      // Send handshake response
      this.socket.send(message2);

      logger.info({ device: device.name }, 'Noise handshake completed');

      // Switch to encrypted message handling
      this.socket.on('message', (ciphertext: Buffer) => {
        this.handleEncryptedMessage(ciphertext);
      });
    } catch (err) {
      logger.warn({ err }, 'Handshake failed');
      this.socket.close(4001, 'Handshake failed');
    }
  }

  private handleEncryptedMessage(ciphertext: Buffer): void {
    if (!this.session) return;
    try {
      const plaintext = this.session.decrypt(ciphertext);
      const message = plaintext.toString('utf-8');
      this.messageHandler?.(message);
    } catch (err) {
      logger.warn({ err }, 'Failed to decrypt message');
      this.socket.close(4002, 'Decryption failed');
    }
  }

  /** Send a JSON message encrypted through the Noise session. */
  send(json: string): void {
    if (!this.session || this.socket.readyState !== 1) return;
    const plaintext = Buffer.from(json, 'utf-8');
    const ciphertext = this.session.encrypt(plaintext);
    this.socket.send(ciphertext);
  }

  /** Register handler for decrypted messages. */
  onMessage(handler: NoiseMessageHandler): void {
    this.messageHandler = handler;
  }

  /** Register close handler. */
  onClose(handler: () => void): void {
    this.closeHandler = handler;
  }

  get isEstablished(): boolean {
    return this.session?.established ?? false;
  }
}
