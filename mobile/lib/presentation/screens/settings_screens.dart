import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/cinepulse_theme.dart';
import '../../data/services/x_oauth_service.dart';
import '../../state/providers.dart';

class XAccountScreen extends ConsumerStatefulWidget {
  const XAccountScreen({super.key});

  @override
  ConsumerState<XAccountScreen> createState() => _XAccountScreenState();
}

class _XAccountScreenState extends ConsumerState<XAccountScreen> {
  final _codeCtrl = TextEditingController();
  PkcePair? _pendingPkce;
  bool _busy = false;
  String? _statusMsg;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _startOAuth() async {
    if (!AppConfig.isXConfigured) {
      setState(() => _statusMsg = 'X_CLIENT_ID not configured via --dart-define.');
      return;
    }
    final oauth = ref.read(xOAuthServiceProvider);
    final pkce = oauth.generatePkcePair();
    final state = Random.secure().nextInt(1 << 30).toString();
    final uri = oauth.buildAuthorizeUri(
      state: state,
      codeChallenge: pkce.codeChallenge,
    );
    setState(() {
      _pendingPkce = pkce;
      _statusMsg =
          'Authorize in browser, then complete redirect or paste authorization code below.';
    });
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _completeExchange() async {
    if (_pendingPkce == null || _codeCtrl.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(xOAuthServiceProvider).exchangeCodeForTokens(
            authorizationCode: _codeCtrl.text.trim(),
            codeVerifier: _pendingPkce!.codeVerifier,
          );
      ref.invalidate(xSessionProvider);
      _codeCtrl.clear();
      setState(() => _statusMsg = 'Connected and stored in Android Keystore.');
    } catch (e) {
      setState(() => _statusMsg = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(xSessionProvider);
    final session = sessionAsync.valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('X Account Connection')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session != null ? '@${session.username}' : 'Not Connected',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    session != null
                        ? 'OAuth 2.0 PKCE • Scopes: ${session.scopes.join(', ')}\nSecured in Android Keystore'
                        : 'Connect your X account using official OAuth 2.0 Authorization Code Flow with PKCE.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  if (session == null)
                    FilledButton.icon(
                      onPressed: _startOAuth,
                      icon: const Icon(Icons.link_rounded),
                      label: const Text('Connect X Account (OAuth 2.0 PKCE)'),
                    )
                  else
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: CinePulseColors.crimson,
                      ),
                      onPressed: () async {
                        await ref
                            .read(xOAuthServiceProvider)
                            .disconnectAndRevoke();
                        ref.invalidate(xSessionProvider);
                      },
                      icon: const Icon(Icons.link_off_rounded),
                      label: const Text('Disconnect & Revoke Access'),
                    ),
                ],
              ),
            ),
          ),
          if (_pendingPkce != null) ...[
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _codeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Authorization Code',
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busy ? null : _completeExchange,
                      child: const Text('Complete Connection'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_statusMsg != null) ...[
            const SizedBox(height: 12),
            Text(_statusMsg!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Security Guarantee: CinePulse never asks for your X password, never embeds client secrets, and never stores X OAuth tokens in Supabase or GitHub Actions.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final xSession = ref.watch(xSessionProvider).valueOrNull;
    final prefs = ref.watch(notificationPrefsProvider);
    final userEmail =
        ref.watch(authRepositoryProvider).currentUser?.email ?? 'Operator';

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.alternate_email),
                  title: const Text('X Account Connection'),
                  subtitle: Text(xSession != null
                      ? '@${xSession.username} (Connected)'
                      : 'Not connected'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/x-account'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Published Post History'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/published-history'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('Source Health & Collection Status'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/source-health'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                      ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                      ButtonSegment(value: ThemeMode.system, label: Text('System')),
                    ],
                    selected: {themeMode},
                    onSelectionChanged: (s) =>
                        ref.read(themeModeProvider.notifier).state = s.first,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('New Drafts Alerts'),
                  value: prefs['new_drafts'] ?? true,
                  onChanged: (v) => ref
                      .read(notificationPrefsProvider.notifier)
                      .state = {...prefs, 'new_drafts': v},
                ),
                SwitchListTile(
                  title: const Text('Source Conflict Alerts'),
                  value: prefs['conflicts'] ?? true,
                  onChanged: (v) => ref
                      .read(notificationPrefsProvider.notifier)
                      .state = {...prefs, 'conflicts': v},
                ),
                SwitchListTile(
                  title: const Text('Expiring Drafts Alerts'),
                  value: prefs['expiring'] ?? true,
                  onChanged: (v) => ref
                      .read(notificationPrefsProvider.notifier)
                      .state = {...prefs, 'expiring': v},
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Display Timezone'),
              subtitle: const Text('Asia/Kolkata (IST, UTC+05:30)'),
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: CinePulseColors.crimson),
            onPressed: () async {
              await ref.read(authRepositoryProvider).signOut();
              if (context.mounted) context.go('/login');
            },
            icon: const Icon(Icons.logout),
            label: Text('Sign Out ($userEmail)'),
          ),
        ],
      ),
    );
  }
}
