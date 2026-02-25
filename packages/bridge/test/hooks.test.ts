import { describe, it, expect, vi, beforeEach } from 'vitest';
import Fastify from 'fastify';
import { hookReceiver, registerHookRoutes } from '../src/hooks/receiver.js';
import type { HookEvent } from '@claude-remote/protocol';

describe('hooks/receiver', () => {
  let app: ReturnType<typeof Fastify>;

  beforeEach(async () => {
    app = Fastify();
    await registerHookRoutes(app);
    await app.ready();
    hookReceiver.removeAllListeners();
  });

  async function postHook(route: string, body: Record<string, unknown>) {
    return app.inject({ method: 'POST', url: route, payload: body });
  }

  describe('PreToolUse', () => {
    it('emits hook event with tool info', async () => {
      const events: HookEvent[] = [];
      hookReceiver.on('hook', (e) => events.push(e));

      const res = await postHook('/hooks/pre-tool-use', {
        session_id: 'sess-1',
        tool_name: 'Bash',
        tool_input: { command: 'ls' },
      });

      expect(res.statusCode).toBe(200);
      expect(events).toHaveLength(1);
      expect(events[0].hook).toBe('PreToolUse');
      expect(events[0].sessionId).toBe('sess-1');
      expect(events[0].tool).toBe('Bash');
      expect(events[0].input).toEqual({ command: 'ls' });
    });
  });

  describe('PostToolUse', () => {
    it('emits hook event with tool output', async () => {
      const events: HookEvent[] = [];
      hookReceiver.on('hook', (e) => events.push(e));

      const res = await postHook('/hooks/post-tool-use', {
        session_id: 'sess-1',
        tool_name: 'Bash',
        tool_output: 'file1.txt\nfile2.txt',
      });

      expect(res.statusCode).toBe(200);
      expect(events).toHaveLength(1);
      expect(events[0].hook).toBe('PostToolUse');
      expect(events[0].output).toBe('file1.txt\nfile2.txt');
    });
  });

  describe('Notification', () => {
    it('emits notification hook event', async () => {
      const events: HookEvent[] = [];
      hookReceiver.on('hook', (e) => events.push(e));

      const res = await postHook('/hooks/notification', {
        session_id: 'sess-2',
        message: 'Build completed',
      });

      expect(res.statusCode).toBe(200);
      expect(events).toHaveLength(1);
      expect(events[0].hook).toBe('Notification');
      expect(events[0].message).toBe('Build completed');
    });
  });

  describe('Stop', () => {
    it('emits stop hook event', async () => {
      const events: HookEvent[] = [];
      hookReceiver.on('hook', (e) => events.push(e));

      const res = await postHook('/hooks/stop', {
        session_id: 'sess-1',
        last_assistant_message: 'Done!',
      });

      expect(res.statusCode).toBe(200);
      expect(events).toHaveLength(1);
      expect(events[0].hook).toBe('Stop');
      expect(events[0].lastAssistantMessage).toBe('Done!');
    });
  });

  describe('response format', () => {
    it('returns { ok: true } for all hook routes', async () => {
      const routes = [
        '/hooks/pre-tool-use',
        '/hooks/post-tool-use',
        '/hooks/notification',
        '/hooks/stop',
      ];
      for (const route of routes) {
        const res = await postHook(route, {});
        expect(JSON.parse(res.body)).toEqual({ ok: true });
      }
    });
  });

  describe('timestamp', () => {
    it('includes ISO timestamp in hook events', async () => {
      const events: HookEvent[] = [];
      hookReceiver.on('hook', (e) => events.push(e));
      await postHook('/hooks/notification', { message: 'test' });

      expect(events[0].timestamp).toMatch(/^\d{4}-\d{2}-\d{2}T/);
    });
  });
});
