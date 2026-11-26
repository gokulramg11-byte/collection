import 'package:cinepulse_india/core/theme/cinepulse_theme.dart';
import 'package:cinepulse_india/domain/models/box_office_models.dart';
import 'package:cinepulse_india/domain/models/post_models.dart';
import 'package:cinepulse_india/presentation/screens/post_review_screen.dart';
import 'package:cinepulse_india/presentation/widgets/collection_metric_card.dart';
import 'package:cinepulse_india/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('CollectionMetricCard keeps metric label and INR Cr separate',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: CinePulseTheme.dark(),
        home: const Scaffold(
          body: CollectionMetricCard(
            metric: CollectionMetric.indiaNet,
            amountInrCrores: 48.20,
            status: ReportSourceStatus.tradeReported,
          ),
        ),
      ),
    );

    expect(find.text('INDIA NET'), findsOneWidget);
    expect(find.text('₹48.20 Cr'), findsOneWidget);
    expect(find.text('Trade Reported'), findsOneWidget);
  });

  testWidgets('PostReviewScreen renders category chips and draft cards',
      (tester) async {
    final sampleDraft = PostDraft(
      id: 'd1',
      category: DraftCategory.movieWise,
      title: 'ARM — 26 Nov 2026',
      reportingDate: DateTime(2026, 11, 26),
      generatedText: 'ARM India Net: ₹48.20 Cr #BoxOffice',
      hashtags: const ['#BoxOffice'],
      entries: const [],
      mainFigureDisplay: '₹48.20 Cr • India Net',
      sourceSummary: '2 source report(s) • Verified',
      weightedCharCount: 38,
      isValidLength: true,
      status: DraftStatus.pendingReview,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 40)),
      createdAt: DateTime.now().toUtc(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeDraftsProvider.overrideWith((ref) async => [sampleDraft]),
        ],
        child: MaterialApp(
          theme: CinePulseTheme.dark(),
          home: const PostReviewScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Post Review'), findsOneWidget);
    expect(find.text('ARM — 26 Nov 2026'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
  });
}
