import { randomBytes } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import noiseProtocol from 'noise-protocol';
import { logger } from '../logger.js';

export interface BridgeKeys {
  staticSecretKey: Buffer;
  staticPublicKey: Buffer;
  psk: Buffer;
}

export interface PairedDevice {
  publicKey: string;
  name: string;
  pairedAt: string;
  lastSeen?: string;
}

interface StoredKeys {
  staticSecretKey: string;
  staticPublicKey: string;
  psk: string;
  pairedDevices: PairedDevice[];
}

/**
 * Generate a real Curve25519 keypair via noise-protocol (sodium-native).
 * Uses the same DH primitive as the Noise handshake.
 */
export function generateKeypair(): BridgeKeys {
  const kp = noiseProtocol.keygen();
  const staticSecretKey = Buffer.from(kp.secretKey);
  const staticPublicKey = Buffer.from(kp.publicKey);
  const psk = randomBytes(32);
  return { staticSecretKey, staticPublicKey, psk };
}

const KEYS_FILENAME = 'keys.json';

export async function loadOrCreateKeys(dataDir: string): Promise<BridgeKeys> {
  const path = join(dataDir, KEYS_FILENAME);
  if (existsSync(path)) {
    const stored: StoredKeys = JSON.parse(readFileSync(path, 'utf-8'));
    return {
      staticSecretKey: Buffer.from(stored.staticSecretKey, 'base64'),
      staticPublicKey: Buffer.from(stored.staticPublicKey, 'base64'),
      psk: Buffer.from(stored.psk, 'base64'),
    };
  }
  const keys = generateKeypair();
  if (!existsSync(dataDir)) {
    mkdirSync(dataDir, { recursive: true, mode: 0o700 });
  }
  const stored: StoredKeys = {
    staticSecretKey: keys.staticSecretKey.toString('base64'),
    staticPublicKey: keys.staticPublicKey.toString('base64'),
    psk: keys.psk.toString('base64'),
    pairedDevices: [],
  };
  writeFileSync(join(dataDir, KEYS_FILENAME), JSON.stringify(stored, null, 2), { mode: 0o600 });
  logger.info('Generated new Curve25519 bridge keypair');
  return keys;
}

export async function addPairedDevice(dataDir: string, device: PairedDevice): Promise<void> {
  const path = join(dataDir, KEYS_FILENAME);
  const stored: StoredKeys = JSON.parse(readFileSync(path, 'utf-8'));
  const existing = stored.pairedDevices.findIndex(d => d.publicKey === device.publicKey);
  if (existing >= 0) {
    stored.pairedDevices[existing] = device;
  } else {
    stored.pairedDevices.push(device);
  }
  writeFileSync(path, JSON.stringify(stored, null, 2), { mode: 0o600 });
}

export function loadPairedDevices(dataDir: string): PairedDevice[] {
  const path = join(dataDir, KEYS_FILENAME);
  if (!existsSync(path)) return [];
  const stored: StoredKeys = JSON.parse(readFileSync(path, 'utf-8'));
  return stored.pairedDevices;
}
