import mdns from 'multicast-dns';
import { hostname } from 'node:os';
import { logger } from '../logger.js';
import { randomBytes } from 'node:crypto';

const SERVICE_TYPE = '_claude-remote._tcp.local';
let instance: ReturnType<typeof mdns> | null = null;

export function startMdnsAdvertisement(port: number): string {
  const serviceId = `claude-remote-${randomBytes(4).toString('hex')}`;
  instance = mdns();

  instance.on('query', (query) => {
    const isForUs = query.questions.some(
      q => q.name === SERVICE_TYPE || q.name === `${serviceId}.${SERVICE_TYPE}`,
    );
    if (isForUs) {
      instance!.respond({
        answers: [
          {
            name: `${serviceId}.${SERVICE_TYPE}`,
            type: 'SRV',
            data: { port, weight: 0, priority: 10, target: `${hostname()}.local` },
          },
          {
            name: `${serviceId}.${SERVICE_TYPE}`,
            type: 'TXT',
            data: [`id=${serviceId}`, `v=1`],
          },
        ],
      });
    }
  });

  logger.info({ serviceId, port }, 'mDNS advertisement started');
  return serviceId;
}

export function stopMdnsAdvertisement(): void {
  instance?.destroy();
  instance = null;
}
