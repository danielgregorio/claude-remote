import 'dart:convert';
import 'dart:typed_data';

import '../models/app_message.dart';
import '../models/bridge_message.dart';
import '../crypto/noise_session.dart';

/// Encodes/decodes protocol messages through an encrypted Noise session.
class MessageCodec {
  final NoiseSession _session;

  MessageCodec(this._session);

  /// Encrypt an AppMessage for sending over WebSocket.
  Future<Uint8List> encode(AppMessage message) async {
    final json = message.toJson();
    return _session.encryptJson(json);
  }

  /// Decrypt a WebSocket binary frame into a BridgeMessage.
  Future<BridgeMessage> decode(Uint8List data) async {
    final json = await _session.decryptJson(data);
    return BridgeMessage.fromJson(json);
  }
}
