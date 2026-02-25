import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { mkdtempSync, rmSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { loadConfig, saveConfig, getConfigPath } from '../src/config.js';

describe('config', () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = mkdtempSync(join(tmpdir(), 'cr-config-'));
  });

  afterEach(() => {
    rmSync(tempDir, { recursive: true, force: true });
    delete process.env.CLAUDE_REMOTE_PORT;
  });

  describe('getConfigPath', () => {
    it('returns custom path when provided', () => {
      expect(getConfigPath('/custom/config.json')).toBe('/custom/config.json');
    });

    it('returns default path when no custom path', () => {
      const path = getConfigPath();
      expect(path).toContain('.claude-remote');
      expect(path).toContain('config.json');
    });
  });

  describe('loadConfig', () => {
    it('returns defaults when no config file exists', async () => {
      const config = await loadConfig(join(tempDir, 'nonexistent.json'));
      expect(config.port).toBe(3847);
      expect(config.tunnel.enabled).toBe(true);
      expect(config.tunnel.provider).toBe('bore');
      expect(config.mdns.enabled).toBe(true);
      expect(config.notifications.enabled).toBe(true);
      expect(config.notifications.provider).toBe('ntfy');
      expect(config.maxPairedDevices).toBe(5);
    });

    it('loads and merges config from file', async () => {
      const configPath = join(tempDir, 'config.json');
      writeFileSync(configPath, JSON.stringify({
        port: 9999,
        tunnel: { enabled: false },
        dataDir: tempDir,
      }));
      const config = await loadConfig(configPath);
      expect(config.port).toBe(9999);
      expect(config.tunnel.enabled).toBe(false);
      expect(config.mdns.enabled).toBe(true); // default preserved
    });

    it('respects CLAUDE_REMOTE_PORT env var', async () => {
      process.env.CLAUDE_REMOTE_PORT = '8888';
      const config = await loadConfig(join(tempDir, 'x.json'));
      expect(config.port).toBe(8888);
    });

    it('creates data dir if it does not exist', async () => {
      const configPath = join(tempDir, 'config.json');
      const dataDir = join(tempDir, 'data-subdir');
      writeFileSync(configPath, JSON.stringify({ dataDir }));
      await loadConfig(configPath);
      expect(existsSync(dataDir)).toBe(true);
    });

    it('validates port range', async () => {
      const configPath = join(tempDir, 'bad-port.json');
      writeFileSync(configPath, JSON.stringify({ port: 80, dataDir: tempDir }));
      await expect(loadConfig(configPath)).rejects.toThrow();
    });
  });

  describe('saveConfig', () => {
    it('writes config to file', () => {
      const configPath = join(tempDir, 'saved.json');
      const config = {
        port: 4000,
        dataDir: tempDir,
        tunnel: { enabled: true, provider: 'bore' as const, relay: 'bore.pub' },
        mdns: { enabled: true },
        notifications: { enabled: true, provider: 'ntfy' as const, target: 'test', server: 'https://ntfy.sh' },
        maxPairedDevices: 3,
      };
      saveConfig(config, configPath);
      expect(existsSync(configPath)).toBe(true);
    });

    it('creates parent directories', () => {
      const configPath = join(tempDir, 'deep', 'nested', 'config.json');
      saveConfig({
        port: 3847,
        dataDir: tempDir,
        tunnel: { enabled: true, provider: 'bore', relay: 'bore.pub' },
        mdns: { enabled: true },
        notifications: { enabled: true, provider: 'ntfy', target: 'test', server: 'https://ntfy.sh' },
        maxPairedDevices: 5,
      }, configPath);
      expect(existsSync(configPath)).toBe(true);
    });
  });
});
