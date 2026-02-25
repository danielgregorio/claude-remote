import { spawn, type ChildProcess } from 'node:child_process';
import { logger } from '../logger.js';
import type { BridgeConfig } from '../config.js';

export interface TunnelInfo {
  url: string;
  port: number;
}

let tunnelProcess: ChildProcess | null = null;

export async function startTunnel(config: BridgeConfig): Promise<TunnelInfo | null> {
  if (!config.tunnel.enabled) return null;

  return new Promise((resolve) => {
    tunnelProcess = spawn('bore', ['local', config.port.toString(), '--to', config.tunnel.relay], {
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let resolved = false;

    tunnelProcess.stdout?.on('data', (data: Buffer) => {
      const match = data.toString().match(/(?:Listening at|Remote port:)\s*(\S+):(\d+)/i);
      if (match && !resolved) {
        resolved = true;
        resolve({ url: match[1], port: parseInt(match[2], 10) });
      }
    });

    tunnelProcess.on('error', (err) => {
      logger.warn({ err }, 'Tunnel failed to start (bore not installed?)');
      if (!resolved) { resolved = true; resolve(null); }
    });

    tunnelProcess.on('exit', () => {
      tunnelProcess = null;
      if (!resolved) { resolved = true; resolve(null); }
    });

    setTimeout(() => {
      if (!resolved) {
        resolved = true;
        logger.warn('Tunnel timed out');
        resolve(null);
      }
    }, 15_000);
  });
}

export function stopTunnel(): void {
  tunnelProcess?.kill('SIGTERM');
  tunnelProcess = null;
}
