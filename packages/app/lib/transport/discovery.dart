import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

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
/// 1. mDNS (LAN discovery via Bonsoir — _claude-remote._tcp)
/// 2. Last known IP (from secure storage)
/// 3. Tunnel relay (from pairing payload)
class ConnectionDiscovery {
  final int defaultPort;
  final String mdnsServiceType;
  final String? lastKnownHost;
  final String? relayUrl;
  final int? relayPort;

  BonsoirDiscovery? _discovery;

  ConnectionDiscovery({
    required this.defaultPort,
    this.mdnsServiceType = '_claude-remote._tcp',
    this.lastKnownHost,
    this.relayUrl,
    this.relayPort,
  });

  /// Yield connection candidates in priority order.
  ///
  /// mDNS discovery runs for [mdnsTimeout] before falling back
  /// to static endpoints.
  Stream<ConnectionCandidate> discover({
    Duration mdnsTimeout = const Duration(seconds: 3),
  }) async* {
    // 1. mDNS discovery — fastest on LAN
    yield* _discoverMdns(mdnsTimeout);

    // 2. Last known host
    if (lastKnownHost != null) {
      yield ConnectionCandidate(
        host: lastKnownHost!,
        port: defaultPort,
        method: ConnectionMethod.lan,
      );
    }

    // 3. Tunnel relay
    if (relayUrl != null && relayPort != null) {
      yield ConnectionCandidate(
        host: relayUrl!,
        port: relayPort!,
        method: ConnectionMethod.tunnel,
      );
    }
  }

  /// Discover bridge via mDNS (Bonsoir).
  Stream<ConnectionCandidate> _discoverMdns(Duration timeout) async* {
    try {
      _discovery = BonsoirDiscovery(type: mdnsServiceType);
      await _discovery!.ready;
      await _discovery!.start();

      // Listen for resolved services with a timeout
      yield* _discovery!.eventStream!
          .where((event) => event.type == BonsoirDiscoveryEventType.discoveryServiceResolved)
          .map((event) {
            final service = event.service!;
            return ConnectionCandidate(
              host: service.host ?? 'localhost',
              port: service.port,
              method: ConnectionMethod.mdns,
            );
          })
          .timeout(timeout, onTimeout: (sink) => sink.close());
    } catch (_) {
      // mDNS not available (e.g., no network) — silently skip
    } finally {
      await _discovery?.stop();
      _discovery = null;
    }
  }

  /// Stop any active discovery.
  Future<void> stop() async {
    await _discovery?.stop();
    _discovery = null;
  }
}
