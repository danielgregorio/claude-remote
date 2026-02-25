import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { logger } from '../logger.js';

const CLAUDE_SETTINGS_PATH = join(homedir(), '.claude', 'settings.json');

interface HookEntry {
  type: string;
  command: string;
}

interface HookMatcher {
  matcher: string;
  hooks: HookEntry[];
}

interface ClaudeSettings {
  hooks?: Record<string, HookMatcher[]>;
  [key: string]: unknown;
}

const HOOK_TYPES = ['PreToolUse', 'PostToolUse', 'Notification', 'Stop'] as const;

const HOOK_ROUTES: Record<string, string> = {
  PreToolUse: '/hooks/pre-tool-use',
  PostToolUse: '/hooks/post-tool-use',
  Notification: '/hooks/notification',
  Stop: '/hooks/stop',
};

function buildHookCommand(port: number, route: string): string {
  return `curl -sf -X POST http://localhost:${port}${route} -H 'Content-Type: application/json' -d @- 2>/dev/null || true`;
}

const HOOK_MARKER = 'claude-remote-bridge';

function isClaudeRemoteHook(entry: HookEntry): boolean {
  return entry.command?.includes(HOOK_MARKER) || entry.command?.includes('/hooks/');
}

export function generateHooksConfig(port: number): Record<string, HookMatcher[]> {
  const hooks: Record<string, HookMatcher[]> = {};
  for (const hookType of HOOK_TYPES) {
    hooks[hookType] = [{
      matcher: '',
      hooks: [{
        type: 'command',
        command: `# ${HOOK_MARKER}\n${buildHookCommand(port, HOOK_ROUTES[hookType])}`,
      }],
    }];
  }
  return hooks;
}

export function previewChanges(port: number): { before: string; after: string; diff: string[] } {
  let settings: ClaudeSettings = {};
  if (existsSync(CLAUDE_SETTINGS_PATH)) {
    settings = JSON.parse(readFileSync(CLAUDE_SETTINGS_PATH, 'utf-8'));
  }

  const before = JSON.stringify(settings, null, 2);
  const merged = mergeHooks(settings, port);
  const after = JSON.stringify(merged, null, 2);

  const diff: string[] = [];
  for (const hookType of HOOK_TYPES) {
    const existing = settings.hooks?.[hookType];
    const hasExisting = existing?.some(m => m.hooks?.some(isClaudeRemoteHook));
    if (hasExisting) {
      diff.push(`  ${hookType}: update existing hook → localhost:${port}`);
    } else {
      diff.push(`  ${hookType}: + add hook → POST localhost:${port}${HOOK_ROUTES[hookType]}`);
    }
  }

  return { before, after, diff };
}

function mergeHooks(settings: ClaudeSettings, port: number): ClaudeSettings {
  const result = { ...settings };
  if (!result.hooks) result.hooks = {};

  const newHooks = generateHooksConfig(port);

  for (const hookType of HOOK_TYPES) {
    const existing = result.hooks[hookType] ?? [];

    // Remove any previous claude-remote hooks
    const filtered = existing.map(matcher => ({
      ...matcher,
      hooks: (matcher.hooks ?? []).filter(h => !isClaudeRemoteHook(h)),
    })).filter(matcher => matcher.hooks.length > 0);

    // Add new claude-remote hooks
    result.hooks[hookType] = [...filtered, ...newHooks[hookType]];
  }

  return result;
}

export function installHooks(port: number): void {
  const dir = join(homedir(), '.claude');
  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true });
  }

  let settings: ClaudeSettings = {};
  if (existsSync(CLAUDE_SETTINGS_PATH)) {
    settings = JSON.parse(readFileSync(CLAUDE_SETTINGS_PATH, 'utf-8'));
  }

  const merged = mergeHooks(settings, port);
  writeFileSync(CLAUDE_SETTINGS_PATH, JSON.stringify(merged, null, 2) + '\n');
  logger.info('Hooks installed in %s', CLAUDE_SETTINGS_PATH);
}

export function uninstallHooks(): void {
  if (!existsSync(CLAUDE_SETTINGS_PATH)) {
    logger.info('No settings.json found — nothing to remove');
    return;
  }

  const settings: ClaudeSettings = JSON.parse(readFileSync(CLAUDE_SETTINGS_PATH, 'utf-8'));
  if (!settings.hooks) {
    logger.info('No hooks configured — nothing to remove');
    return;
  }

  for (const hookType of HOOK_TYPES) {
    const existing = settings.hooks[hookType];
    if (!existing) continue;
    settings.hooks[hookType] = existing.map(matcher => ({
      ...matcher,
      hooks: (matcher.hooks ?? []).filter(h => !isClaudeRemoteHook(h)),
    })).filter(matcher => matcher.hooks.length > 0);
    if (settings.hooks[hookType].length === 0) {
      delete settings.hooks[hookType];
    }
  }

  if (Object.keys(settings.hooks).length === 0) {
    delete settings.hooks;
  }

  writeFileSync(CLAUDE_SETTINGS_PATH, JSON.stringify(settings, null, 2) + '\n');
  logger.info('Claude Remote hooks removed from %s', CLAUDE_SETTINGS_PATH);
}
