import { networkInterfaces, hostname } from 'node:os';
import qrcode from 'qrcode-terminal';
import type { BridgeConfig } from '../config.js';
import type { BridgeKeys } from './keys.js';
import { PROTOCOL_VERSION, type PairingPayload } from '@claude-remote/protocol';

function getLocalIP(): string {
  for (const [, addrs] of Object.entries(networkInterfaces())) {
    if (!addrs) continue;
    for (const addr of addrs) {
      if (addr.family === 'IPv4' && !addr.internal) return addr.address;
    }
  }
  return '127.0.0.1';
}

export function buildPairingPayload(
  config: BridgeConfig,
  keys: BridgeKeys,
  tunnelInfo?: { url: string; port: number },
): PairingPayload {
  const payload: PairingPayload = {
    v: PROTOCOL_VERSION,
    name: hostname(),
    pk: keys.staticPublicKey.toString('base64'),
    psk: keys.psk.toString('base64'),
    lan: { port: config.port, mdns: '_claude-remote._tcp' },
  };
  if (tunnelInfo) payload.relay = tunnelInfo;
  return payload;
}

export async function generatePairingQR(
  config: BridgeConfig,
  keys: BridgeKeys,
  tunnelInfo?: { url: string; port: number },
): Promise<void> {
  const payload = buildPairingPayload(config, keys, tunnelInfo);
  const json = JSON.stringify(payload);
  const encoded = Buffer.from(json).toString('base64url');
  const uri = `claude-remote://pair/${encoded}`;

  console.log('\n  Claude Remote Bridge\n  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
  console.log('  Scan this QR code with Claude Remote app:\n');
  qrcode.generate(uri, { small: true }, (code: string) => {
    console.log(code.split('\n').map((l: string) => `  ${l}`).join('\n'));
  });
  console.log(`\n  Bridge:  ${payload.name}`);
  console.log(`  LAN:     ${getLocalIP()}:${config.port}`);
  if (tunnelInfo) console.log(`  Tunnel:  ${tunnelInfo.url}:${tunnelInfo.port}`);
  console.log(`  Payload: ${json.length} bytes\n`);
}
