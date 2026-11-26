import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/cinepulse_theme.dart';
import '../../core/utils/ist_formatter.dart';
import '../../state/providers.dart';
import '../widgets/state_views.dart';
import '../widgets/status_badges.dart';

class HomeDashboardScreen extends ConsumerWidget {
  const HomeDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashAsync = ref.watch(dashboardProvider);
    final xSessionAsync = ref.watch(xSessionProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('CinePulse India'),
            Text(
              IstFormatter.formatShortTime(DateTime.now().toUtc()),
              style: CinePulseTheme.monoStyle(
                fontSize: 10,
                color: CinePulseColors.emerald,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh Data',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.invalidate(dashboardProvider);
              ref.invalidate(activeDraftsProvider);
            },
          ),
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.push('/notifications'),
          ),
        ],
      ),
      body: dashAsync.when(
        loading: () => const LoadingSkeletonView(),
        error: (err, _) => EmptyStateView(
          icon: Icons.cloud_off_rounded,
          title: 'Unable to Reach Backend',
          subtitle:
              'Could not sync latest box-office reports ($err). Manual X publishing is disabled while offline.',
          actionLabel: 'Retry Connection',
          onAction: () => ref.invalidate(dashboardProvider),
        ),
        data: (snap) {
          final lastRun = snap.latestRun;
          final xSession = xSessionAsync.valueOrNull;
          final unhealthySources =
              snap.sources.where((s) => s.healthStatus != 'HEALTHY').toList();

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(dashboardProvider);
              ref.invalidate(activeDraftsProvider);
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (snap.isFromCache)
                  OfflineErrorBanner(
                    message: 'Offline Mode • Showing cached summary metrics.',
                    onRetry: () => ref.invalidate(dashboardProvider),
                  ),
                // Collection Status + Connected X Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                lastRun != null
                                    ? 'COLLECTION: ${lastRun.status}'
                                    : 'COLLECTION STATUS: NO RUNS YET',
                                style: CinePulseTheme.monoStyle(
                                  fontSize: 11,
                                  color: lastRun?.status == 'SUCCESS'
                                      ? CinePulseColors.emerald
                                      : CinePulseColors.amber,
                                ),
                              ),
                            ),
                            if (lastRun != null)
                              Text(
                                IstFormatter.formatShortTime(lastRun.startedAt),
                                style: CinePulseTheme.monoStyle(
                                  fontSize: 10,
                                  color: CinePulseColors.slate,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: CinePulseColors.darkSurfaceLow,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: CinePulseColors.darkBorder),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.alternate_email, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      xSession != null
                                          ? '@${xSession.username}'
                                          : 'X Account Not Connected',
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                    Text(
                                      xSession != null
                                          ? 'Manual Publish Ready • OAuth 2.0 PKCE'
                                          : 'Connect via OAuth 2.0 PKCE to publish',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              OutlinedButton(
                                onPressed: () => context.push('/x-account'),
                                child: Text(xSession != null ? 'Manage' : 'Connect'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // 2x2 KPI Grid
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.55,
                  children: [
                    _KpiTile(
                      label: 'MONITORED MOVIES',
                      value: '${snap.monitoredMoviesCount}',
                      accent: Theme.of(context).colorScheme.onSurface,
                      onTap: () => context.go('/movies'),
                    ),
                    _KpiTile(
                      label: 'PENDING POSTS',
                      value: '${snap.pendingDraftsCount}',
                      accent: CinePulseColors.amber,
                      onTap: () => context.go('/review'),
                    ),
                    _KpiTile(
                      label: 'PUBLISHED TODAY',
                      value: '${snap.publishedTodayCount}',
                      accent: CinePulseColors.emerald,
                      onTap: () => context.push('/published-history'),
                    ),
                    _KpiTile(
                      label: 'CONFLICTS',
                      value: '${snap.conflictsCount}',
                      accent: snap.conflictsCount > 0
                          ? CinePulseColors.crimson
                          : CinePulseColors.slate,
                      onTap: () => context.push('/source-health'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                // Quick Actions Row
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.push('/top-rankings'),
                        icon: const Icon(Icons.leaderboard_outlined, size: 18),
                        label: const Text('Top 5 Rankings'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.push('/daily-overview'),
                        icon: const Icon(Icons.calendar_today_outlined, size: 18),
                        label: const Text('Daily Overview'),
                      ),
                    ),
                  ],
                ),
                if (unhealthySources.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.warning_amber_rounded,
                          color: CinePulseColors.amber),
                      title: Text(
                        '${unhealthySources.length} Source(s) Need Attention',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      subtitle: Text(
                        unhealthySources.map((s) => s.name).join(', '),
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/source-health'),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Monitored Releases',
                        style: Theme.of(context).textTheme.titleLarge),
                    TextButton(
                      onPressed: () => context.go('/movies'),
                      child: const Text('View All'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (snap.recentMovies.isEmpty)
                  const EmptyStateView(
                    icon: Icons.movie_outlined,
                    title: 'No Monitored Movies Yet',
                    subtitle:
                        'Run the daily collection pipeline to discover Indian theatrical releases.',
                  )
                else
                  for (final movie in snap.recentMovies) ...[
                    Card(
                      child: ListTile(
                        title: Text(movie.title,
                            overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          movie.releaseDate != null
                              ? IstFormatter.formatDateOnly(movie.releaseDate!)
                              : 'Release date pending',
                        ),
                        leading: LanguageBadge(language: movie.primaryLanguage),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/movies/${movie.id}'),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final String value;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: CinePulseTheme.monoStyle(
                  fontSize: 10,
                  color: CinePulseColors.slate,
                  letterSpacing: 0.7,
                ),
              ),
              Text(
                value,
                style: CinePulseTheme.monoStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
