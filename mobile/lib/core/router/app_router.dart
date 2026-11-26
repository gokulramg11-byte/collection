import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/services/x_publish_service.dart';
import '../../domain/models/box_office_models.dart';
import '../../domain/models/post_models.dart';
import '../../presentation/screens/analytics_screens.dart';
import '../../presentation/screens/home_dashboard_screen.dart';
import '../../presentation/screens/movies_screens.dart';
import '../../presentation/screens/post_editor_screen.dart';
import '../../presentation/screens/post_preview_screen.dart';
import '../../presentation/screens/post_review_screen.dart';
import '../../presentation/screens/publish_result_screens.dart';
import '../../presentation/screens/settings_screens.dart';
import '../../presentation/screens/splash_onboarding_login_screens.dart';
import '../../presentation/widgets/cinepulse_scaffold.dart';

final GlobalKey<NavigatorState> _rootNavKey = GlobalKey<NavigatorState>();

GoRouter createAppRouter() {
  return GoRouter(
    navigatorKey: _rootNavKey,
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, __, navigationShell) =>
            CinePulseScaffold(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (_, __) => const HomeDashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/review',
                builder: (_, __) => const PostReviewScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/movies',
                builder: (_, __) => const MoviesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, __) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/review/:id',
        parentNavigatorKey: _rootNavKey,
        builder: (_, state) => PostPreviewScreen(draft: state.extra! as PostDraft),
      ),
      GoRoute(
        path: '/review/:id/edit',
        parentNavigatorKey: _rootNavKey,
        builder: (_, state) => PostEditorScreen(draft: state.extra! as PostDraft),
      ),
      GoRoute(
        path: '/publish-success',
        parentNavigatorKey: _rootNavKey,
        builder: (_, state) =>
            PublishingSuccessScreen(result: state.extra! as XPublishResult),
      ),
      GoRoute(
        path: '/publish-failure',
        parentNavigatorKey: _rootNavKey,
        builder: (_, state) {
          final map = state.extra! as Map<String, dynamic>;
          return PublishingFailureScreen(
            draft: map['draft'] as PostDraft,
            result: map['result'] as XPublishResult,
          );
        },
      ),
      GoRoute(
        path: '/published-history',
        parentNavigatorKey: _rootNavKey,
        builder: (_, __) => const PublishedHistoryScreen(),
      ),
      GoRoute(
        path: '/movies/:id',
        parentNavigatorKey: _rootNavKey,
        builder: (_, state) => MovieDetailsScreen(
          movieId: state.pathParameters['id']!,
          movie: state.extra as Movie?,
        ),
      ),
      GoRoute(
        path: '/movies/:id/history',
        parentNavigatorKey: _rootNavKey,
        builder: (_, state) =>
            CollectionHistoryScreen(movieId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/movies/:id/sources',
        parentNavigatorKey: _rootNavKey,
        builder: (_, state) {
          final map = state.extra! as Map<String, dynamic>;
          return SourceDetailsScreen(
            reports: map['reports'] as List<CollectionReport>,
            reconciled: map['reconciled'] as ReconciledCollection?,
          );
        },
      ),
      GoRoute(
        path: '/top-rankings',
        parentNavigatorKey: _rootNavKey,
        builder: (_, __) => const TopRankingsScreen(),
      ),
      GoRoute(
        path: '/daily-overview',
        parentNavigatorKey: _rootNavKey,
        builder: (_, __) => const DailyOverviewScreen(),
      ),
      GoRoute(
        path: '/source-health',
        parentNavigatorKey: _rootNavKey,
        builder: (_, __) => const SourceHealthScreen(),
      ),
      GoRoute(
        path: '/notifications',
        parentNavigatorKey: _rootNavKey,
        builder: (_, __) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/x-account',
        parentNavigatorKey: _rootNavKey,
        builder: (_, __) => const XAccountScreen(),
      ),
    ],
  );
}
