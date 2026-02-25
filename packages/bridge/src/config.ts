import { existsSync, readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { z } from 'zod';

const DEFAULT_DATA_DIR = join(homedir(), '.claude-remote');

const BridgeConfigSchema = z.object({
  port: z.number().int().min(1024).max(65535).default(3847),
  dataDir: z.string().default(DEFAULT_DATA_DIR),
  tunnel: z.object({
    enabled: z.boolean().default(true),
    provider: z.enum(['bore', 'cloudflare', 'none']).default('bore'),
    relay: z.string().default('bore.pub'),
  }).default({}),
  mdns: z.object({
    enabled: z.boolean().default(true),
  }).default({}),
  notifications: z.object({
    enabled: z.boolean().default(true),
    provider: z.enum(['ntfy', 'gotify', 'webhook', 'none']).default('ntfy'),
    target: z.string().default('claude-remote'),
    server: z.string().default('https://ntfy.sh'),
  }).default({}),
  maxPairedDevices: z.number().int().min(0).default(5),
});

export type BridgeConfig = z.infer<typeof BridgeConfigSchema>;

export function getConfigPath(customPath?: string): string {
  return customPath ?? join(DEFAULT_DATA_DIR, 'config.json');
}

export async function loadConfig(customPath?: string): Promise<BridgeConfig> {
  const configPath = getConfigPath(customPath);
  let rawConfig: Record<string, unknown> = {};
  if (existsSync(configPath)) {
    rawConfig = JSON.parse(readFileSync(configPath, 'utf-8'));
  }
  if (process.env.CLAUDE_REMOTE_PORT) {
    rawConfig.port = parseInt(process.env.CLAUDE_REMOTE_PORT, 10);
  }
  const config = BridgeConfigSchema.parse(rawConfig);
  if (!existsSync(config.dataDir)) {
    mkdirSync(config.dataDir, { recursive: true, mode: 0o700 });
  }
  return config;
}

export function saveConfig(config: BridgeConfig, customPath?: string): void {
  const configPath = getConfigPath(customPath);
  const dir = dirname(configPath);
  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true, mode: 0o700 });
  }
  writeFileSync(configPath, JSON.stringify(config, null, 2), { mode: 0o600 });
}
