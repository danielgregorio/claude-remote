import 'package:flutter/material.dart';

import '../../models/bridge_message.dart';
import '../../theme.dart';

class PermissionDialog extends StatelessWidget {
  final PermissionRequestMessage request;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const PermissionDialog({
    super.key,
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.warning_amber, color: AppColors.waiting),
          const SizedBox(width: 8),
          const Text('Permission Request'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tool: ${request.tool}',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.darkCard,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              request.description,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            onReject();
            Navigator.of(context).pop();
          },
          child: const Text('Reject'),
        ),
        FilledButton(
          onPressed: () {
            onApprove();
            Navigator.of(context).pop();
          },
          child: const Text('Approve'),
        ),
      ],
    );
  }
}
