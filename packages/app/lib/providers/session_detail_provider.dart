import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bridge_message.dart';
import 'connection_provider.dart';

/// Output lines for a specific session.
final sessionOutputProvider =
    StreamProvider.family<String, String>((ref, sessionId) {
  final manager = ref.watch(connectionManagerProvider);

  return manager.messages
      .where((msg) =>
          msg is SessionOutputMessage && msg.sessionId == sessionId)
      .map((msg) => (msg as SessionOutputMessage).content);
});

/// Permission requests for a specific session.
final permissionRequestProvider =
    StreamProvider.family<PermissionRequestMessage, String>(
        (ref, sessionId) {
  final manager = ref.watch(connectionManagerProvider);

  return manager.messages
      .where((msg) =>
          msg is PermissionRequestMessage && msg.sessionId == sessionId)
      .cast<PermissionRequestMessage>();
});
