import 'package:flutter/material.dart';
import '../../core/theme/cinepulse_theme.dart';
import '../../domain/models/box_office_models.dart';
import '../../domain/models/post_models.dart';

class LanguageBadge extends StatelessWidget {
  const LanguageBadge({super.key, required this.language});
  final String language;

  static String _shortCode(String lang) {
    switch (lang.toLowerCase()) {
      case 'malayalam':
        return 'ML';
      case 'tamil':
        return 'TA';
      case 'telugu':
        return 'TE';
      case 'kannada':
        return 'KN';
      case 'hindi':
        return 'HI';
      case 'bengali':
        return 'BN';
      case 'marathi':
        return 'MR';
      case 'punjabi':
        return 'PA';
      case 'gujarati':
        return 'GU';
      default:
        return lang.toUpperCase().substring(0, lang.length >= 2 ? 2 : 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: CinePulseColors.goldContainerDark,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: CinePulseColors.goldDark.withOpacity(0.35)),
      ),
      child: Text(
        _shortCode(language),
        style: CinePulseTheme.monoStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: CinePulseColors.goldOnContainerDark,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class DraftStatusPill extends StatelessWidget {
  const DraftStatusPill({super.key, required this.status});
  final DraftStatus status;

  Color _color() {
    switch (status) {
      case DraftStatus.published:
        return CinePulseColors.emerald;
      case DraftStatus.pendingReview:
        return CinePulseColors.amber;
      case DraftStatus.edited:
      case DraftStatus.publishing:
        return CinePulseColors.goldDark;
      case DraftStatus.failed:
        return CinePulseColors.crimson;
      case DraftStatus.expired:
      case DraftStatus.cancelled:
        return CinePulseColors.slate;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        status.apiValue,
        style: CinePulseTheme.monoStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class SourceStatusDot extends StatelessWidget {
  const SourceStatusDot({super.key, required this.status});
  final ReportSourceStatus status;

  Color _color() {
    switch (status) {
      case ReportSourceStatus.audited:
      case ReportSourceStatus.reportedFinal:
        return CinePulseColors.emerald;
      case ReportSourceStatus.producerReported:
      case ReportSourceStatus.tradeReported:
        return CinePulseColors.goldDark;
      case ReportSourceStatus.estimate:
      case ReportSourceStatus.updatedEstimate:
        return CinePulseColors.amber;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _color();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            status.label,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: c,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}
