import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/cinepulse_repository.dart';
import '../data/services/secure_token_storage.dart';
import '../data/services/x_oauth_service.dart';
import '../data/services/x_publish_service.dart';
import '../domain/models/box_office_models.dart';
import '../domain/models/post_models.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.dark);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

final cinePulseRepositoryProvider = Provider<CinePulseRepository>((ref) {
  return SupabaseCinePulseRepository();
});

final secureTokenStorageProvider = Provider<SecureTokenStorage>((ref) {
  return AndroidKeystoreTokenStorage();
});

final xOAuthServiceProvider = Provider<XOAuthService>((ref) {
  return XOAuthService(tokenStorage: ref.watch(secureTokenStorageProvider));
});

final xPublishServiceProvider = Provider<XPublishService>((ref) {
  return XPublishService(
    tokenStorage: ref.watch(secureTokenStorageProvider),
    oauthService: ref.watch(xOAuthServiceProvider),
  );
});

final xSessionProvider = FutureProvider<XAccountSession?>((ref) async {
  return ref.watch(secureTokenStorageProvider).loadXSession();
});

final dashboardProvider = FutureProvider<DashboardSnapshot>((ref) async {
  return ref.watch(cinePulseRepositoryProvider).fetchDashboard();
});

final activeDraftsProvider = FutureProvider<List<PostDraft>>((ref) async {
  return ref.watch(cinePulseRepositoryProvider).fetchActiveDrafts();
});

final selectedDraftCategoryProvider =
    StateProvider<DraftCategory>((ref) => DraftCategory.all);

final filteredDraftsProvider = Provider<AsyncValue<List<PostDraft>>>((ref) {
  final draftsAsync = ref.watch(activeDraftsProvider);
  final selectedCat = ref.watch(selectedDraftCategoryProvider);
  return draftsAsync.whenData((drafts) {
    if (selectedCat == DraftCategory.all) return drafts;
    return drafts.where((d) => d.category == selectedCat).toList();
  });
});

final moviesProvider = FutureProvider<List<Movie>>((ref) async {
  return ref.watch(cinePulseRepositoryProvider).fetchMovies();
});

final publishedHistoryProvider = FutureProvider<List<PublishedPost>>((ref) async {
  return ref.watch(cinePulseRepositoryProvider).fetchPublishedHistory();
});

final notificationPrefsProvider = StateProvider<Map<String, bool>>(
  (ref) => const {
    'new_drafts': true,
    'conflicts': true,
    'expiring': true,
    'failures': true,
  },
);
