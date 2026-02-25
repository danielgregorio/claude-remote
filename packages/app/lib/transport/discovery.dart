import 'dart:async';

import '../models/connection_state.dart';

/// A candidate endpoint for connecting to the bridge.
class ConnectionCandidate {
  final String host;
  final int port;
  final ConnectionMethod method;

  ConnectionCandidate({
    required this.host,
    required this.port,
    required this.method,
  });

  @override
  String toString() => '${method.name}://$host:$port';
}

/// Discovers bridge endpoints in priority order:
/// 1. mDNS (LAN discovery via Bonsoir)
/// 2. Last known IP (from secure storage)
/// 3. Tunnel relay (from pairing payload)
///
/// In the current implementation, mDNS discovery is deferred
/// to Phase 4. This class provides the infrastructure for
/// endpoint ordering and fallback.
class ConnectionDiscovery {
  final int defaultPort;
  final String? lastKnownHost;
  final String? relayUrl;
  final int? relayPort;

  ConnectionDiscovery({
    required this.defaultPort,
    this.lastKnownHost,
    this.relayUrl,
    this.relayPort,
  });

  /// Yield connection candidates in priority order.
  Stream<ConnectionCandidate> discover() async* {
    // 1. Last known host (or localhost for development)
    if (lastKnownHost != null) {
      yield ConnectionCandidate(
        host: lastKnownHost!,
        port: defaultPort,
        method: ConnectionMethod.lan,
      );
    }

    // 2. Localhost fallback (for development)
    yield ConnectionCandidate(
      host: 'localhost',
      port: defaultPort,
      method: ConnectionMethod.lan,
    );

    // 3. Tunnel relay
    if (relayUrl != null && relayPort != null) {
      yield ConnectionCandidate(
        host: relayUrl!,
        port: relayPort!,
        method: ConnectionMethod.tunnel,
      );
    }
  }
}
