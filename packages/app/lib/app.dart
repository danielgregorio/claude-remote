import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers/connection_provider.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/pairing/scan_qr_screen.dart';
import 'screens/pairing/pairing_success_screen.dart';
import 'screens/session/session_detail_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'theme.dart';

final _router = GoRouter(
  initialLocation: '/',
  redirect: (context, state) async {
    // Check if paired — if not, redirect to pairing
    final container = ProviderScope.containerOf(context);
    final isPaired = await container.read(isPairedProvider.future);
    if (!isPaired && state.matchedLocation != '/pair') {
      return '/pair';
    }
    return null;
  },
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const DashboardScreen(),
    ),
    GoRoute(
      path: '/pair',
      builder: (context, state) => const ScanQrScreen(),
    ),
    GoRoute(
      path: '/pair/success',
      builder: (context, state) => PairingSuccessScreen(
        bridgeName: state.extra as String? ?? 'Bridge',
      ),
    ),
    GoRoute(
      path: '/session/:id',
      builder: (context, state) => SessionDetailScreen(
        sessionId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);

class ClaudeRemoteApp extends StatelessWidget {
  const ClaudeRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Claude Remote',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.dark,
      routerConfig: _router,
    );
  }
}
