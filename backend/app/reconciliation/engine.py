"""Transparent box-office report ingestion, revision tracking, and reconciliation."""

from dataclasses import dataclass
from datetime import date
from decimal import Decimal
import uuid

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.entities import (
    CollectionReport,
    CollectionRevision,
    Movie,
    ReconciledCollection,
    Source,
)
from app.schemas.domain import RawCollectionReportInput, ReportSourceStatus
from app.services.movie_matcher import match_movie_for_report
from app.validators.collection_validator import validate_collection_report

# Higher rank = higher authority. Never average conflicting numbers!
STATUS_AUTHORITY_RANK: dict[str, int] = {
    ReportSourceStatus.AUDITED.value: 6,
    ReportSourceStatus.REPORTED_FINAL.value: 5,
    ReportSourceStatus.PRODUCER_REPORTED.value: 4,
    ReportSourceStatus.TRADE_REPORTED.value: 3,
    ReportSourceStatus.UPDATED_ESTIMATE.value: 2,
    ReportSourceStatus.ESTIMATE.value: 1,
}


@dataclass(frozen=True)
class IngestionOutcome:
    saved_report: CollectionReport | None
    is_duplicate: bool
    revision_recorded: bool


def ingest_report(
    session: Session,
    source: Source,
    raw: RawCollectionReportInput,
) -> IngestionOutcome:
    """Validate and persist a source-specific report, detecting duplicates and revisions."""
    movie: Movie = match_movie_for_report(session, raw)
    validate_collection_report(raw, movie_release_date=movie.release_date)

    content_hash = raw.compute_content_hash()
    exact_dup = session.scalar(
        select(CollectionReport).where(
            CollectionReport.movie_id == movie.id,
            CollectionReport.source_id == source.id,
            CollectionReport.metric == raw.metric.value,
            CollectionReport.period_type == raw.period_type.value,
            CollectionReport.reporting_date == raw.reporting_date,
            CollectionReport.content_hash == content_hash,
        )
    )
    if exact_dup is not None:
        return IngestionOutcome(saved_report=exact_dup, is_duplicate=True, revision_recorded=False)

    # Check if this source already reported for the same movie/metric/period/date (a revision!)
    prior_reports = session.scalars(
        select(CollectionReport)
        .where(
            CollectionReport.movie_id == movie.id,
            CollectionReport.source_id == source.id,
            CollectionReport.metric == raw.metric.value,
            CollectionReport.period_type == raw.period_type.value,
            CollectionReport.reporting_date == raw.reporting_date,
        )
        .order_by(CollectionReport.revision_number.desc())
    ).all()

    next_rev = (prior_reports[0].revision_number + 1) if prior_reports else 1

    new_report = CollectionReport(
        movie_id=movie.id,
        source_id=source.id,
        metric=raw.metric.value,
        period_type=raw.period_type.value,
        day_number=raw.day_number,
        reporting_date=raw.reporting_date,
        amount_inr_crores=raw.amount_inr_crores,
        currency=raw.currency.upper(),
        source_status=raw.source_status.value,
        source_url=raw.source_url,
        original_report_ref=raw.original_report_ref,
        published_at=raw.published_at,
        content_hash=content_hash,
        is_duplicate=False,
        revision_number=next_rev,
    )
    session.add(new_report)
    session.flush()

    revision_recorded = False
    if prior_reports:
        prev = prior_reports[0]
        session.add(
            CollectionRevision(
                report_id=new_report.id,
                previous_amount=prev.amount_inr_crores,
                new_amount=new_report.amount_inr_crores,
                previous_status=prev.source_status,
                new_status=new_report.source_status,
                revision_number=next_rev,
                notes=f"Revised from {prev.amount_inr_crores} ({prev.source_status}) to {new_report.amount_inr_crores} ({new_report.source_status})",
            )
        )
        revision_recorded = True

    return IngestionOutcome(
        saved_report=new_report,
        is_duplicate=False,
        revision_recorded=revision_recorded,
    )


def reconcile_bucket(
    session: Session,
    movie_id: uuid.UUID,
    metric: str,
    period_type: str,
    reporting_date: date,
    conflict_threshold_pct: float = 5.0,
) -> ReconciledCollection | None:
    """Reconcile only compatible reports (same movie, metric, period_type, reporting_date).

    Never averages conflicting values. Selects the highest-authority report and
    preserves all competing reports in conflict_details.
    """
    reports = session.scalars(
        select(CollectionReport).where(
            CollectionReport.movie_id == movie_id,
            CollectionReport.metric == metric,
            CollectionReport.period_type == period_type,
            CollectionReport.reporting_date == reporting_date,
            CollectionReport.is_duplicate.is_(False),
        )
    ).all()

    if not reports:
        return None

    # Keep only the latest revision per source_id
    latest_by_source: dict[uuid.UUID, CollectionReport] = {}
    for r in reports:
        existing = latest_by_source.get(r.source_id)
        if existing is None or r.revision_number > existing.revision_number:
            latest_by_source[r.source_id] = r

    active_reports = list(latest_by_source.values())
    sources_by_id = {
        s.id: s
        for s in session.scalars(
            select(Source).where(Source.id.in_([r.source_id for r in active_reports]))
        ).all()
    }

    def authority_key(rep: CollectionReport) -> tuple[int, float, int, int]:
        src = sources_by_id.get(rep.source_id)
        status_rank = STATUS_AUTHORITY_RANK.get(rep.source_status, 0)
        reliability = float(src.reliability_score) if src else 0.0
        priority_inv = -(src.priority if src else 999)
        return (status_rank, reliability, priority_inv, rep.revision_number)

    selected = max(active_reports, key=authority_key)

    amounts = [r.amount_inr_crores for r in active_reports]
    min_amt = min(amounts)
    max_amt = max(amounts)
    has_conflict = False
    conflict_details: dict | None = None

    if len(active_reports) > 1 and max_amt > Decimal("0"):
        spread_pct = float(((max_amt - min_amt) / max_amt) * Decimal("100"))
        if spread_pct > conflict_threshold_pct:
            has_conflict = True
            conflict_details = {
                "spread_pct": round(spread_pct, 2),
                "min_inr_crores": str(min_amt),
                "max_inr_crores": str(max_amt),
                "competing_reports": [
                    {
                        "report_id": str(r.id),
                        "source_code": sources_by_id[r.source_id].code if r.source_id in sources_by_id else "unknown",
                        "source_name": sources_by_id[r.source_id].name if r.source_id in sources_by_id else "Unknown",
                        "amount_inr_crores": str(r.amount_inr_crores),
                        "source_status": r.source_status,
                        "source_url": r.source_url,
                    }
                    for r in active_reports
                ],
            }

    selected_src = sources_by_id.get(selected.source_id)
    methodology_note = (
        f"Selected {selected_src.name if selected_src else 'source'} "
        f"({selected.source_status}) out of {len(active_reports)} source(s); "
        "compatible metric/period only, no averaging."
    )

    existing_rec = session.scalar(
        select(ReconciledCollection).where(
            ReconciledCollection.movie_id == movie_id,
            ReconciledCollection.metric == metric,
            ReconciledCollection.period_type == period_type,
            ReconciledCollection.reporting_date == reporting_date,
        )
    )

    report_ids = [str(r.id) for r in active_reports]
    if existing_rec is not None:
        existing_rec.reconciled_amount_inr_crores = selected.amount_inr_crores
        existing_rec.confidence_status = selected.source_status
        existing_rec.has_conflict = has_conflict
        existing_rec.conflict_details = conflict_details
        existing_rec.supporting_report_ids = report_ids
        existing_rec.methodology_note = methodology_note
        existing_rec.day_number = selected.day_number or existing_rec.day_number
        session.flush()
        return existing_rec

    rec = ReconciledCollection(
        movie_id=movie_id,
        metric=metric,
        period_type=period_type,
        reporting_date=reporting_date,
        day_number=selected.day_number,
        reconciled_amount_inr_crores=selected.amount_inr_crores,
        confidence_status=selected.source_status,
        has_conflict=has_conflict,
        conflict_details=conflict_details,
        supporting_report_ids=report_ids,
        methodology_note=methodology_note,
    )
    session.add(rec)
    session.flush()
    return rec
