import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/app_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/cinepulse_theme.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (AppConfig.isSupabaseConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
  }

  runApp(const ProviderScope(child: CinePulseApp()));
}

class CinePulseApp extends ConsumerWidget {
  const CinePulseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final router = createAppRouter();

    return MaterialApp.router(
      title: 'CinePulse India',
      debugShowCheckedModeBanner: false,
      theme: CinePulseTheme.light(),
      darkTheme: CinePulseTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
