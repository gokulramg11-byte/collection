import 'package:flutter/material.dart';
import '../../core/theme/cinepulse_theme.dart';
import '../../domain/models/box_office_models.dart';

/// Renders a bar chart strictly from verified historical [ReconciledCollection]
/// points. Never interpolates or fabricates missing dates.
class CollectionHistoryChart extends StatelessWidget {
  const CollectionHistoryChart({
    super.key,
    required this.points,
    required this.metricLabel,
  });

  final List<ReconciledCollection> points;
  final String metricLabel;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.bar_chart_outlined, color: CinePulseColors.slate),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Not enough verified $metricLabel history points to plot a chart yet. No placeholder data is generated.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final sorted = [...points]
      ..sort((a, b) => a.reportingDate.compareTo(b.reportingDate));
    final maxAmount = sorted
        .map((e) => e.amountInrCrores)
        .reduce((a, b) => a > b ? a : b);
    final safeMax = maxAmount > 0 ? maxAmount : 1.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$metricLabel VERIFIED HISTORY (₹ Cr)',
              style: CinePulseTheme.monoStyle(
                fontSize: 10,
                color: CinePulseColors.goldDark,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 120,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final p in sorted.take(10))
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              p.amountInrCrores.toStringAsFixed(1),
                              style: CinePulseTheme.monoStyle(
                                fontSize: 9,
                                color: CinePulseColors.slate,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              height: (p.amountInrCrores / safeMax) * 76 + 4,
                              decoration: BoxDecoration(
                                color: p.hasConflict
                                    ? CinePulseColors.amber
                                    : CinePulseColors.goldDark,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${p.reportingDate.day}/${p.reportingDate.month}',
                              style: CinePulseTheme.monoStyle(
                                fontSize: 9,
                                color: CinePulseColors.slate,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
