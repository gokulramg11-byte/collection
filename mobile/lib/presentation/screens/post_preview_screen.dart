import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/cinepulse_theme.dart';
import '../../core/utils/ist_formatter.dart';
import '../../core/utils/x_character_counter.dart';
import '../../data/services/x_publish_service.dart';
import '../../domain/models/post_models.dart';
import '../../state/providers.dart';
import '../widgets/status_badges.dart';

class PostPreviewScreen extends ConsumerStatefulWidget {
  const PostPreviewScreen({super.key, required this.draft});
  final PostDraft draft;

  @override
  ConsumerState<PostPreviewScreen> createState() => _PostPreviewScreenState();
}

class _PostPreviewScreenState extends ConsumerState<PostPreviewScreen> {
  bool _publishing = false;

  Future<void> _confirmAndPublish(PostDraft draft) async {
    final text = draft.effectiveText;
    final validation = XCharacterCounter.validate(text);
    if (!validation.isValid) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Publish to X'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will immediately publish this post via the official X API.',
            ),
            const SizedBox(height: 12),
            Text(
              'Weighted Chars: ${validation.weightedLength} / 280\n'
              'Category: ${draft.category.label}\n'
              'Sources: ${draft.sourceSummary}',
              style: CinePulseTheme.monoStyle(fontSize: 11, color: CinePulseColors.slate),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm & Publish'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _publishing = true);
    final repo = ref.read(cinePulseRepositoryProvider);
    final publisher = ref.read(xPublishServiceProvider);
    final userId = ref.read(authRepositoryProvider).currentUser?.id ?? '';

    try {
      await repo.markDraftPublishing(draft.id);
      final result = await publisher.publishPost(text: text, userConfirmed: true);

      if (!mounted) return;
      if (result.isSuccess && result.xPostId != null) {
        await repo.markDraftPublished(
          draft: draft,
          userId: userId,
          finalText: text,
          xPostId: result.xPostId!,
          xUrl: result.xUrl ?? '',
        );
        ref.invalidate(activeDraftsProvider);
        ref.invalidate(dashboardProvider);
        ref.invalidate(publishedHistoryProvider);
        if (mounted) {
          context.go('/publish-success', extra: result);
        }
      } else {
        await repo.markDraftFailed(
          draft.id,
          result.errorMessage ?? 'Publishing failed.',
        );
        ref.invalidate(activeDraftsProvider);
        if (mounted) {
          context.push('/publish-failure', extra: {
            'draft': draft,
            'result': result,
          });
        }
      }
    } catch (e) {
      await repo.markDraftFailed(draft.id, e.toString());
      if (mounted) {
        context.push('/publish-failure', extra: {
          'draft': draft,
          'result': XPublishResult(
            status: PublishOutcomeStatus.unknownOutcome,
            errorMessage: e.toString(),
          ),
        });
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final text = draft.effectiveText;
    final validation = XCharacterCounter.validate(text);
    final xSession = ref.watch(xSessionProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Post Preview'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: DraftStatusPill(status: draft.status)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Authentic X-Style Post Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 18,
                        backgroundColor: CinePulseColors.goldContainerDark,
                        child: Icon(Icons.movie_filter_rounded,
                            size: 18, color: CinePulseColors.goldDark),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CinePulse India',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              xSession != null
                                  ? '@${xSession.username}'
                                  : '@CinePulseIN (Not Connected)',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        IstFormatter.formatDateOnly(draft.reportingDate),
                        style: CinePulseTheme.monoStyle(
                          fontSize: 10,
                          color: CinePulseColors.slate,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SelectableText(
                    text,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Weighted Character Counter Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${validation.weightedLength} / 280 weighted chars',
                        style: CinePulseTheme.monoStyle(
                          fontSize: 13,
                          color: validation.isValid
                              ? CinePulseColors.emerald
                              : CinePulseColors.crimson,
                        ),
                      ),
                      Text(
                        validation.isValid ? 'VALID' : 'EXCEEDS LIMIT',
                        style: CinePulseTheme.monoStyle(
                          fontSize: 11,
                          color: validation.isValid
                              ? CinePulseColors.emerald
                              : CinePulseColors.crimson,
                        ),
                      ),
                    ],
                  ),
                  if (validation.suggestions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final s in validation.suggestions)
                      Text('• $s', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Source Attribution
          Card(
            child: ListTile(
              leading: const Icon(Icons.verified_outlined, color: CinePulseColors.goldDark),
              title: const Text('Source Attribution'),
              subtitle: Text(draft.sourceSummary),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: (_publishing || !validation.isValid)
                ? null
                : () => _confirmAndPublish(draft),
            icon: _publishing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(_publishing ? 'Publishing to X...' : 'Publish to X'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      context.push('/review/${draft.id}/edit', extra: draft),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: text));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Post copied to clipboard')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: const Text('Copy'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await ref
                        .read(cinePulseRepositoryProvider)
                        .resetDraftToOriginal(draft.id);
                    ref.invalidate(activeDraftsProvider);
                    if (context.mounted) context.pop();
                  },
                  child: const Text('Reset'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: CinePulseColors.crimson),
            onPressed: () async {
              await ref.read(cinePulseRepositoryProvider).cancelDraft(draft.id);
              ref.invalidate(activeDraftsProvider);
              if (context.mounted) context.pop();
            },
            child: const Text('Cancel Draft'),
          ),
        ],
      ),
    );
  }
}
