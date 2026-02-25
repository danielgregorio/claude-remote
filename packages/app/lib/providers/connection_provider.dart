import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../crypto/key_store.dart';
import '../models/app_message.dart';
import '../models/bridge_message.dart';
import '../models/connection_state.dart';
import '../transport/connection_manager.dart';

/// Global KeyStore instance.
final keyStoreProvider = Provider<KeyStore>((ref) => KeyStore());

/// ConnectionManager — singleton per app lifecycle.
final connectionManagerProvider = Provider<ConnectionManager>((ref) {
  final keyStore = ref.watch(keyStoreProvider);
  final manager = ConnectionManager(keyStore: keyStore);
  ref.onDispose(() => manager.dispose());
  return manager;
});

/// Connection state stream.
final connectionStateProvider =
    StreamProvider<BridgeConnectionState>((ref) {
  final manager = ref.watch(connectionManagerProvider);
  return manager.stateStream;
});

/// Current connection state (synchronous access).
final currentConnectionStateProvider = Provider<BridgeConnectionState>((ref) {
  final asyncState = ref.watch(connectionStateProvider);
  return asyncState.valueOrNull ?? const BridgeConnectionState();
});

/// Bridge messages stream.
final bridgeMessagesProvider = StreamProvider<BridgeMessage>((ref) {
  final manager = ref.watch(connectionManagerProvider);
  return manager.messages;
});

/// Whether the app is paired with a bridge.
final isPairedProvider = FutureProvider<bool>((ref) async {
  final keyStore = ref.watch(keyStoreProvider);
  return keyStore.isPaired;
});
