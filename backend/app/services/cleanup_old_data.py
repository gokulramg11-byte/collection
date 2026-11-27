"""Stale data cleanup service to keep current-day views free of old records."""

from datetime import date, datetime, timedelta, timezone

from sqlalchemy import delete, update
from sqlalchemy.orm import Session

from app.models.entities import Movie, PostDraft, ReconciledCollection
from app.schemas.domain import DraftStatus, ReportingPeriodType, TARGET_LANGUAGES


def cleanup_stale_state(session: Session, reference_date: date | None = None) -> dict[str, int]:
    """Expire old pending drafts and remove stale DAILY reconciled entries (>60 days)."""
    today = reference_date or datetime.now(timezone.utc).date()
    daily_cutoff = today - timedelta(days=60)
    draft_cutoff = today - timedelta(days=2)
    allowed_langs = {lang.value for lang in TARGET_LANGUAGES}

    # 1. Expire any pending/edited drafts from >2 days ago so old drafts don't linger
    expired_res = session.execute(
        update(PostDraft)
        .where(
            PostDraft.status.in_([DraftStatus.PENDING_REVIEW.value, DraftStatus.EDITED.value]),
            PostDraft.reporting_date < draft_cutoff,
        )
        .values(status=DraftStatus.EXPIRED.value)
    )

    # 2. Remove stale DAILY reconciled rows older than 60 days (preserves CUMULATIVE history)
    stale_daily_res = session.execute(
        delete(ReconciledCollection).where(
            ReconciledCollection.period_type == ReportingPeriodType.DAILY.value,
            ReconciledCollection.reporting_date < daily_cutoff,
        )
    )

    # 3. Demote/unmonitor movies outside the 6 target languages
    unmonitored_res = session.execute(
        update(Movie)
        .where(Movie.primary_language.notin_(allowed_langs), Movie.is_monitored.is_(True))
        .values(is_monitored=False)
    )

    session.flush()
    return {
        "expired_old_drafts": int(expired_res.rowcount or 0),
        "removed_stale_daily": int(stale_daily_res.rowcount or 0),
        "unmonitored_other_langs": int(unmonitored_res.rowcount or 0),
    }
