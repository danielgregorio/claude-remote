import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../crypto/key_store.dart';
import '../crypto/pairing.dart';
import 'connection_provider.dart';

enum PairingPhase { idle, scanning, processing, success, error }

class PairingState {
  final PairingPhase phase;
  final String? bridgeName;
  final String? error;

  const PairingState({
    this.phase = PairingPhase.idle,
    this.bridgeName,
    this.error,
  });
}

class PairingNotifier extends StateNotifier<PairingState> {
  final KeyStore _keyStore;

  PairingNotifier(this._keyStore) : super(const PairingState());

  void startScanning() {
    state = const PairingState(phase: PairingPhase.scanning);
  }

  Future<void> processQrCode(String qrValue) async {
    state = const PairingState(phase: PairingPhase.processing);
    try {
      final service = PairingService(_keyStore);
      final result = await service.pair(qrValue);
      state = PairingState(
        phase: PairingPhase.success,
        bridgeName: result.payload.name,
      );
    } catch (e) {
      state = PairingState(
        phase: PairingPhase.error,
        error: e.toString(),
      );
    }
  }

  void reset() {
    state = const PairingState();
  }
}

final pairingProvider =
    StateNotifierProvider<PairingNotifier, PairingState>((ref) {
  final keyStore = ref.watch(keyStoreProvider);
  return PairingNotifier(keyStore);
});
