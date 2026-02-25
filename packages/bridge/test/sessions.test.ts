import { describe, it, expect, vi, beforeEach } from 'vitest';
import { hookReceiver } from '../src/hooks/receiver.js';
import { sessionManager } from '../src/sessions/manager.js';
import type { SessionInfo, HookEvent } from '@claude-remote/protocol';

describe('sessions/manager', () => {
  beforeEach(() => {
    // Clear any existing sessions by removing all listeners and re-creating state
    sessionManager.removeAllListeners();
    hookReceiver.removeAllListeners();
    // Re-subscribe (since constructor only runs once for singleton)
    hookReceiver.on('hook', (event: HookEvent) => {
      // @ts-expect-error accessing private method for test
      sessionManager.handleHookEvent(event);
    });
  });

  function emitHook(event: Partial<HookEvent> & { hook: HookEvent['hook'] }): void {
    hookReceiver.emit('hook', {
      timestamp: new Date().toISOString(),
      ...event,
    } as HookEvent);
  }

  describe('session creation', () => {
    it('creates session on first hook with sessionId', () => {
      emitHook({ hook: 'PreToolUse', sessionId: 'test-1', tool: 'Bash' });
      const sessions = sessionManager.getSessions();
      expect(sessions.some(s => s.id === 'test-1')).toBe(true);
    });

    it('does not create session for unknown sessionId', () => {
      const before = sessionManager.getSessions().length;
      emitHook({ hook: 'Notification' }); // no sessionId
      expect(sessionManager.getSessions().length).toBe(before);
    });

    it('reuses existing session', () => {
      emitHook({ hook: 'PreToolUse', sessionId: 'sess-x', tool: 'Bash' });
      emitHook({ hook: 'PostToolUse', sessionId: 'sess-x', output: 'done' });
      const matching = sessionManager.getSessions().filter(s => s.id === 'sess-x');
      expect(matching).toHaveLength(1);
    });
  });

  describe('status transitions', () => {
    it('sets active on PreToolUse', () => {
      emitHook({ hook: 'PreToolUse', sessionId: 's1', tool: 'Read' });
      expect(sessionManager.getSession('s1')?.status).toBe('active');
    });

    it('sets active on PostToolUse', () => {
      emitHook({ hook: 'PreToolUse', sessionId: 's2', tool: 'Bash' });
      emitHook({ hook: 'PostToolUse', sessionId: 's2', output: 'ok' });
      expect(sessionManager.getSession('s2')?.status).toBe('active');
    });

    it('sets completed on Stop', () => {
      emitHook({ hook: 'PreToolUse', sessionId: 's3', tool: 'Bash' });
      emitHook({ hook: 'Stop', sessionId: 's3' });
      const session = sessionManager.getSession('s3');
      expect(session?.status).toBe('completed');
      expect(session?.endedAt).toBeDefined();
    });
  });

  describe('output buffer', () => {
    it('stores output from PostToolUse', () => {
      emitHook({ hook: 'PostToolUse', sessionId: 'out-1', output: 'line1\nline2' });
      const output = sessionManager.getSessionOutput('out-1');
      expect(output).toEqual(['line1', 'line2']);
    });

    it('stores output from Notification', () => {
      emitHook({ hook: 'Notification', sessionId: 'out-2', message: 'Build done' });
      const output = sessionManager.getSessionOutput('out-2');
      expect(output).toEqual(['Build done']);
    });

    it('tracks outputLines count', () => {
      emitHook({ hook: 'PostToolUse', sessionId: 'out-3', output: 'a\nb\nc' });
      expect(sessionManager.getSession('out-3')?.outputLines).toBe(3);
    });

    it('returns empty for unknown session', () => {
      expect(sessionManager.getSessionOutput('nonexistent')).toEqual([]);
    });
  });

  describe('events', () => {
    it('emits session_update on hook', () => {
      const updates: SessionInfo[] = [];
      sessionManager.on('session_update', (info: SessionInfo) => updates.push(info));

      emitHook({ hook: 'PreToolUse', sessionId: 'ev-1', tool: 'Bash' });
      expect(updates).toHaveLength(1);
      expect(updates[0].id).toBe('ev-1');
    });

    it('emits session_output on PostToolUse with output', () => {
      const outputs: { sid: string; content: string }[] = [];
      sessionManager.on('session_output', (sid: string, content: string) => {
        outputs.push({ sid, content });
      });

      emitHook({ hook: 'PostToolUse', sessionId: 'ev-2', output: 'hello' });
      expect(outputs).toHaveLength(1);
      expect(outputs[0]).toEqual({ sid: 'ev-2', content: 'hello' });
    });

    it('emits permission_request on PreToolUse with tool+input', () => {
      const requests: { sid: string; tool: string }[] = [];
      sessionManager.on('permission_request', (sid: string, tool: string) => {
        requests.push({ sid, tool });
      });

      emitHook({ hook: 'PreToolUse', sessionId: 'ev-3', tool: 'Write', input: { path: '/tmp/x' } });
      expect(requests).toHaveLength(1);
      expect(requests[0]).toEqual({ sid: 'ev-3', tool: 'Write' });
    });
  });

  describe('registerSession', () => {
    it('manually registers a session', () => {
      sessionManager.registerSession('manual-1', 'My Session', '/home/user');
      const session = sessionManager.getSession('manual-1');
      expect(session).toBeDefined();
      expect(session?.name).toBe('My Session');
      expect(session?.cwd).toBe('/home/user');
    });

    it('does not overwrite existing session', () => {
      emitHook({ hook: 'PreToolUse', sessionId: 'dup-1', tool: 'Bash' });
      sessionManager.registerSession('dup-1', 'New Name', '/other');
      expect(sessionManager.getSession('dup-1')?.name).toBe('dup-1'); // keeps original
    });
  });
});
