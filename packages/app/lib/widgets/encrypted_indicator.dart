import 'package:flutter/material.dart';

/// Shows a lock icon indicating the Noise session is active.
class EncryptedIndicator extends StatelessWidget {
  final bool isEncrypted;

  const EncryptedIndicator({super.key, this.isEncrypted = true});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isEncrypted
          ? 'End-to-end encrypted (Noise KK)'
          : 'Not encrypted',
      child: Icon(
        isEncrypted ? Icons.lock : Icons.lock_open,
        size: 14,
        color: isEncrypted ? Colors.green : Colors.red,
      ),
    );
  }
}
