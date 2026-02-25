import { describe, it, expect } from 'vitest';
import { generateHooksConfig, previewChanges } from '../src/cli/hooks-install.js';

describe('cli/hooks-install', () => {
  describe('generateHooksConfig', () => {
    it('generates config for all 4 hook types', () => {
      const config = generateHooksConfig(3847);
      expect(Object.keys(config)).toEqual(['PreToolUse', 'PostToolUse', 'Notification', 'Stop']);
    });

    it('generates curl commands with correct port', () => {
      const config = generateHooksConfig(9000);
      const cmd = config.PreToolUse[0].hooks[0].command;
      expect(cmd).toContain('localhost:9000');
      expect(cmd).toContain('/hooks/pre-tool-use');
    });

    it('generates correct routes for each hook type', () => {
      const config = generateHooksConfig(3847);
      expect(config.PreToolUse[0].hooks[0].command).toContain('/hooks/pre-tool-use');
      expect(config.PostToolUse[0].hooks[0].command).toContain('/hooks/post-tool-use');
      expect(config.Notification[0].hooks[0].command).toContain('/hooks/notification');
      expect(config.Stop[0].hooks[0].command).toContain('/hooks/stop');
    });

    it('includes marker comment for identification', () => {
      const config = generateHooksConfig(3847);
      expect(config.PreToolUse[0].hooks[0].command).toContain('claude-remote-bridge');
    });

    it('uses command type for all hooks', () => {
      const config = generateHooksConfig(3847);
      for (const hookType of Object.values(config)) {
        for (const matcher of hookType) {
          for (const hook of matcher.hooks) {
            expect(hook.type).toBe('command');
          }
        }
      }
    });

    it('uses empty matcher to match all tools', () => {
      const config = generateHooksConfig(3847);
      for (const hookType of Object.values(config)) {
        for (const matcher of hookType) {
          expect(matcher.matcher).toBe('');
        }
      }
    });
  });

  describe('previewChanges', () => {
    it('returns diff with all hook types', () => {
      const { diff } = previewChanges(3847);
      expect(diff).toHaveLength(4);
      expect(diff.some(d => d.includes('PreToolUse'))).toBe(true);
      expect(diff.some(d => d.includes('PostToolUse'))).toBe(true);
      expect(diff.some(d => d.includes('Notification'))).toBe(true);
      expect(diff.some(d => d.includes('Stop'))).toBe(true);
    });

    it('returns valid JSON for before and after', () => {
      const { before, after } = previewChanges(3847);
      expect(() => JSON.parse(before)).not.toThrow();
      expect(() => JSON.parse(after)).not.toThrow();
    });
  });
});
