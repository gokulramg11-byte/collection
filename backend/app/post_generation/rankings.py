"""Top 5 box-office ranking builder with strict separation between:
1. Current-Year / All-Time Language-Wise Top 5 (CUMULATIVE collections per industry)
2. Current-Day Top 5 (DAILY collections for currently running releases only)
"""

from dataclasses import dataclass
from datetime import date, timedelta
from decimal import Decimal
import uuid

from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.models.entities import Movie, ReconciledCollection
from app.schemas.domain import CollectionMetric, DraftCategory, IndianLanguage, ReportingPeriodType

# Strictly 6 supported languages: Malayalam, Tamil, English, Hindi, Telugu, Kannada
LANGUAGE_TO_CATEGORY: dict[str, DraftCategory] = {
    IndianLanguage.MALAYALAM.value: DraftCategory.MALAYALAM_TOP_5,
    IndianLanguage.TAMIL.value: DraftCategory.TAMIL_TOP_5,
    IndianLanguage.ENGLISH.value: DraftCategory.ENGLISH_TOP_5,
    IndianLanguage.HINDI.value: DraftCategory.HINDI_TOP_5,
    IndianLanguage.TELUGU.value: DraftCategory.TELUGU_TOP_5,
    IndianLanguage.KANNADA.value: DraftCategory.KANNADA_TOP_5,
}

ACTIVE_THEATRICAL_WINDOW_DAYS = 60


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
    """Build a Current-Day DAILY Top 5 ranking for currently running movies only."""
    cutoff_release = reporting_date - timedelta(days=ACTIVE_THEATRICAL_WINDOW_DAYS)
    stmt = (
        select(ReconciledCollection, Movie)
        .join(Movie, ReconciledCollection.movie_id == Movie.id)
        .where(
            ReconciledCollection.reporting_date == reporting_date,
            ReconciledCollection.metric == metric.value,
            ReconciledCollection.period_type == period_type.value,
            or_(Movie.release_date.is_(None), Movie.release_date >= cutoff_release),
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
        f"Current-day {metric.value} ({period_type.value}) on {reporting_date.isoformat()} "
        f"for {scope_label} (active releases <= {ACTIVE_THEATRICAL_WINDOW_DAYS}d). "
        f"Coverage: {len(entries)}/5."
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


def build_current_year_language_top_5(
    session: Session,
    category: DraftCategory,
    language_filter: str,
    reference_date: date,
    metric: CollectionMetric = CollectionMetric.WORLDWIDE_GROSS,
    current_year_only: bool = True,
    min_entries: int = 2,
) -> Top5RankingResult | None:
    """Build a Language-Wise Top 5 from CUMULATIVE totals (Current Year or All-Time)."""
    stmt = (
        select(ReconciledCollection, Movie)
        .join(Movie, ReconciledCollection.movie_id == Movie.id)
        .where(
            Movie.primary_language == language_filter,
            ReconciledCollection.metric == metric.value,
            ReconciledCollection.period_type == ReportingPeriodType.CUMULATIVE.value,
            ReconciledCollection.reporting_date <= reference_date,
        )
        .order_by(ReconciledCollection.reporting_date.desc())
    )
    if current_year_only:
        year_start = date(reference_date.year, 1, 1)
        stmt = stmt.where(Movie.release_date >= year_start)

    rows = session.execute(stmt).all()

    # Keep only the latest cumulative record per movie_id
    latest_per_movie: dict[uuid.UUID, tuple[ReconciledCollection, Movie]] = {}
    for rec, movie in rows:
        if movie.id not in latest_per_movie:
            latest_per_movie[movie.id] = (rec, movie)

    if len(latest_per_movie) < min_entries:
        return None

    sorted_movies = sorted(
        latest_per_movie.values(),
        key=lambda pair: pair[0].reconciled_amount_inr_crores,
        reverse=True,
    )[:5]

    entries: list[RankedMovieEntry] = []
    statuses: set[str] = set()
    for idx, (rec, movie) in enumerate(sorted_movies, start=1):
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

    scope = f"{reference_date.year} {language_filter}" if current_year_only else f"All-Time {language_filter}"
    methodology = (
        f"{scope} Top {len(entries)} ({metric.value}, CUMULATIVE). "
        f"Coverage: {len(entries)}/5."
    )
    return Top5RankingResult(
        category=category,
        metric=metric,
        period_type=ReportingPeriodType.CUMULATIVE,
        reporting_date=reference_date,
        entries=entries,
        is_partial=len(entries) < 5,
        has_mixed_confidence=len(statuses) > 1,
        methodology_note=methodology,
    )
