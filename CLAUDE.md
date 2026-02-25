# Claude Remote

Open-source mobile companion app for Claude Code sessions. Monitor, interact, and control Claude Code from your phone.

## Architecture

Monorepo with 3 packages:

- `packages/protocol` — Shared TypeScript types and constants
- `packages/bridge` — Node.js/TypeScript bridge server
- `packages/app` — Flutter mobile app (iOS + Android)

### Bridge Server

The bridge sits between Claude Code (desktop) and the mobile app:

```
Claude Code --[hooks HTTP]--> Bridge Server --[Noise/WebSocket]--> Mobile App
```

**Key design decisions:**
- **Noise Protocol (KKpsk2)** for E2E encryption — Curve25519/ChaCha20-Poly1305/BLAKE2s
- **Claude Code hooks only** — never reads internal files
- **Zero-config networking** — mDNS for LAN, bore tunnel for remote
- **Push via ntfy** — open-source, no sensitive content in notifications

### Pairing Flow

Bridge generates QR code with: public key + PSK + connection info. App scans once, pairing is permanent.

### Build

```bash
npm install
npm run build       # builds protocol then bridge
npm run test        # runs vitest
```

### Development

```bash
npm run dev:bridge  # watch mode with tsx
```
