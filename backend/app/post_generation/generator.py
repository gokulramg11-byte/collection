"""Post draft generation with X weighted-character validation and source preservation."""

from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
import uuid

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.entities import Movie, PostDraft, PostSource, ReconciledCollection
from app.post_generation.rankings import LANGUAGE_TO_CATEGORY, Top5RankingResult, build_top_5_ranking
from app.schemas.domain import CollectionMetric, DraftCategory, DraftStatus, ReportingPeriodType
from app.validators.x_text_validator import validate_x_post

MILESTONE_THRESHOLDS_CR = [
    Decimal("1000"),
    Decimal("500"),
    Decimal("250"),
    Decimal("100"),
    Decimal("50"),
]

_METRIC_LABELS = {
    CollectionMetric.INDIA_NET.value: "India Net",
    CollectionMetric.INDIA_GROSS.value: "India Gross",
    CollectionMetric.OVERSEAS_GROSS.value: "Overseas Gross",
    CollectionMetric.WORLDWIDE_GROSS.value: "Worldwide Gross",
}


def _format_crores(amount: Decimal) -> str:
    return f"₹{amount.quantize(Decimal('0.01'))} Cr"


def _persist_draft(
    session: Session,
    *,
    category: DraftCategory,
    title: str,
    reporting_date: date,
    text: str,
    hashtags: list[str],
    main_figure_display: str | None,
    source_summary: str,
    report_ids: list[str],
    reconciled_id: uuid.UUID | None = None,
    movie_id: uuid.UUID | None = None,
    period_type: str | None = None,
    metric: str | None = None,
    entries: list[dict] | None = None,
    expiry_hours: int = 48,
) -> PostDraft:
    validation = validate_x_post(text)
    now = datetime.now(timezone.utc)
    draft = PostDraft(
        category=category.value,
        title=title,
        movie_id=movie_id,
        reporting_date=reporting_date,
        period_type=period_type,
        metric=metric,
        generated_text=text,
        hashtags=hashtags,
        entries=entries or [],
        main_figure_display=main_figure_display,
        source_summary=source_summary,
        weighted_char_count=validation.weighted_length,
        is_valid_length=validation.is_valid,
        status=DraftStatus.PENDING_REVIEW.value,
        expires_at=now + timedelta(hours=expiry_hours),
    )
    session.add(draft)
    session.flush()

    seen_reports: set[str] = set()
    for rid in report_ids:
        if rid in seen_reports:
            continue
        seen_reports.add(rid)
        session.add(
            PostSource(
                draft_id=draft.id,
                report_id=uuid.UUID(rid),
                reconciled_id=reconciled_id,
            )
        )
    session.flush()
    return draft


def _format_ranking_draft(ranking: Top5RankingResult) -> tuple[str, list[str], str]:
    metric_label = _METRIC_LABELS.get(ranking.metric.value, ranking.metric.value)
    period_label = "Daily" if ranking.period_type == ReportingPeriodType.DAILY else "Cumulative"
    cat_title = ranking.category.value.replace("_", " ").title()
    header = f"{cat_title} ({period_label} {metric_label}) — {ranking.reporting_date.strftime('%d %b %Y')}"
    if ranking.is_partial:
        header += f" [Partial {len(ranking.entries)}/5]"

    lines = [header, ""]
    for entry in ranking.entries:
        tag = "Est." if "ESTIMATE" in entry.confidence_status else "Rep."
        lines.append(f"{entry.rank}. {entry.title}: {_format_crores(entry.amount_inr_crores)} ({tag})")

    hashtags = ["#BoxOffice", "#IndianCinema"]
    lines.append("")
    lines.append(" ".join(hashtags))
    return "\n".join(lines), hashtags, header


def generate_drafts_for_date(
    session: Session,
    reporting_date: date,
    expiry_hours: int = 48,
) -> list[PostDraft]:
    """Generate pending X post drafts from reconciled collections for reporting_date."""
    created_drafts: list[PostDraft] = []

    reconciled_rows = session.execute(
        select(ReconciledCollection, Movie)
        .join(Movie, ReconciledCollection.movie_id == Movie.id)
        .where(ReconciledCollection.reporting_date == reporting_date)
    ).all()

    # Group reconciled metrics by movie_id so Movie Wise posts never mix metrics silently
    by_movie: dict[uuid.UUID, tuple[Movie, list[ReconciledCollection]]] = {}
    for rec, movie in reconciled_rows:
        if movie.id not in by_movie:
            by_movie[movie.id] = (movie, [])
        by_movie[movie.id][1].append(rec)

    for movie_id, (movie, recs) in by_movie.items():
        lines = [f"{movie.title} ({movie.primary_language}) — {reporting_date.strftime('%d %b %Y')}"]
        report_ids: list[str] = []
        primary_display: str | None = None
        is_opening_day = any(r.day_number == 1 for r in recs)
        has_conflict = any(r.has_conflict for r in recs)

        for r in sorted(recs, key=lambda x: (x.period_type, x.metric)):
            m_label = _METRIC_LABELS.get(r.metric, r.metric)
            p_label = "Day" if r.period_type == ReportingPeriodType.DAILY.value else "Total"
            if r.day_number and r.period_type == ReportingPeriodType.DAILY.value:
                p_label = f"Day {r.day_number}"
            amt_str = _format_crores(r.reconciled_amount_inr_crores)
            status_short = r.confidence_status.replace("_", " ").title()
            lines.append(f"• {m_label} ({p_label}): {amt_str} [{status_short}]")
            if primary_display is None:
                primary_display = f"{amt_str} • {m_label}"
            report_ids.extend(r.supporting_report_ids or [])

        lang_tag = f"#{movie.primary_language.replace(' ', '')}Cinema"
        hashtags = ["#BoxOffice", lang_tag]
        lines.append("")
        lines.append(" ".join(hashtags))
        text = "\n".join(lines)
        source_summary = (
            f"{len(set(report_ids))} source report(s)"
            + (" • Conflict flagged" if has_conflict else " • Verified")
        )

        cat = DraftCategory.OPENING_DAY if is_opening_day else DraftCategory.MOVIE_WISE
        draft = _persist_draft(
            session,
            category=cat,
            title=f"{movie.title} — {reporting_date.strftime('%d %b %Y')}",
            reporting_date=reporting_date,
            text=text,
            hashtags=hashtags,
            main_figure_display=primary_display,
            source_summary=source_summary,
            report_ids=report_ids,
            reconciled_id=recs[0].id,
            movie_id=movie_id,
            period_type=recs[0].period_type,
            metric=recs[0].metric,
            expiry_hours=expiry_hours,
        )
        created_drafts.append(draft)

        # Check cumulative milestones (only on CUMULATIVE records)
        for r in recs:
            if r.period_type != ReportingPeriodType.CUMULATIVE.value:
                continue
            for threshold in MILESTONE_THRESHOLDS_CR:
                if r.reconciled_amount_inr_crores >= threshold:
                    m_label = _METRIC_LABELS.get(r.metric, r.metric)
                    m_text = (
                        f"Milestone: {movie.title} crosses ₹{threshold} Cr {m_label}!\n"
                        f"Current {m_label}: {_format_crores(r.reconciled_amount_inr_crores)} "
                        f"({r.confidence_status.replace('_', ' ').title()})\n\n"
                        f"#BoxOffice {lang_tag}"
                    )
                    m_draft = _persist_draft(
                        session,
                        category=DraftCategory.MILESTONES,
                        title=f"{movie.title} crosses ₹{threshold} Cr {m_label}",
                        reporting_date=reporting_date,
                        text=m_text,
                        hashtags=["#BoxOffice", lang_tag],
                        main_figure_display=f"{_format_crores(r.reconciled_amount_inr_crores)} • {m_label}",
                        source_summary=f"{len(set(r.supporting_report_ids or []))} source report(s)",
                        report_ids=list(r.supporting_report_ids or []),
                        reconciled_id=r.id,
                        movie_id=movie_id,
                        period_type=r.period_type,
                        metric=r.metric,
                        expiry_hours=expiry_hours,
                    )
                    created_drafts.append(m_draft)
                    break

    # Top 5 Rankings: India (Daily India Net), Worldwide (Daily Worldwide Gross), and Regional Languages
    ranking_specs: list[tuple[DraftCategory, CollectionMetric, ReportingPeriodType, str | None]] = [
        (DraftCategory.TOP_5_INDIA, CollectionMetric.INDIA_NET, ReportingPeriodType.DAILY, None),
        (DraftCategory.TOP_5_WORLDWIDE, CollectionMetric.WORLDWIDE_GROSS, ReportingPeriodType.DAILY, None),
    ]
    for lang_name, lang_cat in LANGUAGE_TO_CATEGORY.items():
        ranking_specs.append((lang_cat, CollectionMetric.INDIA_NET, ReportingPeriodType.DAILY, lang_name))

    for cat, metric, period, lang_filter in ranking_specs:
        ranking = build_top_5_ranking(
            session,
            category=cat,
            reporting_date=reporting_date,
            metric=metric,
            period_type=period,
            language_filter=lang_filter,
        )
        if ranking is None:
            continue
        r_text, r_tags, r_title = _format_ranking_draft(ranking)
        all_r_ids = [rid for e in ranking.entries for rid in e.supporting_report_ids]
        entries_json = [
            {
                "rank": e.rank,
                "movie_id": e.movie_id,
                "title": e.title,
                "language": e.language,
                "amount_inr_crores": str(e.amount_inr_crores),
                "confidence_status": e.confidence_status,
            }
            for e in ranking.entries
        ]
        lead = ranking.entries[0]
        r_draft = _persist_draft(
            session,
            category=cat,
            title=r_title,
            reporting_date=reporting_date,
            text=r_text,
            hashtags=r_tags,
            main_figure_display=f"#1 {lead.title}: {_format_crores(lead.amount_inr_crores)}",
            source_summary=ranking.methodology_note,
            report_ids=all_r_ids,
            period_type=period.value,
            metric=metric.value,
            entries=entries_json,
            expiry_hours=expiry_hours,
        )
        created_drafts.append(r_draft)

    return created_drafts
