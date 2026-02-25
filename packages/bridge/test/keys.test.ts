import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { mkdtempSync, rmSync, existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { generateKeypair, loadOrCreateKeys, addPairedDevice, loadPairedDevices } from '../src/crypto/keys.js';

describe('crypto/keys', () => {
  let dataDir: string;

  beforeEach(() => {
    dataDir = mkdtempSync(join(tmpdir(), 'cr-test-'));
  });

  afterEach(() => {
    rmSync(dataDir, { recursive: true, force: true });
  });

  describe('generateKeypair', () => {
    it('generates 32-byte Curve25519 keys', () => {
      const keys = generateKeypair();
      expect(keys.staticSecretKey).toBeInstanceOf(Buffer);
      expect(keys.staticPublicKey).toBeInstanceOf(Buffer);
      expect(keys.psk).toBeInstanceOf(Buffer);
      expect(keys.staticSecretKey.length).toBe(32);
      expect(keys.staticPublicKey.length).toBe(32);
      expect(keys.psk.length).toBe(32);
    });

    it('generates unique keypairs each time', () => {
      const a = generateKeypair();
      const b = generateKeypair();
      expect(a.staticPublicKey.equals(b.staticPublicKey)).toBe(false);
      expect(a.staticSecretKey.equals(b.staticSecretKey)).toBe(false);
      expect(a.psk.equals(b.psk)).toBe(false);
    });

    it('public key is derived from secret key (deterministic DH)', () => {
      // Two keypairs should have different public keys since they have different secrets
      const a = generateKeypair();
      const b = generateKeypair();
      expect(a.staticSecretKey.equals(b.staticSecretKey)).toBe(false);
      expect(a.staticPublicKey.equals(b.staticPublicKey)).toBe(false);
    });
  });

  describe('loadOrCreateKeys', () => {
    it('creates keys file on first run', async () => {
      const keys = await loadOrCreateKeys(dataDir);
      expect(keys.staticPublicKey.length).toBe(32);
      expect(existsSync(join(dataDir, 'keys.json'))).toBe(true);
    });

    it('loads existing keys on subsequent runs', async () => {
      const first = await loadOrCreateKeys(dataDir);
      const second = await loadOrCreateKeys(dataDir);
      expect(first.staticPublicKey.equals(second.staticPublicKey)).toBe(true);
      expect(first.staticSecretKey.equals(second.staticSecretKey)).toBe(true);
      expect(first.psk.equals(second.psk)).toBe(true);
    });

    it('stores keys as base64 in JSON', async () => {
      await loadOrCreateKeys(dataDir);
      const stored = JSON.parse(readFileSync(join(dataDir, 'keys.json'), 'utf-8'));
      expect(typeof stored.staticSecretKey).toBe('string');
      expect(typeof stored.staticPublicKey).toBe('string');
      expect(typeof stored.psk).toBe('string');
      expect(Buffer.from(stored.staticPublicKey, 'base64').length).toBe(32);
    });

    it('creates data dir if it does not exist', async () => {
      const nested = join(dataDir, 'sub', 'dir');
      await loadOrCreateKeys(nested);
      expect(existsSync(join(nested, 'keys.json'))).toBe(true);
    });
  });

  describe('paired devices', () => {
    it('adds a paired device', async () => {
      await loadOrCreateKeys(dataDir);
      await addPairedDevice(dataDir, {
        publicKey: 'dGVzdA==',
        name: 'Test Phone',
        pairedAt: new Date().toISOString(),
      });
      const devices = loadPairedDevices(dataDir);
      expect(devices).toHaveLength(1);
      expect(devices[0].name).toBe('Test Phone');
    });

    it('updates existing device by public key', async () => {
      await loadOrCreateKeys(dataDir);
      const pk = 'dGVzdA==';
      await addPairedDevice(dataDir, { publicKey: pk, name: 'Old Name', pairedAt: '2024-01-01' });
      await addPairedDevice(dataDir, { publicKey: pk, name: 'New Name', pairedAt: '2024-06-01' });
      const devices = loadPairedDevices(dataDir);
      expect(devices).toHaveLength(1);
      expect(devices[0].name).toBe('New Name');
    });

    it('returns empty array when no keys file exists', () => {
      const devices = loadPairedDevices(join(dataDir, 'nonexistent'));
      expect(devices).toEqual([]);
    });
  });
});
