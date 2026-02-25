import { describe, it, expect } from 'vitest';
import { generateKeypair } from '../src/crypto/keys.js';
import { initiateHandshake, respondHandshake } from '../src/crypto/noise.js';

describe('crypto/noise', () => {
  function makeKeypairs() {
    const bridge = generateKeypair();
    const app = generateKeypair();
    return { bridge, app };
  }

  describe('handshake', () => {
    it('completes KK handshake successfully', () => {
      const { bridge, app } = makeKeypairs();

      const { message1, complete } = initiateHandshake(
        { publicKey: app.staticPublicKey, secretKey: app.staticSecretKey },
        bridge.psk,
        bridge.staticPublicKey,
      );

      const { message2, session: bSession } = respondHandshake(
        bridge, app.staticPublicKey, message1,
      );

      const aSession = complete(message2);

      expect(bSession.established).toBe(true);
      expect(aSession.established).toBe(true);
    });

    it('produces 48-byte handshake messages', () => {
      const { bridge, app } = makeKeypairs();

      const { message1, complete } = initiateHandshake(
        { publicKey: app.staticPublicKey, secretKey: app.staticSecretKey },
        bridge.psk,
        bridge.staticPublicKey,
      );

      const { message2 } = respondHandshake(bridge, app.staticPublicKey, message1);

      expect(message1.length).toBe(48);
      expect(message2.length).toBe(48);
    });

    it('stores remote public key in session', () => {
      const { bridge, app } = makeKeypairs();

      const { message1, complete } = initiateHandshake(
        { publicKey: app.staticPublicKey, secretKey: app.staticSecretKey },
        bridge.psk,
        bridge.staticPublicKey,
      );

      const { message2, session: bSession } = respondHandshake(
        bridge, app.staticPublicKey, message1,
      );
      const aSession = complete(message2);

      expect(bSession.remotePublicKey.equals(app.staticPublicKey)).toBe(true);
      expect(aSession.remotePublicKey.equals(bridge.staticPublicKey)).toBe(true);
    });
  });

  describe('encrypt/decrypt', () => {
    it('roundtrips app → bridge', () => {
      const { bridge, app } = makeKeypairs();
      const { message1, complete } = initiateHandshake(
        { publicKey: app.staticPublicKey, secretKey: app.staticSecretKey },
        bridge.psk, bridge.staticPublicKey,
      );
      const { message2, session: bSession } = respondHandshake(bridge, app.staticPublicKey, message1);
      const aSession = complete(message2);

      const plaintext = Buffer.from('Hello Claude Remote!');
      const encrypted = aSession.encrypt(plaintext);
      const decrypted = bSession.decrypt(encrypted);
      expect(decrypted.equals(plaintext)).toBe(true);
    });

    it('roundtrips bridge → app', () => {
      const { bridge, app } = makeKeypairs();
      const { message1, complete } = initiateHandshake(
        { publicKey: app.staticPublicKey, secretKey: app.staticSecretKey },
        bridge.psk, bridge.staticPublicKey,
      );
      const { message2, session: bSession } = respondHandshake(bridge, app.staticPublicKey, message1);
      const aSession = complete(message2);

      const plaintext = Buffer.from(JSON.stringify({ type: 'session_list', sessions: [] }));
      const encrypted = bSession.encrypt(plaintext);
      const decrypted = aSession.decrypt(encrypted);
      expect(decrypted.equals(plaintext)).toBe(true);
    });

    it('handles large messages', () => {
      const { bridge, app } = makeKeypairs();
      const { message1, complete } = initiateHandshake(
        { publicKey: app.staticPublicKey, secretKey: app.staticSecretKey },
        bridge.psk, bridge.staticPublicKey,
      );
      const { message2, session: bSession } = respondHandshake(bridge, app.staticPublicKey, message1);
      const aSession = complete(message2);

      const large = Buffer.alloc(100_000, 0x42);
      const enc = aSession.encrypt(large);
      const dec = bSession.decrypt(enc);
      expect(dec.equals(large)).toBe(true);
    });

    it('handles empty messages', () => {
      const { bridge, app } = makeKeypairs();
      const { message1, complete } = initiateHandshake(
        { publicKey: app.staticPublicKey, secretKey: app.staticSecretKey },
        bridge.psk, bridge.staticPublicKey,
      );
      const { message2, session: bSession } = respondHandshake(bridge, app.staticPublicKey, message1);
      const aSession = complete(message2);

      const empty = Buffer.alloc(0);
      const enc = aSession.encrypt(empty);
      const dec = bSession.decrypt(enc);
      expect(dec.equals(empty)).toBe(true);
    });

    it('handles multiple sequential messages', () => {
      const { bridge, app } = makeKeypairs();
      const { message1, complete } = initiateHandshake(
        { publicKey: app.staticPublicKey, secretKey: app.staticSecretKey },
        bridge.psk, bridge.staticPublicKey,
      );
      const { message2, session: bSession } = respondHandshake(bridge, app.staticPublicKey, message1);
      const aSession = complete(message2);

      for (let i = 0; i < 50; i++) {
        const msg = Buffer.from(`Message ${i}`);
        const enc = aSession.encrypt(msg);
        const dec = bSession.decrypt(enc);
        expect(dec.toString()).toBe(`Message ${i}`);
      }
    });

    it('encrypted output is larger than plaintext (MAC overhead)', () => {
      const { bridge, app } = makeKeypairs();
      const { message1, complete } = initiateHandshake(
        { publicKey: app.staticPublicKey, secretKey: app.staticSecretKey },
        bridge.psk, bridge.staticPublicKey,
      );
      const { message2, session: bSession } = respondHandshake(bridge, app.staticPublicKey, message1);
      const aSession = complete(message2);

      const plaintext = Buffer.from('test');
      const encrypted = aSession.encrypt(plaintext);
      expect(encrypted.length).toBe(plaintext.length + 16); // +16 for Poly1305 MAC
    });
  });

  describe('authentication', () => {
    it('rejects wrong PSK', () => {
      const { bridge, app } = makeKeypairs();
      const wrongPsk = Buffer.alloc(32, 0xff);

      const { message1 } = initiateHandshake(
        { publicKey: app.staticPublicKey, secretKey: app.staticSecretKey },
        wrongPsk, // Wrong PSK — prologue won't match
        bridge.staticPublicKey,
      );

      // The handshake should fail because the prologue (which includes PSK) differs
      expect(() => {
        respondHandshake(bridge, app.staticPublicKey, message1);
      }).toThrow();
    });

    it('rejects wrong remote static key', () => {
      const { bridge, app } = makeKeypairs();
      const impersonator = generateKeypair();

      // Impersonator tries to connect as if they were the app
      const { message1 } = initiateHandshake(
        { publicKey: impersonator.staticPublicKey, secretKey: impersonator.staticSecretKey },
        bridge.psk,
        bridge.staticPublicKey,
      );

      // Bridge expects app's public key but gets impersonator's message
      expect(() => {
        respondHandshake(bridge, app.staticPublicKey, message1);
      }).toThrow();
    });

    it('tampered ciphertext is rejected', () => {
      const { bridge, app } = makeKeypairs();
      const { message1, complete } = initiateHandshake(
        { publicKey: app.staticPublicKey, secretKey: app.staticSecretKey },
        bridge.psk, bridge.staticPublicKey,
      );
      const { message2, session: bSession } = respondHandshake(bridge, app.staticPublicKey, message1);
      const aSession = complete(message2);

      const encrypted = aSession.encrypt(Buffer.from('secret'));
      encrypted[0] ^= 0xff; // tamper with first byte
      expect(() => bSession.decrypt(encrypted)).toThrow();
    });
  });
});
