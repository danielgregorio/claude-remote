import type { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import type { HookEvent } from '@claude-remote/protocol';
import { logger } from '../logger.js';
import { EventEmitter } from 'node:events';

export interface HookEventBus {
  on(event: 'hook', listener: (hookEvent: HookEvent) => void): void;
  off(event: 'hook', listener: (hookEvent: HookEvent) => void): void;
}

class HookReceiver extends EventEmitter implements HookEventBus {
  handlePreToolUse(body: Record<string, unknown>): void {
    const event: HookEvent = {
      hook: 'PreToolUse',
      sessionId: body.session_id as string | undefined,
      tool: body.tool_name as string | undefined,
      input: body.tool_input as Record<string, unknown> | undefined,
      timestamp: new Date().toISOString(),
    };
    logger.debug({ event }, 'PreToolUse hook received');
    this.emit('hook', event);
  }

  handlePostToolUse(body: Record<string, unknown>): void {
    const event: HookEvent = {
      hook: 'PostToolUse',
      sessionId: body.session_id as string | undefined,
      tool: body.tool_name as string | undefined,
      output: body.tool_output as string | undefined,
      timestamp: new Date().toISOString(),
    };
    logger.debug({ event }, 'PostToolUse hook received');
    this.emit('hook', event);
  }

  handleNotification(body: Record<string, unknown>): void {
    const event: HookEvent = {
      hook: 'Notification',
      sessionId: body.session_id as string | undefined,
      message: body.message as string | undefined,
      timestamp: new Date().toISOString(),
    };
    logger.debug({ event }, 'Notification hook received');
    this.emit('hook', event);
  }

  handleStop(body: Record<string, unknown>): void {
    const event: HookEvent = {
      hook: 'Stop',
      sessionId: body.session_id as string | undefined,
      lastAssistantMessage: body.last_assistant_message as string | undefined,
      timestamp: new Date().toISOString(),
    };
    logger.debug({ event }, 'Stop hook received');
    this.emit('hook', event);
  }
}

export const hookReceiver = new HookReceiver();

export async function registerHookRoutes(app: FastifyInstance): Promise<void> {
  app.post('/hooks/pre-tool-use', async (req: FastifyRequest, reply: FastifyReply) => {
    hookReceiver.handlePreToolUse(req.body as Record<string, unknown>);
    return reply.code(200).send({ ok: true });
  });

  app.post('/hooks/post-tool-use', async (req: FastifyRequest, reply: FastifyReply) => {
    hookReceiver.handlePostToolUse(req.body as Record<string, unknown>);
    return reply.code(200).send({ ok: true });
  });

  app.post('/hooks/notification', async (req: FastifyRequest, reply: FastifyReply) => {
    hookReceiver.handleNotification(req.body as Record<string, unknown>);
    return reply.code(200).send({ ok: true });
  });

  app.post('/hooks/stop', async (req: FastifyRequest, reply: FastifyReply) => {
    hookReceiver.handleStop(req.body as Record<string, unknown>);
    return reply.code(200).send({ ok: true });
  });
}
