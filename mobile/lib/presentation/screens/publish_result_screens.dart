import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/cinepulse_theme.dart';
import '../../core/utils/ist_formatter.dart';
import '../../data/services/x_publish_service.dart';
import '../../domain/models/post_models.dart';
import '../../state/providers.dart';
import '../widgets/state_views.dart';
import '../widgets/status_badges.dart';

class PublishingSuccessScreen extends StatelessWidget {
  const PublishingSuccessScreen({super.key, required this.result});
  final XPublishResult result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.check_circle_rounded,
                  size: 64, color: CinePulseColors.emerald),
              const SizedBox(height: 16),
              Text(
                'Published to X',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Your post is live and has been moved to Publishing History.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('X POST ID',
                          style: CinePulseTheme.monoStyle(
                              fontSize: 10, color: CinePulseColors.slate)),
                      const SizedBox(height: 4),
                      SelectableText(
                        result.xPostId ?? '—',
                        style: CinePulseTheme.monoStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 12),
                      Text('PUBLISHED AT',
                          style: CinePulseTheme.monoStyle(
                              fontSize: 10, color: CinePulseColors.slate)),
                      const SizedBox(height: 4),
                      Text(
                        IstFormatter.formatDateTime(DateTime.now().toUtc()),
                        style: CinePulseTheme.monoStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (result.xUrl != null && result.xUrl!.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(result.xUrl!),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('View on X'),
                ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () => context.go('/review'),
                child: const Text('Back to Review Queue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PublishingFailureScreen extends ConsumerStatefulWidget {
  const PublishingFailureScreen({
    super.key,
    required this.draft,
    required this.result,
  });

  final PostDraft draft;
  final XPublishResult result;

  @override
  ConsumerState<PublishingFailureScreen> createState() =>
      _PublishingFailureScreenState();
}

class _PublishingFailureScreenState
    extends ConsumerState<PublishingFailureScreen> {
  bool _checking = false;
  String? _reconcileNote;

  Future<void> _reconcileOnX() async {
    setState(() {
      _checking = true;
      _reconcileNote = null;
    });
    try {
      final found = await ref
          .read(xPublishServiceProvider)
          .reconcileUnknownOutcome(expectedText: widget.draft.effectiveText);
      if (!mounted) return;
      if (found != null && found.isSuccess && found.xPostId != null) {
        final userId = ref.read(authRepositoryProvider).currentUser?.id ?? '';
        await ref.read(cinePulseRepositoryProvider).markDraftPublished(
              draft: widget.draft,
              userId: userId,
              finalText: widget.draft.effectiveText,
              xPostId: found.xPostId!,
              xUrl: found.xUrl ?? '',
            );
        ref.invalidate(activeDraftsProvider);
        ref.invalidate(publishedHistoryProvider);
        if (mounted) context.go('/publish-success', extra: found);
      } else {
        setState(() {
          _reconcileNote =
              'Post was NOT found in recent X timeline. Safe to retry or edit.';
        });
      }
    } catch (e) {
      setState(() => _reconcileNote = 'Reconciliation failed: $e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUnknown = widget.result.status == PublishOutcomeStatus.unknownOutcome;
    return Scaffold(
      appBar: AppBar(title: const Text('Publishing Failed')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 56, color: CinePulseColors.crimson),
            const SizedBox(height: 16),
            Text(
              isUnknown
                  ? 'Outcome Unconfirmed — Reconcile Required'
                  : 'Publishing Failed',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.result.status.name.toUpperCase(),
                      style: CinePulseTheme.monoStyle(
                        fontSize: 11,
                        color: CinePulseColors.crimson,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(widget.result.errorMessage ?? 'Unknown error.'),
                    if (_reconcileNote != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _reconcileNote!,
                        style: const TextStyle(color: CinePulseColors.amber),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (isUnknown)
              FilledButton.icon(
                onPressed: _checking ? null : _reconcileOnX,
                icon: const Icon(Icons.sync_rounded),
                label: Text(_checking
                    ? 'Checking X Timeline...'
                    : 'Check Post Status on X'),
              )
            else
              FilledButton(
                onPressed: () => context.pop(),
                child: const Text('Review & Retry'),
              ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => context.go('/review'),
              child: const Text('Return to Queue'),
            ),
          ],
        ),
      ),
    );
  }
}

class PublishedHistoryScreen extends ConsumerWidget {
  const PublishedHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(publishedHistoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Published History')),
      body: historyAsync.when(
        loading: () => const LoadingSkeletonView(),
        error: (err, _) => EmptyStateView(
          icon: Icons.error_outline,
          title: 'Failed to Load History',
          subtitle: err.toString(),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyStateView(
              icon: Icons.history_toggle_off,
              title: 'No Published Posts Yet',
              subtitle:
                  'Posts you manually approve and publish to X will appear here.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final p = items[i];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            p.category.label.toUpperCase(),
                            style: CinePulseTheme.monoStyle(
                              fontSize: 10,
                              color: CinePulseColors.goldDark,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const DraftStatusPill(status: DraftStatus.published),
                          const Spacer(),
                          Text(
                            IstFormatter.formatShortTime(p.publishedAt),
                            style: CinePulseTheme.monoStyle(
                                fontSize: 10, color: CinePulseColors.slate),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(p.finalText),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'X ID: ${p.xPostId}',
                              overflow: TextOverflow.ellipsis,
                              style: CinePulseTheme.monoStyle(
                                  fontSize: 11, color: CinePulseColors.slate),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => launchUrl(
                              Uri.parse(p.xUrl),
                              mode: LaunchMode.externalApplication,
                            ),
                            icon: const Icon(Icons.open_in_new, size: 15),
                            label: const Text('Open on X'),
                          ),
                        ],
                      ),
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
