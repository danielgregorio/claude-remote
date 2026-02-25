import Fastify from 'fastify';
import fastifyWebsocket from '@fastify/websocket';
import type { BridgeConfig } from './config.js';
import type { BridgeKeys } from './crypto/keys.js';
import { generatePairingQR } from './crypto/pairing.js';
import { NoiseWebSocketServer } from './crypto/noise-ws.js';
import { registerHookRoutes, hookReceiver } from './hooks/receiver.js';
import { sessionManager } from './sessions/manager.js';
import { startMdnsAdvertisement, stopMdnsAdvertisement } from './discovery/mdns.js';
import { startTunnel, stopTunnel, type TunnelInfo } from './discovery/tunnel.js';
import { initNotifications, sendNotification } from './notifications/dispatcher.js';
import { logger } from './logger.js';
import type { HealthResponse, BridgeMessage, AppMessage } from '@claude-remote/protocol';

const startTime = Date.now();

export async function startBridge(config: BridgeConfig, keys: BridgeKeys): Promise<void> {
  const app = Fastify({ logger: false });
  await app.register(fastifyWebsocket);

  // Health check
  app.get('/api/health', async () => {
    return {
      status: 'ok',
      version: '0.1.0',
      uptime: Math.floor((Date.now() - startTime) / 1000),
      sessions: sessionManager.getSessions().length,
      paired: true,
    } satisfies HealthResponse;
  });

  // Sessions list (unauthenticated — basic info only)
  app.get('/api/sessions', async () => ({
    sessions: sessionManager.getSessions(),
  }));

  // Hook routes (local only — from Claude Code)
  await registerHookRoutes(app);

  // WebSocket routes
  app.register(async function (fastify) {
    // Encrypted WebSocket — all app communication goes through here
    fastify.get('/ws', { websocket: true }, (socket) => {
      logger.info('New WebSocket connection — awaiting Noise handshake');
      const noiseWs = new NoiseWebSocketServer(socket, keys, config.dataDir);

      const subscriptions = new Set<string>();

      noiseWs.onMessage((json: string) => {
        try {
          const msg = JSON.parse(json) as AppMessage;
          handleAppMessage(noiseWs, msg, subscriptions);
        } catch (err) {
          logger.warn({ err }, 'Invalid message from app');
        }
      });

      const onOutput = (sid: string, content: string) => {
        if (subscriptions.has(sid)) {
          noiseWs.send(JSON.stringify({
            type: 'session_output',
            sessionId: sid,
            content,
            timestamp: new Date().toISOString(),
          } satisfies BridgeMessage));
        }
      };

      const onUpdate = () => {
        noiseWs.send(JSON.stringify({
          type: 'session_list',
          sessions: sessionManager.getSessions(),
        } satisfies BridgeMessage));
      };

      const onPermission = (sessionId: string, tool: string, input: Record<string, unknown>) => {
        if (subscriptions.has(sessionId)) {
          noiseWs.send(JSON.stringify({
            type: 'permission_request',
            sessionId,
            requestId: `${sessionId}-${Date.now()}`,
            tool,
            description: `Tool: ${tool}`,
            input,
          } satisfies BridgeMessage));
        }
      };

      sessionManager.on('session_output', onOutput);
      sessionManager.on('session_update', onUpdate);
      sessionManager.on('permission_request', onPermission);

      noiseWs.onClose(() => {
        sessionManager.off('session_output', onOutput);
        sessionManager.off('session_update', onUpdate);
        sessionManager.off('permission_request', onPermission);
        logger.info('Encrypted WebSocket connection closed');
      });
    });

    // Plaintext WebSocket for local dashboard (localhost only)
    fastify.get('/ws/dashboard', { websocket: true }, (socket) => {
      logger.info('Dashboard WebSocket connected (plaintext, local only)');
      socket.send(JSON.stringify({
        type: 'session_list',
        sessions: sessionManager.getSessions(),
      } satisfies BridgeMessage));

      const onUpdate = () => {
        if (socket.readyState === 1) {
          socket.send(JSON.stringify({
            type: 'session_list',
            sessions: sessionManager.getSessions(),
          } satisfies BridgeMessage));
        }
      };

      sessionManager.on('session_update', onUpdate);
      socket.on('close', () => sessionManager.off('session_update', onUpdate));
    });
  });

  // Notifications
  initNotifications(config);
  sessionManager.on('permission_request', (sessionId: string) => {
    sendNotification(
      sessionManager.getSession(sessionId)?.name ?? sessionId,
      'needs_permission',
      'high',
    );
  });
  hookReceiver.on('hook', (event) => {
    if (event.hook === 'Stop') {
      sendNotification(
        sessionManager.getSession(event.sessionId ?? '')?.name ?? 'Session',
        'completed',
        'low',
      );
    }
  });

  // Start server
  await app.listen({ port: config.port, host: '0.0.0.0' });
  logger.info({ port: config.port }, 'Bridge HTTP/WS server started');

  // mDNS
  if (config.mdns.enabled) {
    startMdnsAdvertisement(config.port);
  }

  // Tunnel
  let tunnelInfo: TunnelInfo | null = null;
  if (config.tunnel.enabled) {
    tunnelInfo = await startTunnel(config);
  }

  // Show pairing QR
  await generatePairingQR(config, keys, tunnelInfo ?? undefined);

  // Graceful shutdown
  const shutdown = async () => {
    logger.info('Shutting down...');
    stopMdnsAdvertisement();
    stopTunnel();
    await app.close();
    process.exit(0);
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

function handleAppMessage(
  ws: NoiseWebSocketServer,
  msg: AppMessage,
  subscriptions: Set<string>,
): void {
  switch (msg.type) {
    case 'list_sessions':
      ws.send(JSON.stringify({
        type: 'session_list',
        sessions: sessionManager.getSessions(),
      } satisfies BridgeMessage));
      break;
    case 'subscribe':
      subscriptions.add(msg.sessionId);
      break;
    case 'unsubscribe':
      subscriptions.delete(msg.sessionId);
      break;
    case 'approve':
      logger.info({ sessionId: msg.sessionId, requestId: msg.requestId }, 'Permission approved');
      break;
    case 'reject':
      logger.info({ sessionId: msg.sessionId, requestId: msg.requestId }, 'Permission rejected');
      break;
    case 'input':
      logger.info({ sessionId: msg.sessionId }, 'Input received from app');
      break;
  }
}
