import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/cinepulse_theme.dart';
import '../../core/utils/ist_formatter.dart';
import '../../domain/models/post_models.dart';
import '../../state/providers.dart';
import '../widgets/state_views.dart';
import '../widgets/status_badges.dart';

class PostReviewScreen extends ConsumerWidget {
  const PostReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allDraftsAsync = ref.watch(activeDraftsProvider);
    final filteredAsync = ref.watch(filteredDraftsProvider);
    final selectedCat = ref.watch(selectedDraftCategoryProvider);

    final countsByCategory = <DraftCategory, int>{};
    allDraftsAsync.whenData((list) {
      countsByCategory[DraftCategory.all] = list.length;
      for (final d in list) {
        countsByCategory[d.category] = (countsByCategory[d.category] ?? 0) + 1;
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Post Review'),
        actions: [
          IconButton(
            tooltip: 'All Categories',
            icon: const Icon(Icons.filter_list_rounded),
            onPressed: () => _showCategorySheet(context, ref, countsByCategory),
          ),
          IconButton(
            tooltip: 'Published History',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => context.push('/published-history'),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              scrollDirection: Axis.horizontal,
              itemCount: DraftCategory.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, idx) {
                final cat = DraftCategory.values[idx];
                final count = countsByCategory[cat] ?? 0;
                final selected = cat == selectedCat;
                return ChoiceChip(
                  selected: selected,
                  label: Text(count > 0 ? '${cat.label} ($count)' : cat.label),
                  onSelected: (_) =>
                      ref.read(selectedDraftCategoryProvider.notifier).state = cat,
                );
              },
            ),
          ),
          Expanded(
            child: filteredAsync.when(
              loading: () => const LoadingSkeletonView(message: 'Loading pending drafts...'),
              error: (err, _) => EmptyStateView(
                icon: Icons.error_outline,
                title: 'Failed to Load Drafts',
                subtitle: err.toString(),
                actionLabel: 'Retry',
                onAction: () => ref.invalidate(activeDraftsProvider),
              ),
              data: (drafts) {
                if (drafts.isEmpty) {
                  return EmptyStateView(
                    icon: Icons.check_circle_outline_rounded,
                    title: 'No Pending Drafts',
                    subtitle:
                        'All drafts for this category have been reviewed or expired.',
                    actionLabel: 'Refresh Queue',
                    onAction: () => ref.invalidate(activeDraftsProvider),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(activeDraftsProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: drafts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, idx) => _DraftCard(draft: drafts[idx]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showCategorySheet(
    BuildContext context,
    WidgetRef ref,
    Map<DraftCategory, int> counts,
  ) {
    final selected = ref.read(selectedDraftCategoryProvider);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          builder: (_, scrollCtrl) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Filter by Category',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  itemCount: DraftCategory.values.length,
                  itemBuilder: (_, i) {
                    final cat = DraftCategory.values[i];
                    final count = counts[cat] ?? 0;
                    return ListTile(
                      title: Text(cat.label),
                      trailing: Text(
                        '$count',
                        style: CinePulseTheme.monoStyle(
                          fontSize: 13,
                          color: count > 0
                              ? CinePulseColors.goldDark
                              : CinePulseColors.slate,
                        ),
                      ),
                      selected: cat == selected,
                      onTap: () {
                        ref.read(selectedDraftCategoryProvider.notifier).state = cat;
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({required this.draft});
  final PostDraft draft;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        draft.category.label.toUpperCase(),
                        style: CinePulseTheme.monoStyle(
                          fontSize: 10,
                          color: CinePulseColors.goldDark,
                        ),
                      ),
                      DraftStatusPill(status: draft.status),
                    ],
                  ),
                ),
                Text(
                  IstFormatter.formatDateOnly(draft.reportingDate),
                  style: CinePulseTheme.monoStyle(
                    fontSize: 11,
                    color: CinePulseColors.slate,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              draft.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              draft.effectiveText,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (draft.mainFigureDisplay != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: CinePulseColors.darkSurfaceLow,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  draft.mainFigureDisplay!,
                  style: CinePulseTheme.monoStyle(
                    fontSize: 14,
                    color: CinePulseColors.goldDark,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    draft.sourceSummary,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  IstFormatter.formatExpiryCountdown(draft.expiresAt),
                  style: CinePulseTheme.monoStyle(
                    fontSize: 10,
                    color: CinePulseColors.amber,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => context.push('/review/${draft.id}', extra: draft),
                    child: const Text('Preview'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        context.push('/review/${draft.id}/edit', extra: draft),
                    child: const Text('Edit'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
