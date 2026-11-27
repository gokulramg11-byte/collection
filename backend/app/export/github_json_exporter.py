"""Sanitized JSON exporter for serverless GitHub `data` branch storage.

Enforces strict separation so old (e.g. February) daily records never mix
with current-day collections:
- `DAILY` reports/reconciled: exported only for active releases (<= 60 days)
  and recent reporting dates (<= 30 days).
- `CUMULATIVE` reports/reconciled: exported only for current-year films
  (for Language-Wise Current-Year Top 5).
- `movies.json`: strictly the 6 target languages (Malayalam, Tamil, English,
  Hindi, Telugu, Kannada).
"""

from datetime import date, datetime, timedelta, timezone
import json
from pathlib import Path

from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.models.entities import (
    CollectionReport,
    CollectionRun,
    Movie,
    PostDraft,
    ReconciledCollection,
    Source,
)
from app.schemas.domain import DraftStatus, ReportingPeriodType, TARGET_LANGUAGES


def _iso(dt: datetime | None) -> str | None:
    if dt is None:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc).isoformat()


def export_github_json(
    session: Session,
    output_dir: str | Path,
    reference_date: date | None = None,
) -> dict[str, int]:
    """Export sanitized, date-separated JSON snapshots to `output_dir`."""
    out = Path(output_dir)
    out.mkdir(parents=True, exist_ok=True)

    today = reference_date or datetime.now(timezone.utc).date()
    year_start = date(today.year, 1, 1)
    daily_report_cutoff = today - timedelta(days=30)
    active_release_cutoff = today - timedelta(days=60)
    draft_cutoff = today - timedelta(days=2)
    allowed_langs = {lang.value for lang in TARGET_LANGUAGES}

    movies = session.scalars(
        select(Movie)
        .where(
            Movie.primary_language.in_(allowed_langs),
            or_(Movie.release_date.is_(None), Movie.release_date >= year_start),
        )
        .order_by(Movie.release_date.desc())
    ).all()
    movie_by_id = {m.id: m for m in movies}
    movie_ids = set(movie_by_id.keys())

    sources = session.scalars(select(Source).order_by(Source.priority)).all()
    sources_by_id = {s.id: s for s in sources}

    all_reports = session.scalars(
        select(CollectionReport)
        .where(CollectionReport.movie_id.in_(movie_ids))
        .order_by(CollectionReport.reporting_date.desc())
    ).all() if movie_ids else []

    reports = []
    for r in all_reports:
        m = movie_by_id.get(r.movie_id)
        if r.period_type == ReportingPeriodType.DAILY.value:
            if r.reporting_date < daily_report_cutoff:
                continue
            if m and m.release_date and m.release_date < active_release_cutoff:
                continue
        reports.append(r)

    all_reconciled = session.scalars(
        select(ReconciledCollection)
        .where(ReconciledCollection.movie_id.in_(movie_ids))
        .order_by(ReconciledCollection.reporting_date.desc())
    ).all() if movie_ids else []

    reconciled = []
    for rc in all_reconciled:
        m = movie_by_id.get(rc.movie_id)
        if rc.period_type == ReportingPeriodType.DAILY.value:
            if rc.reporting_date < daily_report_cutoff:
                continue
            if m and m.release_date and m.release_date < active_release_cutoff:
                continue
        reconciled.append(rc)

    drafts = session.scalars(
        select(PostDraft)
        .where(
            PostDraft.status.in_(
                [
                    DraftStatus.PENDING_REVIEW.value,
                    DraftStatus.EDITED.value,
                    DraftStatus.FAILED.value,
                ]
            ),
            PostDraft.reporting_date >= draft_cutoff,
        )
        .order_by(PostDraft.created_at.desc())
    ).all()

    runs = session.scalars(
        select(CollectionRun).order_by(CollectionRun.started_at.desc()).limit(20)
    ).all()

    (out / "movies.json").write_text(
        json.dumps(
            [
                {
                    "id": str(m.id),
                    "tmdb_id": m.tmdb_id,
                    "title": m.title,
                    "original_title": m.original_title,
                    "primary_language": m.primary_language,
                    "languages": m.languages,
                    "release_date": m.release_date.isoformat() if m.release_date else None,
                    "poster_path": m.poster_path,
                    "overview": m.overview,
                    "is_monitored": m.is_monitored,
                }
                for m in movies
            ],
            indent=2,
        ),
        encoding="utf-8",
    )

    (out / "sources.json").write_text(
        json.dumps(
            [
                {
                    "id": str(s.id),
                    "code": s.code,
                    "name": s.name,
                    "access_method": s.access_method,
                    "health_status": s.health_status,
                    "last_success_at": _iso(s.last_success_at),
                    "last_error": s.last_error,
                }
                for s in sources
            ],
            indent=2,
        ),
        encoding="utf-8",
    )

    (out / "reports.json").write_text(
        json.dumps(
            [
                {
                    "id": str(r.id),
                    "movie_id": str(r.movie_id),
                    "source_id": str(r.source_id),
                    "sources": {
                        "name": sources_by_id[r.source_id].name
                        if r.source_id in sources_by_id
                        else "Verified Source"
                    },
                    "metric": r.metric,
                    "period_type": r.period_type,
                    "day_number": r.day_number,
                    "reporting_date": r.reporting_date.isoformat(),
                    "amount_inr_crores": str(r.amount_inr_crores),
                    "currency": r.currency,
                    "source_status": r.source_status,
                    "source_url": r.source_url,
                    "original_report_ref": r.original_report_ref,
                    "published_at": _iso(r.published_at),
                    "retrieved_at": _iso(r.retrieved_at),
                    "revision_number": r.revision_number,
                }
                for r in reports
            ],
            indent=2,
        ),
        encoding="utf-8",
    )

    (out / "reconciled.json").write_text(
        json.dumps(
            [
                {
                    "id": str(rc.id),
                    "movie_id": str(rc.movie_id),
                    "metric": rc.metric,
                    "period_type": rc.period_type,
                    "day_number": rc.day_number,
                    "reporting_date": rc.reporting_date.isoformat(),
                    "reconciled_amount_inr_crores": str(rc.reconciled_amount_inr_crores),
                    "confidence_status": rc.confidence_status,
                    "has_conflict": rc.has_conflict,
                    "conflict_details": rc.conflict_details,
                    "supporting_report_ids": rc.supporting_report_ids,
                    "methodology_note": rc.methodology_note,
                }
                for rc in reconciled
            ],
            indent=2,
        ),
        encoding="utf-8",
    )

    (out / "drafts.json").write_text(
        json.dumps(
            [
                {
                    "id": str(d.id),
                    "category": d.category,
                    "title": d.title,
                    "movie_id": str(d.movie_id) if d.movie_id else None,
                    "reporting_date": d.reporting_date.isoformat(),
                    "generated_text": d.generated_text,
                    "edited_text": d.edited_text,
                    "hashtags": d.hashtags,
                    "entries": d.entries,
                    "main_figure_display": d.main_figure_display,
                    "source_summary": d.source_summary,
                    "weighted_char_count": d.weighted_char_count,
                    "is_valid_length": d.is_valid_length,
                    "status": d.status,
                    "numerical_edit_confirmed": d.numerical_edit_confirmed,
                    "last_error": d.last_error,
                    "expires_at": _iso(d.expires_at),
                    "created_at": _iso(d.created_at),
                }
                for d in drafts
            ],
            indent=2,
        ),
        encoding="utf-8",
    )

    (out / "runs.json").write_text(
        json.dumps(
            [
                {
                    "id": str(run.id),
                    "trigger_type": run.trigger_type,
                    "status": run.status,
                    "started_at": _iso(run.started_at),
                    "completed_at": _iso(run.completed_at),
                    "movies_discovered": run.movies_discovered,
                    "reports_collected": run.reports_collected,
                    "conflicts_detected": run.conflicts_detected,
                    "drafts_generated": run.drafts_generated,
                    "error_summary": run.error_summary,
                }
                for run in runs
            ],
            indent=2,
        ),
        encoding="utf-8",
    )

    (out / "manifest.json").write_text(
        json.dumps(
            {
                "exported_at": datetime.now(timezone.utc).isoformat(),
                "reference_date": today.isoformat(),
                "movies_count": len(movies),
                "drafts_count": len(drafts),
                "reports_count": len(reports),
                "conflicts_count": sum(1 for rc in reconciled if rc.has_conflict),
            },
            indent=2,
        ),
        encoding="utf-8",
    )

    return {
        "movies": len(movies),
        "sources": len(sources),
        "reports": len(reports),
        "reconciled": len(reconciled),
        "drafts": len(drafts),
        "runs": len(runs),
    }
