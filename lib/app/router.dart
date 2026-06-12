import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/ai/analysis_screen.dart';
import '../features/ai/chat_screen.dart';
import '../features/auth/auth_screen.dart';
import '../features/book_details/book_details_screen.dart';
import '../features/graph/graph_screen.dart';
import '../features/community/challenges_screen.dart';
import '../features/community/community_screen.dart';
import '../features/home/home_screen.dart';
import '../features/import/import_screen.dart';
import '../features/import/metadata_repository.dart';
import '../features/insights/insights_screen.dart';
import '../features/library/library_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/onboarding/splash_screen.dart';
import '../features/premium/paywall_screen.dart';
import '../features/profile/achievements_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/scanner/scanner_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/tracker/tracker_screen.dart';
import '../features/wrapped/wrapped_screen.dart';
import 'shell.dart';

final router = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
    GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
    GoRoute(path: '/auth', builder: (_, _) => const AuthScreen()),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => MainShell(shell: shell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/library', builder: (_, _) => const LibraryScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/insights', builder: (_, _) => const InsightsScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/community',
              builder: (_, _) => const CommunityScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
        ]),
      ],
    ),
    GoRoute(
      path: '/book/:id',
      pageBuilder: (_, state) => _slideIn(
          state, BookDetailsScreen(bookId: state.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/tracker/:id',
      pageBuilder: (_, state) =>
          _slideIn(state, TrackerScreen(bookId: state.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/scanner',
      pageBuilder: (_, state) => _slideIn(
          state, ScannerScreen(manual: state.uri.queryParameters['manual'] == '1')),
    ),
    GoRoute(
      path: '/import',
      pageBuilder: (_, state) =>
          _slideIn(state, ImportScreen(metadata: state.extra as BookMetadata)),
    ),
    GoRoute(
      path: '/notifications',
      pageBuilder: (_, state) => _slideIn(state, const NotificationsScreen()),
    ),
    GoRoute(
      path: '/settings',
      pageBuilder: (_, state) => _slideIn(state, const SettingsScreen()),
    ),
    GoRoute(
      path: '/achievements',
      pageBuilder: (_, state) => _slideIn(state, const AchievementsScreen()),
    ),
    GoRoute(
      path: '/ai',
      pageBuilder: (_, state) => _slideIn(state, const AiAnalysisScreen()),
    ),
    GoRoute(
      path: '/ai/chat',
      pageBuilder: (_, state) => _slideIn(state, const AiChatScreen()),
    ),
    GoRoute(
      path: '/graph',
      pageBuilder: (_, state) => _slideIn(state, const GraphScreen()),
    ),
    GoRoute(
      path: '/challenges',
      pageBuilder: (_, state) => _slideIn(state, const ChallengesScreen()),
    ),
    GoRoute(
      path: '/premium',
      pageBuilder: (_, state) => _slideIn(state, const PaywallScreen()),
    ),
    GoRoute(
      path: '/wrapped',
      pageBuilder: (_, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const WrappedScreen(),
        transitionDuration: const Duration(milliseconds: 350),
        transitionsBuilder: (context, animation, secondary, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    ),
  ],
);

/// Right-to-left slide-in matching the prototype's `screen-in` animation.
CustomTransitionPage _slideIn(GoRouterState state, Widget child) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: (context, animation, secondary, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: const Cubic(0.2, 0, 0, 1));
      return FadeTransition(
        opacity: Tween(begin: 0.3, end: 1.0).animate(curved),
        child: SlideTransition(
          position: Tween(begin: const Offset(0.12, 0), end: Offset.zero)
              .animate(curved),
          child: child,
        ),
      );
    },
  );
}
