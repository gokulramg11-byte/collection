import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/cinepulse_theme.dart';
import '../../core/utils/ist_formatter.dart';
import '../../domain/models/box_office_models.dart';
import '../../state/providers.dart';
import '../widgets/collection_history_chart.dart';
import '../widgets/collection_metric_card.dart';
import '../widgets/state_views.dart';
import '../widgets/status_badges.dart';

class MoviesScreen extends ConsumerStatefulWidget {
  const MoviesScreen({super.key});

  @override
  ConsumerState<MoviesScreen> createState() => _MoviesScreenState();
}

class _MoviesScreenState extends ConsumerState<MoviesScreen> {
  String _query = '';
  String _selectedLanguage = 'All';

  static const _languages = [
    'All',
    'Malayalam',
    'Tamil',
    'Telugu',
    'Kannada',
    'Hindi',
    'Bengali',
    'Marathi',
    'Punjabi',
    'Gujarati',
    'Other',
  ];

  @override
  Widget build(BuildContext context) {
    final moviesAsync = ref.watch(moviesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Movies')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: const InputDecoration(
                hintText: 'Search Indian movies...',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _languages.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final lang = _languages[i];
                return ChoiceChip(
                  selected: _selectedLanguage == lang,
                  label: Text(lang),
                  onSelected: (_) => setState(() => _selectedLanguage = lang),
                );
              },
            ),
          ),
          Expanded(
            child: moviesAsync.when(
              loading: () => const LoadingSkeletonView(message: 'Loading movies...'),
              error: (e, _) => EmptyStateView(
                icon: Icons.error_outline,
                title: 'Failed to Load Movies',
                subtitle: e.toString(),
              ),
              data: (movies) {
                final filtered = movies.where((m) {
                  final matchesLang = _selectedLanguage == 'All' ||
                      m.primaryLanguage.toLowerCase() ==
                          _selectedLanguage.toLowerCase();
                  final matchesQuery =
                      _query.isEmpty || m.title.toLowerCase().contains(_query);
                  return matchesLang && matchesQuery;
                }).toList();

                if (filtered.isEmpty) {
                  return EmptyStateView(
                    icon: Icons.movie_filter_outlined,
                    title: 'No Matching Movies',
                    subtitle: 'Try clearing search text or switching language filter.',
                    actionLabel: 'Reset Filters',
                    onAction: () => setState(() {
                      _query = '';
                      _selectedLanguage = 'All';
                    }),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final m = filtered[i];
                    return Card(
                      child: ListTile(
                        leading: LanguageBadge(language: m.primaryLanguage),
                        title: Text(m.title, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          m.releaseDate != null
                              ? 'Release: ${IstFormatter.formatDateOnly(m.releaseDate!)}'
                              : 'Release date pending',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/movies/${m.id}', extra: m),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class MovieDetailsScreen extends ConsumerWidget {
  const MovieDetailsScreen({super.key, required this.movieId, this.movie});
  final String movieId;
  final Movie? movie;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(cinePulseRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(movie?.title ?? 'Movie Details'),
        actions: [
          IconButton(
            tooltip: 'Collection History',
            icon: const Icon(Icons.table_chart_outlined),
            onPressed: () => context.push('/movies/$movieId/history'),
          ),
        ],
      ),
      body: FutureBuilder(
        future: Future.wait([
          repo.fetchMovieCollections(movieId),
          repo.fetchMovieReports(movieId),
        ]),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingSkeletonView();
          }
          if (snapshot.hasError) {
            return EmptyStateView(
              icon: Icons.error_outline,
              title: 'Unable to Load Collections',
              subtitle: snapshot.error.toString(),
            );
          }

          final collections =
              snapshot.data![0] as List<ReconciledCollection>;
          final reports = snapshot.data![1] as List<CollectionReport>;

          ReconciledCollection? latestFor(CollectionMetric metric) {
            final matches = collections.where((c) => c.metric == metric).toList();
            return matches.isNotEmpty ? matches.first : null;
          }

          final indiaNet = latestFor(CollectionMetric.indiaNet);
          final indiaGross = latestFor(CollectionMetric.indiaGross);
          final overseas = latestFor(CollectionMetric.overseasGross);
          final worldwide = latestFor(CollectionMetric.worldwideGross);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (movie != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        LanguageBadge(language: movie!.primaryLanguage),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(movie!.title,
                                  style: Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 4),
                              Text(
                                movie!.releaseDate != null
                                    ? 'Release: ${IstFormatter.formatDateOnly(movie!.releaseDate!)}'
                                    : 'Release date unavailable',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              Text('Separated Box-Office Metrics',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.4,
                children: [
                  CollectionMetricCard(
                    metric: CollectionMetric.indiaNet,
                    amountInrCrores: indiaNet?.amountInrCrores,
                    status: indiaNet?.confidenceStatus,
                    hasConflict: indiaNet?.hasConflict ?? false,
                    onTap: () => context.push(
                      '/movies/$movieId/sources',
                      extra: {'reports': reports, 'reconciled': indiaNet},
                    ),
                  ),
                  CollectionMetricCard(
                    metric: CollectionMetric.indiaGross,
                    amountInrCrores: indiaGross?.amountInrCrores,
                    status: indiaGross?.confidenceStatus,
                    hasConflict: indiaGross?.hasConflict ?? false,
                    onTap: () => context.push(
                      '/movies/$movieId/sources',
                      extra: {'reports': reports, 'reconciled': indiaGross},
                    ),
                  ),
                  CollectionMetricCard(
                    metric: CollectionMetric.overseasGross,
                    amountInrCrores: overseas?.amountInrCrores,
                    status: overseas?.confidenceStatus,
                    hasConflict: overseas?.hasConflict ?? false,
                    onTap: () => context.push(
                      '/movies/$movieId/sources',
                      extra: {'reports': reports, 'reconciled': overseas},
                    ),
                  ),
                  CollectionMetricCard(
                    metric: CollectionMetric.worldwideGross,
                    amountInrCrores: worldwide?.amountInrCrores,
                    status: worldwide?.confidenceStatus,
                    hasConflict: worldwide?.hasConflict ?? false,
                    onTap: () => context.push(
                      '/movies/$movieId/sources',
                      extra: {'reports': reports, 'reconciled': worldwide},
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              CollectionHistoryChart(
                points: collections
                    .where((c) => c.metric == CollectionMetric.indiaNet)
                    .toList(),
                metricLabel: 'India Net',
              ),
              const SizedBox(height: 16),
              Text('Source Reports (${reports.length})',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (reports.isEmpty)
                const EmptyStateView(
                  icon: Icons.bar_chart_outlined,
                  title: 'No Historical Data Yet',
                  subtitle:
                      'Charts and reports appear only when verified source reports exist—no figures are fabricated.',
                )
              else
                for (final r in reports) ...[
                  Card(
                    child: ListTile(
                      title: Text(
                        '${r.metric.label} (${r.periodType.label}): ₹${r.amountInrCrores.toStringAsFixed(2)} Cr',
                        style: CinePulseTheme.monoStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        '${r.sourceName} • ${r.sourceStatus.label} • ${IstFormatter.formatDateOnly(r.reportingDate)}',
                      ),
                      trailing: const Icon(Icons.open_in_new, size: 16),
                      onTap: () => launchUrl(
                        Uri.parse(r.sourceUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              const SizedBox(height: 12),
              Text(
                'Metadata via TMDB • Box-office figures strictly from authorized trade/official reports.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }
}

class CollectionHistoryScreen extends ConsumerWidget {
  const CollectionHistoryScreen({super.key, required this.movieId});
  final String movieId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Collection History')),
      body: FutureBuilder<List<ReconciledCollection>>(
        future: ref.read(cinePulseRepositoryProvider).fetchMovieCollections(movieId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const LoadingSkeletonView();
          }
          final rows = snap.data ?? const [];
          if (rows.isEmpty) {
            return const EmptyStateView(
              icon: Icons.timeline_outlined,
              title: 'No Collection History',
              subtitle: 'No reconciled daily or cumulative entries recorded yet.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final r = rows[i];
              return Card(
                child: ListTile(
                  title: Text(
                    '${r.metric.label} (${r.periodType.label}) • ₹${r.amountInrCrores.toStringAsFixed(2)} Cr',
                    style: CinePulseTheme.monoStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    '${IstFormatter.formatDateOnly(r.reportingDate)} • ${r.confidenceStatus.label}',
                  ),
                  trailing: r.hasConflict
                      ? const Icon(Icons.warning_amber_rounded,
                          color: CinePulseColors.crimson)
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class SourceDetailsScreen extends StatelessWidget {
  const SourceDetailsScreen({
    super.key,
    required this.reports,
    this.reconciled,
  });

  final List<CollectionReport> reports;
  final ReconciledCollection? reconciled;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Source Attribution & Conflicts')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (reconciled != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${reconciled!.metric.label} (${reconciled!.periodType.label})',
                      style: CinePulseTheme.monoStyle(
                          fontSize: 11, color: CinePulseColors.goldDark),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '₹${reconciled!.amountInrCrores.toStringAsFixed(2)} Cr',
                      style: CinePulseTheme.monoStyle(fontSize: 22),
                    ),
                    const SizedBox(height: 8),
                    Text(reconciled!.methodologyNote,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text('Supporting & Competing Reports (${reports.length})',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final r in reports) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(r.sourceName,
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(
                          '₹${r.amountInrCrores.toStringAsFixed(2)} Cr',
                          style: CinePulseTheme.monoStyle(
                              fontSize: 14, color: CinePulseColors.goldDark),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${r.sourceStatus.label} • Rev ${r.revisionNumber} • Retrieved ${IstFormatter.formatShortTime(r.retrievedAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
