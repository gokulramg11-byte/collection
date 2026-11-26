import 'package:flutter/material.dart';
import '../../core/theme/cinepulse_theme.dart';
import '../../domain/models/box_office_models.dart';
import 'status_badges.dart';

/// Displays a single strictly-separated box-office metric (India Net, India Gross,
/// Overseas Gross, or Worldwide Gross) with its source status and optional tap
/// to inspect supporting/competing reports.
class CollectionMetricCard extends StatelessWidget {
  const CollectionMetricCard({
    super.key,
    required this.metric,
    required this.amountInrCrores,
    required this.status,
    this.hasConflict = false,
    this.onTap,
  });

  final CollectionMetric metric;
  final double? amountInrCrores;
  final ReportSourceStatus? status;
  final bool hasConflict;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final amountText = amountInrCrores != null
        ? '₹${amountInrCrores!.toStringAsFixed(2)} Cr'
        : 'Unavailable';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      metric.label.toUpperCase(),
                      overflow: TextOverflow.ellipsis,
                      style: CinePulseTheme.monoStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: CinePulseColors.slate,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ),
                  if (hasConflict)
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 14,
                      color: CinePulseColors.crimson,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                amountText,
                style: CinePulseTheme.monoStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: amountInrCrores != null
                      ? Theme.of(context).colorScheme.onSurface
                      : CinePulseColors.slate,
                ),
              ),
              const SizedBox(height: 6),
              if (status != null)
                SourceStatusDot(status: status!)
              else
                Text(
                  'No verified report',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
