"""Top 5 box-office ranking builder with strict metric and period comparability."""

from dataclasses import dataclass
from datetime import date
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.entities import Movie, ReconciledCollection
from app.schemas.domain import CollectionMetric, DraftCategory, IndianLanguage, ReportingPeriodType

LANGUAGE_TO_CATEGORY: dict[str, DraftCategory] = {
    IndianLanguage.MALAYALAM.value: DraftCategory.MALAYALAM_TOP_5,
    IndianLanguage.TAMIL.value: DraftCategory.TAMIL_TOP_5,
    IndianLanguage.TELUGU.value: DraftCategory.TELUGU_TOP_5,
    IndianLanguage.KANNADA.value: DraftCategory.KANNADA_TOP_5,
    IndianLanguage.HINDI.value: DraftCategory.HINDI_TOP_5,
    IndianLanguage.BENGALI.value: DraftCategory.BENGALI_TOP_5,
    IndianLanguage.MARATHI.value: DraftCategory.MARATHI_TOP_5,
}


@dataclass(frozen=True)
class RankedMovieEntry:
    rank: int
    movie_id: str
    title: str
    language: str
    amount_inr_crores: Decimal
    confidence_status: str
    reconciled_id: str
    supporting_report_ids: list[str]


@dataclass(frozen=True)
class Top5RankingResult:
    category: DraftCategory
    metric: CollectionMetric
    period_type: ReportingPeriodType
    reporting_date: date
    entries: list[RankedMovieEntry]
    is_partial: bool
    has_mixed_confidence: bool
    methodology_note: str


def build_top_5_ranking(
    session: Session,
    category: DraftCategory,
    reporting_date: date,
    metric: CollectionMetric,
    period_type: ReportingPeriodType,
    language_filter: str | None = None,
    min_entries: int = 2,
) -> Top5RankingResult | None:
    """Build a comparable Top 5 ranking for a single metric, period_type, and date."""
    stmt = (
        select(ReconciledCollection, Movie)
        .join(Movie, ReconciledCollection.movie_id == Movie.id)
        .where(
            ReconciledCollection.reporting_date == reporting_date,
            ReconciledCollection.metric == metric.value,
            ReconciledCollection.period_type == period_type.value,
        )
        .order_by(ReconciledCollection.reconciled_amount_inr_crores.desc())
    )
    if language_filter:
        stmt = stmt.where(Movie.primary_language == language_filter)

    rows = session.execute(stmt).all()
    if len(rows) < min_entries:
        return None

    top_rows = rows[:5]
    entries: list[RankedMovieEntry] = []
    statuses: set[str] = set()
    for idx, (rec, movie) in enumerate(top_rows, start=1):
        statuses.add(rec.confidence_status)
        entries.append(
            RankedMovieEntry(
                rank=idx,
                movie_id=str(movie.id),
                title=movie.title,
                language=movie.primary_language,
                amount_inr_crores=rec.reconciled_amount_inr_crores,
                confidence_status=rec.confidence_status,
                reconciled_id=str(rec.id),
                supporting_report_ids=list(rec.supporting_report_ids or []),
            )
        )

    is_partial = len(entries) < 5
    has_mixed = len(statuses) > 1
    scope_label = language_filter or ("Worldwide" if metric == CollectionMetric.WORLDWIDE_GROSS else "India")
    methodology = (
        f"Comparable {metric.value} ({period_type.value}) on {reporting_date.isoformat()} "
        f"for {scope_label}. Coverage: {len(entries)}/5."
    )
    if has_mixed:
        methodology += " Mixed report statuses noted."

    return Top5RankingResult(
        category=category,
        metric=metric,
        period_type=period_type,
        reporting_date=reporting_date,
        entries=entries,
        is_partial=is_partial,
        has_mixed_confidence=has_mixed,
        methodology_note=methodology,
    )
