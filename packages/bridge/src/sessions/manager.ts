import { EventEmitter } from 'node:events';
import type { SessionInfo, SessionStatus, HookEvent } from '@claude-remote/protocol';
import { hookReceiver } from '../hooks/receiver.js';
import { logger } from '../logger.js';

class Session {
  public info: SessionInfo;
  private outputBuffer: string[] = [];

  constructor(id: string, name?: string) {
    this.info = {
      id,
      name: name ?? id,
      status: 'active',
      cwd: '',
      startedAt: new Date().toISOString(),
      outputLines: 0,
      durationSeconds: 0,
    };
  }

  updateStatus(status: SessionStatus): void {
    this.info.status = status;
    this.info.durationSeconds = Math.floor(
      (Date.now() - new Date(this.info.startedAt).getTime()) / 1000,
    );
    if (status === 'completed' || status === 'error') {
      this.info.endedAt = new Date().toISOString();
    }
  }

  appendOutput(content: string): void {
    this.outputBuffer.push(...content.split('\n'));
    this.info.outputLines = this.outputBuffer.length;
    if (this.outputBuffer.length > 5000) {
      this.outputBuffer = this.outputBuffer.slice(-5000);
    }
  }

  getRecentOutput(lines = 100): string[] {
    return this.outputBuffer.slice(-lines);
  }
}

class SessionManager extends EventEmitter {
  private sessions = new Map<string, Session>();

  constructor() {
    super();
    hookReceiver.on('hook', (event: HookEvent) => this.handleHookEvent(event));
  }

  private handleHookEvent(event: HookEvent): void {
    const sessionId = event.sessionId ?? 'unknown';
    if (!this.sessions.has(sessionId) && sessionId !== 'unknown') {
      this.sessions.set(sessionId, new Session(sessionId));
    }
    const session = this.sessions.get(sessionId);
    if (!session) return;

    switch (event.hook) {
      case 'PreToolUse':
        session.updateStatus('active');
        if (event.tool && event.input) {
          this.emit('permission_request', sessionId, event.tool, event.input);
        }
        break;
      case 'PostToolUse':
        session.updateStatus('active');
        if (event.output) {
          session.appendOutput(event.output);
          this.emit('session_output', sessionId, event.output);
        }
        break;
      case 'Notification':
        if (event.message) {
          session.appendOutput(event.message);
          this.emit('session_output', sessionId, event.message);
        }
        break;
      case 'Stop':
        session.updateStatus('completed');
        break;
    }
    this.emit('session_update', session.info);
  }

  getSessions(): SessionInfo[] {
    return Array.from(this.sessions.values()).map(s => s.info);
  }

  getSession(id: string): SessionInfo | undefined {
    return this.sessions.get(id)?.info;
  }

  getSessionOutput(id: string, lines = 100): string[] {
    return this.sessions.get(id)?.getRecentOutput(lines) ?? [];
  }

  registerSession(id: string, name: string, cwd: string): void {
    if (!this.sessions.has(id)) {
      const session = new Session(id, name);
      session.info.cwd = cwd;
      this.sessions.set(id, session);
      this.emit('session_update', session.info);
      logger.info({ sessionId: id, name }, 'Session registered');
    }
  }
}

export const sessionManager = new SessionManager();
