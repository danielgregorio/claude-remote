# Flutter App — Development Guide

## Status

The app code is **complete but not yet compiled**. All Dart source files are written, the Noise KK crypto has been validated byte-compatible with the Node.js bridge, but `flutter create`, `flutter pub get`, and `flutter build` have not been run yet (no Flutter SDK was available during initial development).

### What's been verified

- **Noise KK handshake**: Full Dart <-> Node.js roundtrip test passes
  - Prologue (BLAKE2b-512) byte-identical
  - Handshake messages (msg1/msg2) interoperate
  - Transport encryption: both directions verified
  - See `test_dart/bin/test_handshake.dart` for the proof

- **12 Dart unit tests** pass (run with standalone Dart SDK)
- **60 Node.js bridge tests** pass (vitest)

---

## Quick Start

### Prerequisites

- Flutter SDK 3.24+ (`flutter --version`)
- Node.js 18+ (for the bridge server)
- A physical device or emulator (camera needed for QR pairing)

### Step 1: Initialize the Flutter project

The Flutter native scaffolding (`android/`, `ios/`, etc.) hasn't been generated yet. Run from the repo root:

```bash
cd packages/app

# Generate native project files around existing lib/ code
flutter create --project-name claude_remote \
  --org com.clauderemote \
  --platforms android,ios \
  .

# Install dependencies
flutter pub get

# Generate freezed/json_serializable code (if using code generation)
# dart run build_runner build --delete-conflicting-outputs
```

**Important**: `flutter create .` with existing `lib/` and `pubspec.yaml` will preserve all our code and just add the missing `android/`, `ios/`, `web/`, `test/` scaffolding.

### Step 2: Verify the build

```bash
# Check for analysis errors
flutter analyze

# Run tests (once flutter_test is available)
flutter test
```

### Step 3: Start the bridge server

In a separate terminal:

```bash
# From repo root
npm install
npm run build

# Start the bridge
npx tsx packages/bridge/src/cli.ts start

# In another terminal, generate pairing QR
npx tsx packages/bridge/src/cli.ts pair
```

### Step 4: Run the app

```bash
cd packages/app
flutter run
```

Scan the QR code shown by `bridge pair` with the app's camera.

---

## Architecture Overview

```
lib/
  main.dart                    # Entry point — ProviderScope + ClaudeRemoteApp
  app.dart                     # MaterialApp + GoRouter + routes
  theme.dart                   # Dark/light theme

  crypto/
    noise_kk.dart              # Noise KK state machine (initiator, ~300 lines)
    noise_session.dart         # Transport encrypt/decrypt after handshake
    key_store.dart             # flutter_secure_storage wrapper
    pairing.dart               # QR URI parser + pairing service

  transport/
    bridge_connection.dart     # WebSocket + Noise handshake protocol
    connection_manager.dart    # Auto-reconnect with exponential backoff
    message_codec.dart         # JSON through encrypted session
    discovery.dart             # mDNS (Bonsoir) -> LAN IP -> tunnel failover

  models/
    pairing_payload.dart       # QR code JSON payload
    session_info.dart          # Session status + metadata
    bridge_message.dart        # Bridge -> App messages (sealed class)
    app_message.dart           # App -> Bridge messages (sealed class)
    connection_state.dart      # Connection lifecycle enum

  providers/
    connection_provider.dart   # Riverpod: connection state + messages
    sessions_provider.dart     # Riverpod: session list
    session_detail_provider.dart # Riverpod: live output + permissions
    pairing_provider.dart      # Riverpod: pairing state machine
    settings_provider.dart     # Riverpod: user preferences
    notifications_provider.dart # ntfy polling + local notifications

  screens/
    pairing/
      scan_qr_screen.dart      # Camera QR scanner (mobile_scanner)
      pairing_success_screen.dart
    dashboard/
      dashboard_screen.dart    # Session list + connection indicator
      session_card.dart        # Individual session widget
      connection_indicator.dart # LAN/tunnel/offline status
    session/
      session_detail_screen.dart # Live output viewer
      permission_dialog.dart    # Approve/reject tool use
      input_bar.dart            # Text input for sessions
    settings/
      settings_screen.dart     # Bridge info, unpair, prefs

  widgets/
    status_badge.dart          # Colored status chip
    encrypted_indicator.dart   # Lock icon for Noise session
```

---

## Key Implementation Details

### Noise KK Handshake

The app is always the **initiator**. The bridge is the **responder**.

```
App (initiator)                    Bridge (responder)
     |                                  |
     |-- WebSocket connect /ws -------->|
     |                                  |
     |-- [0x01][32B pubkey][48B msg1] ->|  (e, es, ss)
     |                                  |
     |<----------- [48B msg2] ----------|  (e, ee, se)
     |                                  |
     |  [encrypted JSON frames]  <----> |
```

- Protocol: `Noise_KK_25519_ChaChaPoly_BLAKE2b`
- PSK bound into prologue: `BLAKE2b-512("claude-remote/v1" || PSK)`
- Nonce encoding: `[4 zero bytes][8-byte LE counter]` at offset 4
- Transport: auto-incrementing nonces, empty AD

The implementation lives in `lib/crypto/noise_kk.dart` and uses the `cryptography` package (pure Dart, no native dependencies).

### State Management

Riverpod providers drive the entire app state:

- `connectionManagerProvider` — singleton ConnectionManager
- `connectionStateProvider` — stream of BridgeConnectionState
- `sessionsProvider` — list of SessionInfo, updated from bridge messages
- `sessionOutputProvider(sessionId)` — stream of output lines
- `permissionRequestProvider(sessionId)` — stream of permission requests
- `pairingProvider` — pairing state machine
- `settingsProvider` — user preferences in secure storage

### Connection Lifecycle

1. App launches → checks `isPaired`
2. If not paired → QR scan screen
3. If paired → auto-connect via ConnectionManager
4. ConnectionManager tries: mDNS → last known IP → tunnel
5. On connect: Noise handshake → encrypted session
6. On disconnect: exponential backoff reconnect (1s → 30s)

---

## Cross-Platform Test Vectors

Test vectors are generated by the bridge and saved at:
```
packages/app/test/crypto/noise_test_vectors.json
```

To regenerate:
```bash
npx tsx packages/bridge/scripts/noise-test-vectors.ts > packages/app/test/crypto/noise_test_vectors.json
```

To run the Dart validation (standalone, no Flutter):
```bash
# Install Dart SDK if not available via Flutter
cd packages/app/test_dart
dart pub get
dart test                         # Unit tests
dart run bin/test_handshake.dart  # Full Dart <-> Node.js handshake
```

---

## Remaining Work

### Must-do before first build

- [ ] Run `flutter create .` to generate native scaffolding
- [ ] Run `flutter pub get` to resolve dependencies
- [ ] Run `flutter analyze` and fix any compile errors
- [ ] Test QR scanning with a real camera (mobile_scanner requires physical device)

### Phase 5: Polish

- [ ] Add notification permission request on first launch (Android 13+)
- [ ] Implement ntfy HTTP long-polling in `notifications_provider.dart`
- [ ] Add haptic feedback on permission requests
- [ ] Test mDNS discovery on LAN (Bonsoir)
- [ ] Handle app backgrounding (keep WebSocket alive? or reconnect on resume?)
- [ ] Add "last seen" timestamp to bridge info in settings
- [ ] Dark/light theme toggle in settings
- [ ] Widget tests for key screens
- [ ] Integration test: full pairing → session → permission flow

### Nice-to-have

- [ ] Biometric auth before approving dangerous tool use
- [ ] Session output search/filter
- [ ] Copy session output to clipboard
- [ ] Share session summary
- [ ] iPad/tablet layout with split view

---

## Troubleshooting

### `flutter pub get` fails on cryptography

The `cryptography: ^2.7.0` package is pure Dart. If it conflicts, check the Flutter SDK version — needs Dart 3.5+.

### QR scanner doesn't work

`mobile_scanner` requires camera permissions:
- **Android**: Add to `android/app/src/main/AndroidManifest.xml`:
  ```xml
  <uses-permission android:name="android.permission.CAMERA" />
  ```
- **iOS**: Add to `ios/Runner/Info.plist`:
  ```xml
  <key>NSCameraUsageDescription</key>
  <string>Camera needed to scan bridge QR code</string>
  ```

### Handshake fails with "could not verify data"

This means the Noise handshake MAC verification failed. Check:
1. Are you scanning the correct QR code from the current bridge instance?
2. Did the bridge regenerate keys? (Delete `~/.claude-remote/keys.json` and re-pair)
3. Is the PSK correct? The QR code contains the PSK — re-scan.

### WebSocket connection refused

- Ensure the bridge is running: `npx tsx packages/bridge/src/cli.ts start`
- Check the port (default 3847): `curl http://localhost:3847/api/health`
- If using tunnel, ensure bore is running and accessible

### mDNS not discovering bridge

- Both devices must be on the same LAN
- mDNS may be blocked by network policy (corporate WiFi)
- Fallback: the app will try the last known IP and tunnel relay
