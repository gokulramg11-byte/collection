import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/cinepulse_theme.dart';
import '../../core/utils/x_character_counter.dart';
import '../../domain/models/post_models.dart';
import '../../state/providers.dart';

class PostEditorScreen extends ConsumerStatefulWidget {
  const PostEditorScreen({super.key, required this.draft});
  final PostDraft draft;

  @override
  ConsumerState<PostEditorScreen> createState() => _PostEditorScreenState();
}

class _PostEditorScreenState extends ConsumerState<PostEditorScreen> {
  late TextEditingController _bodyCtrl;
  late TextEditingController _hashtagsCtrl;
  late List<Map<String, dynamic>> _entries;
  bool _saving = false;

  static final RegExp _numberPattern = RegExp(r'\d+(?:\.\d+)?');

  @override
  void initState() {
    super.initState();
    _bodyCtrl = TextEditingController(text: widget.draft.effectiveText);
    _hashtagsCtrl = TextEditingController(text: widget.draft.hashtags.join(' '));
    _entries = List<Map<String, dynamic>>.from(widget.draft.entries);
  }

  @override
  void dispose() {
    _bodyCtrl.dispose();
    _hashtagsCtrl.dispose();
    super.dispose();
  }

  bool _numbersChanged(String originalText, String newText) {
    final origNums =
        _numberPattern.allMatches(originalText).map((m) => m.group(0)!).toList();
    final newNums =
        _numberPattern.allMatches(newText).map((m) => m.group(0)!).toList();
    if (origNums.length != newNums.length) return true;
    for (var i = 0; i < origNums.length; i++) {
      if (origNums[i] != newNums[i]) return true;
    }
    return false;
  }

  Future<void> _save() async {
    final text = _bodyCtrl.text.trim();
    final validation = XCharacterCounter.validate(text);
    final numbersModified = _numbersChanged(widget.draft.generatedText, text);

    var numericalConfirmed = false;
    Map<String, dynamic>? audit;
    if (numbersModified) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirm Numerical Change'),
          content: const Text(
            'You modified numerical figures in this draft. Underlying source reports remain unchanged, and this manual edit will be logged in the audit trail.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm Edit'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      numericalConfirmed = true;
      audit = {
        'original_text': widget.draft.generatedText,
        'edited_text': text,
        'confirmed_at': DateTime.now().toUtc().toIso8601String(),
      };
    }

    setState(() => _saving = true);
    try {
      final tags = _hashtagsCtrl.text
          .split(RegExp(r'\s+'))
          .where((t) => t.trim().isNotEmpty)
          .toList();
      await ref.read(cinePulseRepositoryProvider).saveDraftEdit(
            draftId: widget.draft.id,
            editedText: text,
            hashtags: tags,
            weightedCharCount: validation.weightedLength,
            isValidLength: validation.isValid,
            numericalEditConfirmed: numericalConfirmed,
            numericalAudit: audit,
          );
      ref.invalidate(activeDraftsProvider);
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final validation = XCharacterCounter.validate(_bodyCtrl.text);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Draft'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving...' : 'Save Edits'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Live Weighted Counter Bar
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${validation.weightedLength} / 280 weighted',
                    style: CinePulseTheme.monoStyle(
                      fontSize: 13,
                      color: validation.isValid
                          ? CinePulseColors.emerald
                          : CinePulseColors.crimson,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      final cur = _bodyCtrl.text;
                      _bodyCtrl.text = '$cur\n';
                      setState(() {});
                    },
                    icon: const Icon(Icons.keyboard_return, size: 16),
                    label: const Text('Line Break'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyCtrl,
            maxLines: 10,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Post Content',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _hashtagsCtrl,
            decoration: const InputDecoration(
              labelText: 'Hashtags (space separated)',
            ),
          ),
          if (_entries.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Reorder / Remove Entries',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _entries.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _entries.removeAt(oldIndex);
                  _entries.insert(newIndex, item);
                });
              },
              itemBuilder: (ctx, i) {
                final e = _entries[i];
                return Card(
                  key: ValueKey('${e['title']}_$i'),
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    leading: const Icon(Icons.drag_handle),
                    title: Text(e['title']?.toString() ?? ''),
                    subtitle: Text('₹${e['amount_inr_crores']} Cr'),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, color: CinePulseColors.crimson),
                      onPressed: () => setState(() => _entries.removeAt(i)),
                    ),
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: CinePulseColors.amber.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: CinePulseColors.amber.withOpacity(0.4)),
            ),
            child: Text(
              'Manual numerical edits require explicit confirmation and are logged in the audit trail. Source reports remain preserved.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
