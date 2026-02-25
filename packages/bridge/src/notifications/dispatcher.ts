import type { PushNotification, NotificationPriority } from '@claude-remote/protocol';
import type { BridgeConfig } from '../config.js';
import { logger } from '../logger.js';
import { hostname } from 'node:os';

interface NotificationProvider {
  send(n: PushNotification): Promise<void>;
}

class NtfyProvider implements NotificationProvider {
  constructor(private server: string, private topic: string) {}

  async send(n: PushNotification): Promise<void> {
    const body =
      n.event === 'needs_permission' ? `Session "${n.session}" needs permission` :
      n.event === 'needs_input' ? `Session "${n.session}" needs input` :
      n.event === 'completed' ? `Session "${n.session}" completed` :
      `Session "${n.session}": ${n.event}`;

    try {
      await fetch(`${this.server}/${this.topic}`, {
        method: 'POST',
        headers: {
          Title: `Claude Remote - ${n.bridge}`,
          Priority: n.priority === 'high' ? '5' : '3',
        },
        body,
      });
    } catch (err) {
      logger.warn({ err }, 'ntfy send failed');
    }
  }
}

let provider: NotificationProvider | null = null;

export function initNotifications(config: BridgeConfig): void {
  if (!config.notifications.enabled || config.notifications.provider === 'none') return;
  if (config.notifications.provider === 'ntfy') {
    provider = new NtfyProvider(config.notifications.server, config.notifications.target);
    logger.info('Notifications enabled via ntfy');
  }
}

export async function sendNotification(
  session: string,
  event: PushNotification['event'],
  priority: NotificationPriority = 'medium',
): Promise<void> {
  if (!provider) return;
  await provider.send({
    bridge: hostname(),
    session,
    event,
    priority,
    timestamp: new Date().toISOString(),
  });
}
