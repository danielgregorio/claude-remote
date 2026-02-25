export const PROTOCOL_VERSION = 1;
export const DEFAULT_PORT = 3847;
export const MDNS_SERVICE_TYPE = '_claude-remote._tcp';

export interface PairingPayload {
  v: typeof PROTOCOL_VERSION;
  name: string;
  pk: string;   // Bridge Noise static public key (base64, 32 bytes)
  psk: string;  // Pre-shared key for KKpsk2 (base64, 32 bytes)
  lan: { port: number; mdns: string };
  relay?: { url: string; port: number };
}

export type SessionStatus = 'active' | 'waiting_input' | 'waiting_permission' | 'idle' | 'completed' | 'error';

export interface SessionInfo {
  id: string;
  name: string;
  status: SessionStatus;
  cwd: string;
  startedAt: string;
  endedAt?: string;
  outputLines: number;
  durationSeconds: number;
  model?: string;
}

// Bridge -> App messages
export interface SessionListMessage { type: 'session_list'; sessions: SessionInfo[] }
export interface SessionOutputMessage { type: 'session_output'; sessionId: string; content: string; timestamp: string }
export interface SessionStatusMessage { type: 'session_status'; sessionId: string; status: SessionStatus; detail?: string }
export interface PermissionRequestMessage { type: 'permission_request'; sessionId: string; requestId: string; tool: string; description: string; input?: Record<string, unknown> }
export interface QuestionMessage { type: 'question'; sessionId: string; requestId: string; question: string }
export interface BridgeStatusMessage { type: 'bridge_status'; uptime: number; activeSessions: number; version: string }

export type BridgeMessage = SessionListMessage | SessionOutputMessage | SessionStatusMessage | PermissionRequestMessage | QuestionMessage | BridgeStatusMessage;

// App -> Bridge messages
export interface ApproveAction { type: 'approve'; sessionId: string; requestId: string }
export interface RejectAction { type: 'reject'; sessionId: string; requestId: string }
export interface InputAction { type: 'input'; sessionId: string; text: string }
export interface SubscribeAction { type: 'subscribe'; sessionId: string }
export interface UnsubscribeAction { type: 'unsubscribe'; sessionId: string }
export interface ListSessionsAction { type: 'list_sessions' }

export type AppMessage = ApproveAction | RejectAction | InputAction | SubscribeAction | UnsubscribeAction | ListSessionsAction;

export interface HealthResponse { status: 'ok'; version: string; uptime: number; sessions: number; paired: boolean }

export interface HookEvent {
  hook: 'PreToolUse' | 'PostToolUse' | 'Notification' | 'Stop';
  sessionId?: string;
  tool?: string;
  input?: Record<string, unknown>;
  output?: string;
  message?: string;
  lastAssistantMessage?: string;
  timestamp: string;
}

export type NotificationPriority = 'high' | 'medium' | 'low';

export interface PushNotification {
  bridge: string;
  session: string;
  event: 'needs_input' | 'needs_permission' | 'completed' | 'error' | 'idle';
  priority: NotificationPriority;
  timestamp: string;
}
