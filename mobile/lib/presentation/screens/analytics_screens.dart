import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/cinepulse_theme.dart';
import '../../core/utils/ist_formatter.dart';
import '../../state/providers.dart';
import '../widgets/state_views.dart';

class TopRankingsScreen extends ConsumerWidget {
  const TopRankingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draftsAsync = ref.watch(activeDraftsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Top 5 Rankings')),
      body: draftsAsync.when(
        loading: () => const LoadingSkeletonView(),
        error: (e, _) => EmptyStateView(
          icon: Icons.error_outline,
          title: 'Unable to Load Rankings',
          subtitle: e.toString(),
        ),
        data: (drafts) {
          final rankings =
              drafts.where((d) => d.entries.isNotEmpty).toList();
          if (rankings.isEmpty) {
            return const EmptyStateView(
              icon: Icons.leaderboard_outlined,
              title: 'No Comparable Top 5 Rankings Yet',
              subtitle:
                  'Rankings are generated only when comparable reports exist for the same metric and period.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rankings.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final r = rankings[i];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.title,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      for (final e in r.entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Text(
                                '#${e['rank']}',
                                style: CinePulseTheme.monoStyle(
                                  fontSize: 13,
                                  color: CinePulseColors.goldDark,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: Text(e['title']?.toString() ?? '')),
                              Text(
                                '₹${e['amount_inr_crores']} Cr',
                                style: CinePulseTheme.monoStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 6),
                      Text(r.sourceSummary,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class DailyOverviewScreen extends ConsumerWidget {
  const DailyOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moviesAsync = ref.watch(moviesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Daily Collection Overview')),
      body: moviesAsync.when(
        loading: () => const LoadingSkeletonView(),
        error: (e, _) => EmptyStateView(
          icon: Icons.error_outline,
          title: 'Failed to Load Overview',
          subtitle: e.toString(),
        ),
        data: (movies) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      IstFormatter.formatDateOnly(DateTime.now()),
                      style: CinePulseTheme.monoStyle(
                          fontSize: 12, color: CinePulseColors.goldDark),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${movies.length} Tracked Indian Releases',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap any film in Movies to inspect separated India Net, India Gross, Overseas, and Worldwide Gross reports.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SourceHealthScreen extends ConsumerWidget {
  const SourceHealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashAsync = ref.watch(dashboardProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Source Health & Status')),
      body: dashAsync.when(
        loading: () => const LoadingSkeletonView(),
        error: (e, _) => EmptyStateView(
          icon: Icons.error_outline,
          title: 'Failed to Load Sources',
          subtitle: e.toString(),
        ),
        data: (snap) {
          if (snap.sources.isEmpty) {
            return const EmptyStateView(
              icon: Icons.dns_outlined,
              title: 'No Sources Registered',
              subtitle: 'Run the backend pipeline once to register configured adapters.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: snap.sources.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final s = snap.sources[i];
              final healthy = s.healthStatus == 'HEALTHY';
              return Card(
                child: ListTile(
                  leading: Icon(
                    healthy ? Icons.check_circle : Icons.warning_amber_rounded,
                    color: healthy
                        ? CinePulseColors.emerald
                        : CinePulseColors.amber,
                  ),
                  title: Text(s.name),
                  subtitle: Text(
                    '${s.accessMethod} • ${s.healthStatus}'
                    '${s.lastError != null ? '\n${s.lastError}' : ''}',
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dash = ref.watch(dashboardProvider).valueOrNull;
    final items = <Map<String, String>>[
      if ((dash?.pendingDraftsCount ?? 0) > 0)
        {
          'title': '${dash!.pendingDraftsCount} Drafts Awaiting Review',
          'body': 'Tap Post Review to inspect and manually publish to X.',
        },
      if ((dash?.conflictsCount ?? 0) > 0)
        {
          'title': '${dash!.conflictsCount} Source Conflict(s) Detected',
          'body': 'Competing trade and official figures require manual review.',
        },
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: items.isEmpty
          ? const EmptyStateView(
              icon: Icons.notifications_none_rounded,
              title: 'All Caught Up',
              subtitle:
                  'Alerts for new drafts, source conflicts, expiring drafts, and collection failures appear here.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => Card(
                child: ListTile(
                  leading: const Icon(Icons.notifications_active_outlined,
                      color: CinePulseColors.goldDark),
                  title: Text(items[i]['title']!),
                  subtitle: Text(items[i]['body']!),
                ),
              ),
            ),
    );
  }
}
