"""Sanitized JSON exporter for serverless GitHub `data` branch storage.

SECURITY: Exports ONLY public-safe box-office analytics and pending drafts.
Never exports credentials, API keys, user emails, or OAuth tokens.
"""

from datetime import datetime, timezone
import json
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.entities import (
    CollectionReport,
    CollectionRun,
    Movie,
    PostDraft,
    ReconciledCollection,
    Source,
)
from app.schemas.domain import DraftStatus


def _iso(dt: datetime | None) -> str | None:
    if dt is None:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc).isoformat()


def export_github_json(session: Session, output_dir: str | Path) -> dict[str, int]:
    """Export sanitized JSON snapshots to `output_dir` for the Flutter app."""
    out = Path(output_dir)
    out.mkdir(parents=True, exist_ok=True)

    movies = session.scalars(select(Movie).order_by(Movie.release_date.desc())).all()
    sources = session.scalars(select(Source).order_by(Source.priority)).all()
    reports = session.scalars(
        select(CollectionReport).order_by(CollectionReport.reporting_date.desc())
    ).all()
    reconciled = session.scalars(
        select(ReconciledCollection).order_by(ReconciledCollection.reporting_date.desc())
    ).all()
    drafts = session.scalars(
        select(PostDraft)
        .where(
            PostDraft.status.in_(
                [
                    DraftStatus.PENDING_REVIEW.value,
                    DraftStatus.EDITED.value,
                    DraftStatus.FAILED.value,
                ]
            )
        )
        .order_by(PostDraft.created_at.desc())
    ).all()
    runs = session.scalars(
        select(CollectionRun).order_by(CollectionRun.started_at.desc()).limit(20)
    ).all()

    sources_by_id = {s.id: s for s in sources}

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
