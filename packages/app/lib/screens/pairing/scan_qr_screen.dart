import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../providers/pairing_provider.dart';

class ScanQrScreen extends ConsumerStatefulWidget {
  const ScanQrScreen({super.key});

  @override
  ConsumerState<ScanQrScreen> createState() => _ScanQrScreenState();
}

class _ScanQrScreenState extends ConsumerState<ScanQrScreen> {
  final _controller = MobileScannerController();
  bool _processing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_processing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    final value = barcode!.rawValue!;
    if (!value.startsWith('claude-remote://pair/')) return;

    _processing = true;
    ref.read(pairingProvider.notifier).processQrCode(value);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PairingState>(pairingProvider, (prev, next) {
      if (next.phase == PairingPhase.success) {
        context.go('/pair/success', extra: next.bridgeName);
      } else if (next.phase == PairingPhase.error) {
        _processing = false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pairing failed: ${next.error}')),
        );
      }
    });

    final state = ref.watch(pairingProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),
            Text(
              'Claude Remote',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 32),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: state.phase == PairingPhase.processing
                      ? const Center(child: CircularProgressIndicator())
                      : MobileScanner(
                          controller: _controller,
                          onDetect: _onDetect,
                        ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Scan the QR code displayed by\nclaude-remote-bridge pair',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                    ),
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}
