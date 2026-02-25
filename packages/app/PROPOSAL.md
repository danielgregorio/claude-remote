# Claude Remote — Flutter App Proposal

## Overview

Mobile companion app for Claude Code sessions. Connects to the bridge server via Noise-encrypted WebSocket. Pairs via QR code scan.

---

## Tech Stack

| Concern | Package | Justification |
|---------|---------|---------------|
| **Framework** | Flutter 3.24+ | Cross-platform iOS/Android |
| **State management** | `riverpod` + `flutter_riverpod` | Compile-safe, testable, no boilerplate |
| **Crypto (primary)** | `sodium: ^3.4.6` + `sodium_libs: ^3.4.6` | libsodium FFI — formally verified X25519, ChaCha20-Poly1305, BLAKE2b. Same C lib as Node.js bridge. |
| **Crypto (fallback)** | `cryptography: ^2.9.0` | Pure Dart alternative if libsodium FFI is problematic. 302 likes, actively maintained. |
| **Noise protocol** | Custom `lib/crypto/noise_kk.dart` | ~200 lines implementing KK state machine over libsodium/cryptography primitives |
| **WebSocket** | `web_socket_channel: ^3.0.0` | Standard Dart WebSocket with binary frame support |
| **QR scanning** | `mobile_scanner: ^7.2.0` | MLKit/Apple Vision, 2,230 likes, 618k/week downloads |
| **Secure storage** | `flutter_secure_storage: ^10.0.0` | Keychain (iOS) / Keystore+Tink (Android), 4,390 likes. v10 security rewrite. |
| **mDNS discovery** | `bonsoir: ^6.1.0` | Cross-platform service discovery |
| **Push notifications** | `flutter_local_notifications` + ntfy HTTP polling | No Firebase dependency — ntfy is open source |
| **Navigation** | `go_router: ^14.0.0` | Declarative routing |
| **Serialization** | `freezed` + `json_serializable` | Immutable models matching protocol types |

---

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                    Flutter App                        │
│                                                      │
│  ┌──────────┐  ┌─────────────┐  ┌────────────────┐  │
│  │ UI Layer │  │ State Layer │  │  Crypto Layer  │  │
│  │ (Screens)│◀─│ (Riverpod)  │◀─│ (Noise KK)     │  │
│  └──────────┘  └──────┬──────┘  └───────┬────────┘  │
│                       │                  │           │
│               ┌───────▼──────────────────▼────────┐  │
│               │       Transport Layer             │  │
│               │  (WebSocket + Noise encrypt/      │  │
│               │   decrypt + connection manager)   │  │
│               └──────────────┬────────────────────┘  │
│                              │                       │
│               ┌──────────────▼────────────────────┐  │
│               │    Connection Discovery           │  │
│               │  mDNS → LAN IP → Tunnel relay     │  │
│               └───────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
                           │
                    WebSocket (binary)
                    Noise KK encrypted
                           │
                    ┌──────▼──────┐
                    │   Bridge    │
                    │   Server    │
                    └─────────────┘
```

### Layer breakdown

**1. Crypto Layer (`lib/crypto/`)**

```
lib/crypto/
  noise_kk.dart        # Noise KK state machine (initiator only)
  noise_session.dart   # Encrypt/decrypt wrapper after handshake
  key_store.dart       # Secure storage for static keypair + PSK + bridge pubkey
  pairing.dart         # QR code payload parser
```

The Noise KK implementation uses `cryptography` package:
- `X25519()` for Curve25519 DH (ephemeral + static key exchanges)
- `Chacha20.poly1305Aead()` for symmetric AEAD after key derivation
- `Blake2b()` for hashing (chaining key, handshake hash)
- HKDF via HMAC-BLAKE2b for key derivation (same as Noise spec)

The state machine implements exactly:
```
Prologue: BLAKE2b-512("claude-remote/v1" || PSK)

Pre-messages:
  -> s   (initiator static key known to responder)
  <- s   (responder static key known to initiator)

Messages:
  -> e, es, ss    (msg1: 48 bytes)
  <- e, ee, se    (msg2: 48 bytes)
  [split → tx CipherState, rx CipherState]
```

This must match the bridge's `noise-protocol` implementation exactly — same prologue construction, same pattern, same crypto primitives (except BLAKE2b vs BLAKE2s — we use BLAKE2b since that's what `noise-protocol` npm actually uses despite the Noise spec naming).

**2. Transport Layer (`lib/transport/`)**

```
lib/transport/
  bridge_connection.dart    # WebSocket lifecycle + Noise handshake
  connection_manager.dart   # Auto-reconnect, connection state
  message_codec.dart        # JSON ↔ Dart models, encrypt/decrypt wrapper
  discovery.dart            # mDNS → LAN IP → tunnel failover
```

Connection flow:
1. `ConnectionManager` tries endpoints in order: mDNS → last known IP → tunnel URL
2. Opens WebSocket to `ws://<host>:<port>/ws`
3. Sends handshake frame: `[0x01][32B pubkey][48B noise msg1]`
4. Receives `[48B noise msg2]`
5. Handshake complete → all subsequent frames are encrypted binary
6. Sends `{"type":"list_sessions"}` encrypted to get initial state
7. Subscribes to active sessions

Auto-reconnect with exponential backoff (1s → 2s → 4s → 8s → max 30s).

**3. State Layer (`lib/providers/`)**

```
lib/providers/
  connection_provider.dart   # ConnectionState: disconnected/connecting/handshake/connected
  sessions_provider.dart     # List<SessionInfo>, auto-refreshed from bridge
  session_detail_provider.dart  # Output stream for subscribed session
  pairing_provider.dart      # Pairing state machine
  settings_provider.dart     # User preferences
```

Key Riverpod providers:
```dart
// Connection state — drives UI globally
final connectionProvider = StateNotifierProvider<ConnectionNotifier, ConnectionState>(...);

// Sessions — rebuilt on every session_list message from bridge
final sessionsProvider = Provider<List<SessionInfo>>((ref) {
  return ref.watch(connectionProvider).sessions;
});

// Live output for a specific session
final sessionOutputProvider = StreamProvider.family<String, String>((ref, sessionId) {
  return ref.read(connectionProvider.notifier).outputStream(sessionId);
});
```

**4. UI Layer (`lib/screens/`)**

```
lib/screens/
  pairing/
    scan_qr_screen.dart     # Camera QR scanner
    pairing_success.dart    # Confirmation with bridge name
  dashboard/
    dashboard_screen.dart   # Session list + connection status
    session_card.dart       # Individual session widget
  session/
    session_detail.dart     # Live output + actions
    permission_dialog.dart  # Approve/reject tool use
    input_dialog.dart       # Text input for session
  settings/
    settings_screen.dart    # Bridge info, unpair, notifications
```

---

## Screen Designs

### 1. Pairing Screen (first launch)

```
┌─────────────────────────┐
│                         │
│    Claude Remote        │
│                         │
│  ┌───────────────────┐  │
│  │                   │  │
│  │   📷 Camera       │  │
│  │   viewfinder      │  │
│  │                   │  │
│  │   Scan QR code    │  │
│  │   from bridge     │  │
│  │                   │  │
│  └───────────────────┘  │
│                         │
│  Run on your computer:  │
│  claude-remote-bridge   │
│         pair            │
│                         │
└─────────────────────────┘
```

### 2. Dashboard (main screen)

```
┌─────────────────────────┐
│ Claude Remote    🏠 ●   │ ← connection indicator
│─────────────────────────│
│                         │
│ ┌─────────────────────┐ │
│ │ ● refactor-auth     │ │ ← green dot = active
│ │   active · 12m      │ │
│ │   ~/projects/api    │ │
│ └─────────────────────┘ │
│                         │
│ ┌─────────────────────┐ │
│ │ ⏳ fix-tests        │ │ ← yellow = waiting
│ │   needs permission  │ │
│ │   ~/projects/web    │ │
│ └─────────────────────┘ │
│                         │
│ ┌─────────────────────┐ │
│ │ ✓ deploy-prod       │ │ ← grey = completed
│ │   completed · 45m   │ │
│ │   ~/infra           │ │
│ └─────────────────────┘ │
│                         │
│         ⚙️              │
└─────────────────────────┘
```

### 3. Session Detail

```
┌─────────────────────────┐
│ ← refactor-auth    ●   │
│─────────────────────────│
│                         │
│ ┌─────────────────────┐ │
│ │ $ Reading file      │ │
│ │   src/auth.ts       │ │
│ │                     │ │
│ │ $ Editing file      │ │
│ │   src/auth.ts:42    │ │
│ │   +import {hash}... │ │
│ │                     │ │
│ │ $ Running tests     │ │
│ │   ✓ 12 passed       │ │
│ │   ✗ 1 failed        │ │
│ └─────────────────────┘ │
│                         │
│ ┌─────────────────────┐ │
│ │ 🔧 Bash: rm -rf tmp │ │
│ │                     │ │
│ │  [Approve] [Reject] │ │
│ └─────────────────────┘ │
│                         │
│ ┌─────────────────────┐ │
│ │ Type a message...   │ │
│ └─────────────────────┘ │
└─────────────────────────┘
```

### 4. Permission Dialog (push notification → opens this)

```
┌─────────────────────────┐
│                         │
│  ⚠️ Permission Request  │
│                         │
│  Session: refactor-auth │
│  Tool: Bash             │
│                         │
│  ┌───────────────────┐  │
│  │ rm -rf /tmp/build │  │
│  └───────────────────┘  │
│                         │
│  ┌─────────┐ ┌───────┐  │
│  │ Reject  │ │Approve│  │
│  └─────────┘ └───────┘  │
│                         │
└─────────────────────────┘
```

---

## Noise KK Implementation in Dart

The core ~200 lines. This is the most critical piece:

```dart
// lib/crypto/noise_kk.dart — pseudocode structure

class NoiseKK {
  // Symmetric state
  Uint8List _chainingKey;  // 64 bytes (BLAKE2b)
  Uint8List _h;            // handshake hash
  SecretKey? _cipherKey;
  int _nonce = 0;

  // Keys
  final SimpleKeyPair _staticKeypair;
  final SimplePublicKey _remoteStaticKey;
  SimpleKeyPair? _ephemeralKeypair;

  // Algorithms
  final _x25519 = X25519();
  final _aead = Chacha20.poly1305Aead();
  final _blake2b = Blake2b();

  /// Initialize symmetric state with protocol name
  void _initializeSymmetric() {
    final protocolName = utf8.encode('Noise_KK_25519_ChaChaPoly_BLAKE2b');
    _h = blake2b512(protocolName);  // if len <= HASHLEN, pad; else hash
    _chainingKey = Uint8List.fromList(_h);
  }

  /// Mix prologue (includes PSK binding)
  void _mixHash(Uint8List data) {
    _h = blake2b512(concat(_h, data));
  }

  /// HKDF via HMAC-BLAKE2b
  (Uint8List, Uint8List) _hkdf2(Uint8List chainingKey, Uint8List ikm) { ... }

  /// Mix key material from DH
  void _mixKey(Uint8List dhOutput) {
    final (ck, k) = _hkdf2(_chainingKey, dhOutput);
    _chainingKey = ck;
    _cipherKey = SecretKey(k);
    _nonce = 0;
  }

  /// Perform X25519 DH
  Future<Uint8List> _dh(SimpleKeyPair local, SimplePublicKey remote) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: local, remotePublicKey: remote,
    );
    return shared.extractBytes();
  }

  /// Initiator: generate msg1 (e, es, ss)
  Future<Uint8List> writeMessage1() async {
    _ephemeralKeypair = await _x25519.newKeyPair();
    final ePub = await _ephemeralKeypair!.extractPublicKey();

    // e: send ephemeral public key
    final eBytes = ePub.bytes;
    _mixHash(eBytes);

    // es: DH(e, rs)
    _mixKey(await _dh(_ephemeralKeypair!, _remoteStaticKey));

    // ss: DH(s, rs)
    _mixKey(await _dh(_staticKeypair, _remoteStaticKey));

    // Encrypt empty payload
    final encrypted = _encryptAndHash(Uint8List(0));
    return concat(eBytes, encrypted);  // 32 + 16 = 48 bytes
  }

  /// Initiator: process msg2 (e, ee, se) → returns split
  Future<(CipherState tx, CipherState rx)> readMessage2(Uint8List msg) async {
    // e: read remote ephemeral
    final re = SimplePublicKey(msg.sublist(0, 32), type: KeyPairType.x25519);
    _mixHash(msg.sublist(0, 32));

    // ee: DH(e, re)
    _mixKey(await _dh(_ephemeralKeypair!, re));

    // se: DH(s, re)
    _mixKey(await _dh(_staticKeypair, re));

    // Decrypt payload
    _decryptAndHash(msg.sublist(32));

    // Split → transport keys
    return _split();
  }
}
```

### Key compatibility requirement

The Dart implementation MUST produce byte-identical handshake messages as the Node.js `noise-protocol` library. This means:
- Same BLAKE2b hash (512-bit, NOT 256-bit)
- Same X25519 DH (standard Curve25519 scalar multiplication)
- Same ChaCha20-Poly1305 (IETF variant, 96-bit nonce)
- Same HKDF construction (HMAC-BLAKE2b)
- Same prologue: `BLAKE2b-512("claude-remote/v1" || PSK)`
- Same nonce encoding: 8-byte little-endian counter, padded to 12 bytes for ChaCha20

### Cross-platform test strategy

Before implementing the full Flutter app, create a Dart CLI test harness:
```bash
# Generate test vectors from Node.js bridge
node packages/bridge/scripts/noise-test-vectors.js > test-vectors.json

# Verify Dart implementation matches
dart packages/app/test/noise_compat_test.dart
```

Test vectors should include:
1. Static keypair (known secret → known public key)
2. Prologue hash for known PSK
3. Full handshake transcript (msg1, msg2) with known ephemeral keys
4. Transport encryption test (known plaintext → known ciphertext with known nonce)

---

## Connection Discovery

```dart
class ConnectionDiscovery {
  final BridgeInfo bridge;  // from pairing payload

  /// Try connections in order, return first working one
  Stream<ConnectionAttempt> discover() async* {
    // 1. mDNS — fast LAN discovery
    yield ConnectionAttempt.mdns(bridge.mdnsService);
    await for (final service in Bonsoir.discovery(type: '_claude-remote._tcp')) {
      yield ConnectionAttempt.lan(service.host, service.port);
    }

    // 2. Last known IP (from successful previous connection)
    final lastIp = await _storage.getLastKnownIp();
    if (lastIp != null) {
      yield ConnectionAttempt.lan(lastIp, bridge.port);
    }

    // 3. Tunnel relay (from pairing payload)
    if (bridge.relay != null) {
      yield ConnectionAttempt.tunnel(bridge.relay!.url, bridge.relay!.port);
    }
  }
}
```

Connection indicator in UI:
- `🏠` LAN (mDNS or direct IP)
- `🌐` Tunnel (relay)
- `🔴` Offline (reconnecting)

---

## Push Notifications (ntfy)

No Firebase. The app polls ntfy server for bridge-specific topic:

```dart
class NtfyListener {
  /// Long-poll ntfy for notifications
  Stream<PushNotification> listen(String server, String topic) async* {
    final url = '$server/$topic/json?poll=1&since=all';
    // Uses Server-Sent Events or long polling
    // Only receives: event type + session name (no sensitive content)
  }
}
```

Notification types → app actions:
| Event | Notification | Tap Action |
|-------|-------------|------------|
| `needs_permission` | "Session X needs permission" (high priority) | Opens permission dialog |
| `needs_input` | "Session X needs input" | Opens session with keyboard |
| `completed` | "Session X completed" (low priority) | Opens session detail |
| `error` | "Session X encountered an error" | Opens session detail |

---

## Data Flow: Pairing

```
1. User runs `claude-remote-bridge pair` on desktop
2. Terminal shows QR code containing:
   claude-remote://pair/<base64url-encoded-JSON>

   JSON: {
     v: 1,
     name: "hostname",
     pk: "<bridge Curve25519 pubkey, base64>",
     psk: "<pre-shared key, base64>",
     lan: { port: 3847, mdns: "_claude-remote._tcp" },
     relay?: { url: "bore.pub", port: 12345 }
   }

3. App scans QR → parses URI → extracts PairingPayload
4. App generates its own Curve25519 keypair
5. App stores: own keypair + bridge pubkey + PSK in secure storage
6. App connects to bridge via WebSocket
7. Noise KK handshake authenticates both sides
8. Bridge registers app's pubkey as paired device
9. Pairing complete — persisted forever (until revoke)
```

---

## Directory Structure

```
packages/app/
  lib/
    main.dart
    app.dart                       # MaterialApp + GoRouter + ProviderScope
    theme.dart                     # Dark/light theme

    crypto/
      noise_kk.dart                # Noise KK state machine
      noise_session.dart           # Transport encrypt/decrypt
      key_store.dart               # flutter_secure_storage wrapper
      pairing.dart                 # QR payload parser + validator

    transport/
      bridge_connection.dart       # WebSocket + Noise handshake
      connection_manager.dart      # Auto-reconnect, state machine
      message_codec.dart           # BridgeMessage/AppMessage serialization
      discovery.dart               # mDNS → LAN → tunnel

    models/
      session_info.dart            # freezed model
      bridge_message.dart          # freezed union types
      app_message.dart             # freezed union types
      pairing_payload.dart         # freezed model
      connection_state.dart        # enum + data

    providers/
      connection_provider.dart
      sessions_provider.dart
      session_detail_provider.dart
      pairing_provider.dart
      settings_provider.dart
      notifications_provider.dart

    screens/
      pairing/
        scan_qr_screen.dart
        pairing_success_screen.dart
      dashboard/
        dashboard_screen.dart
        session_card.dart
        connection_indicator.dart
      session/
        session_detail_screen.dart
        output_viewer.dart
        permission_dialog.dart
        input_bar.dart
      settings/
        settings_screen.dart
        bridge_info_card.dart

    widgets/
      status_badge.dart            # active/waiting/completed badge
      encrypted_indicator.dart     # lock icon showing Noise session active

  test/
    crypto/
      noise_kk_test.dart           # Unit test: handshake state machine
      noise_compat_test.dart       # Cross-platform: verify vs Node.js vectors
      key_store_test.dart
    transport/
      message_codec_test.dart
      connection_manager_test.dart
    providers/
      sessions_provider_test.dart
```

---

## Implementation Phases

### Phase 1: Crypto Foundation (1-2 days)
- [ ] Implement `NoiseKK` state machine in pure Dart
- [ ] Generate test vectors from Node.js bridge
- [ ] Verify byte-compatibility with cross-platform tests
- [ ] `KeyStore` wrapper around `flutter_secure_storage`
- [ ] QR payload parser

### Phase 2: Transport (1 day)
- [ ] `BridgeConnection` — WebSocket + handshake protocol
- [ ] `ConnectionManager` — auto-reconnect state machine
- [ ] `MessageCodec` — JSON serialization for protocol types

### Phase 3: Core UI (2-3 days)
- [ ] Pairing flow (QR scan → store keys → first connection)
- [ ] Dashboard with session list
- [ ] Session detail with live output
- [ ] Permission approve/reject dialog
- [ ] Text input for sessions

### Phase 4: Discovery + Notifications (1 day)
- [ ] mDNS discovery via `bonsoir`
- [ ] Connection failover (mDNS → IP → tunnel)
- [ ] ntfy notification polling
- [ ] Local notification display

### Phase 5: Polish (1-2 days)
- [ ] Dark/light theme
- [ ] Connection status indicator
- [ ] Settings screen (unpair, notification prefs)
- [ ] Error handling and edge cases
- [ ] Widget and integration tests

---

## Dependencies (pubspec.yaml)

```yaml
dependencies:
  flutter:
    sdk: flutter

  # State management
  flutter_riverpod: ^2.6.0
  riverpod_annotation: ^2.6.0

  # Crypto (libsodium FFI — same C lib as Node.js bridge)
  sodium: ^3.4.6
  sodium_libs: ^3.4.6
  # Pure Dart fallback if needed:
  # cryptography: ^2.9.0

  # Storage
  flutter_secure_storage: ^10.0.0

  # Networking
  web_socket_channel: ^3.0.0

  # Discovery
  bonsoir: ^6.1.0

  # Connectivity state
  connectivity_plus: ^6.1.0

  # QR
  mobile_scanner: ^7.2.0

  # Navigation
  go_router: ^14.6.0

  # Models
  freezed_annotation: ^2.4.0
  json_annotation: ^4.9.0

  # Notifications
  flutter_local_notifications: ^18.0.0

  # UI
  google_fonts: ^6.2.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.4.0
  freezed: ^2.5.0
  json_serializable: ^6.8.0
  riverpod_generator: ^2.6.0
  mocktail: ^1.0.0
```

---

## Risk: Noise Protocol Compatibility

**This is the #1 risk.** The Dart Noise KK implementation must produce byte-identical output as the Node.js `noise-protocol` library. Any mismatch = handshake failure.

**Mitigation:**
1. Generate deterministic test vectors from Node.js (seeded keypairs, fixed ephemeral)
2. Cross-platform test suite that runs on both Node.js and Dart
3. Start Phase 1 with Noise only — don't touch UI until handshake works

**Specific concerns:**
- BLAKE2b output size: must be 512-bit (64 bytes), not 256-bit
- Nonce encoding differences (big-endian vs little-endian)
- HKDF construction must match exactly
- The `noise-protocol` npm uses `sodium-native` which may have quirks

**Primary approach: `sodium` + `sodium_libs`** (libsodium FFI for Flutter). This uses the **exact same C library** (`libsodium`) as the Node.js bridge's `sodium-native`, virtually eliminating byte-compatibility concerns. All platforms covered (iOS, Android, macOS, Linux, Windows, Web).

**Fallback:** Pure Dart via `cryptography: ^2.9.0` if libsodium FFI causes build issues. Would need more extensive cross-platform testing.

**Also found:** `noise_protocol_framework: ^1.1.0` on pub.dev (pure Dart, May 2025). Low adoption and unaudited — NOT recommended for security-critical use. Better to implement the KK state machine (~200 lines) ourselves over proven primitives.

---

## Security Invariants

1. **Static keys never leave secure storage** — Keychain (iOS) / Keystore (Android)
2. **No plaintext protocol messages over network** — everything through Noise session
3. **Push notifications never contain content** — only event type + session name
4. **QR code is the ONLY pairing mechanism** — no manual key entry, no cloud relay
5. **Handshake hash is verified** — if tampered, connection fails immediately
6. **Forward secrecy** — ephemeral keys destroyed after handshake, past sessions unrecoverable
