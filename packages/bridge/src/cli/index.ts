#!/usr/bin/env node
import { Command } from 'commander';
import { startBridge } from '../server.js';
import { loadConfig, getConfigPath } from '../config.js';
import { generateKeypair, loadOrCreateKeys } from '../crypto/keys.js';
import { generatePairingQR } from '../crypto/pairing.js';
import { previewChanges, installHooks, uninstallHooks } from './hooks-install.js';
import { logger } from '../logger.js';
import { createInterface } from 'node:readline';

const program = new Command();
program
  .name('claude-remote-bridge')
  .description('Bridge server for Claude Remote')
  .version('0.1.0');

program
  .command('start')
  .description('Start the bridge server')
  .option('-p, --port <port>', 'Port to listen on', '3847')
  .option('-c, --config <path>', 'Path to config file')
  .option('--no-tunnel', 'Disable tunnel relay')
  .option('--no-mdns', 'Disable mDNS')
  .action(async (options) => {
    const config = await loadConfig(options.config);
    if (options.port) config.port = parseInt(options.port, 10);
    if (options.tunnel === false) config.tunnel.enabled = false;
    if (options.mdns === false) config.mdns.enabled = false;
    const keys = await loadOrCreateKeys(config.dataDir);
    logger.info('Starting Claude Remote Bridge...');
    await startBridge(config, keys);
  });

program
  .command('pair')
  .description('Display QR code for pairing')
  .action(async () => {
    const config = await loadConfig();
    const keys = await loadOrCreateKeys(config.dataDir);
    await generatePairingQR(config, keys);
  });

program
  .command('revoke')
  .description('Revoke all paired devices')
  .option('--all', 'Revoke all devices')
  .option('--show-qr', 'Show new QR after revoke')
  .action(async (options) => {
    if (!options.all) {
      logger.error('Specify --all to revoke all devices');
      process.exit(1);
    }
    const config = await loadConfig();
    const keys = generateKeypair();
    logger.info('All paired devices revoked. New keys generated.');
    if (options.showQr) {
      await generatePairingQR(config, keys);
    }
  });

const hooks = program
  .command('hooks')
  .description('Manage Claude Code hooks integration');

hooks
  .command('install')
  .description('Auto-configure Claude Code hooks to send events to the bridge')
  .option('-p, --port <port>', 'Bridge port', '3847')
  .option('-y, --yes', 'Skip confirmation')
  .action(async (options) => {
    const port = parseInt(options.port, 10);
    const { diff } = previewChanges(port);

    console.log('\n  Claude Remote — Hooks Install');
    console.log('  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    console.log('  Changes to ~/.claude/settings.json:\n');
    for (const line of diff) {
      console.log(line);
    }
    console.log('');

    if (!options.yes) {
      const rl = createInterface({ input: process.stdin, output: process.stdout });
      const answer = await new Promise<string>((resolve) => {
        rl.question('  Apply these changes? [y/N] ', resolve);
      });
      rl.close();
      if (answer.toLowerCase() !== 'y') {
        console.log('  Cancelled.');
        return;
      }
    }

    installHooks(port);
    console.log('  Hooks installed. Claude Code will now forward events to the bridge.');
    console.log('  Run `claude-remote-bridge start` to begin receiving hooks.\n');
  });

hooks
  .command('uninstall')
  .description('Remove Claude Remote hooks from Claude Code settings')
  .action(() => {
    uninstallHooks();
    console.log('  Claude Remote hooks removed from settings.');
  });

program.parse();
