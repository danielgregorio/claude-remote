import 'dart:convert';
import 'dart:typed_data';

/// Pairing payload parsed from QR code URI.
///
/// URI format: claude-remote://pair/<base64url-encoded-JSON>
/// JSON: { v, name, pk, psk, lan: { port, mdns }, relay?: { url, port } }
class PairingPayload {
  final int version;
  final String name;
  final Uint8List bridgePublicKey; // 32 bytes Curve25519
  final Uint8List psk; // 32 bytes pre-shared key
  final int lanPort;
  final String mdnsService;
  final String? relayUrl;
  final int? relayPort;

  PairingPayload({
    required this.version,
    required this.name,
    required this.bridgePublicKey,
    required this.psk,
    required this.lanPort,
    required this.mdnsService,
    this.relayUrl,
    this.relayPort,
  });

  /// Parse a claude-remote://pair/<payload> URI.
  factory PairingPayload.fromUri(String uri) {
    const prefix = 'claude-remote://pair/';
    if (!uri.startsWith(prefix)) {
      throw FormatException('Invalid pairing URI: must start with $prefix');
    }

    final encoded = uri.substring(prefix.length);
    final jsonStr = utf8.decode(base64Url.decode(base64Url.normalize(encoded)));
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;

    return PairingPayload.fromJson(json);
  }

  factory PairingPayload.fromJson(Map<String, dynamic> json) {
    final version = json['v'] as int;
    if (version != 1) {
      throw FormatException('Unsupported pairing version: $version');
    }

    final lan = json['lan'] as Map<String, dynamic>;
    final relay = json['relay'] as Map<String, dynamic>?;

    return PairingPayload(
      version: version,
      name: json['name'] as String,
      bridgePublicKey: base64Decode(json['pk'] as String),
      psk: base64Decode(json['psk'] as String),
      lanPort: lan['port'] as int,
      mdnsService: lan['mdns'] as String,
      relayUrl: relay?['url'] as String?,
      relayPort: relay?['port'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'v': version,
        'name': name,
        'pk': base64Encode(bridgePublicKey),
        'psk': base64Encode(psk),
        'lan': {'port': lanPort, 'mdns': mdnsService},
        if (relayUrl != null) 'relay': {'url': relayUrl, 'port': relayPort},
      };
}
