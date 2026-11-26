"""Idempotent draft expiry cleanup service."""

from datetime import datetime, timezone

from sqlalchemy import update
from sqlalchemy.orm import Session

from app.models.entities import PostDraft
from app.schemas.domain import DraftStatus


def expire_stale_drafts(session: Session, now: datetime | None = None) -> int:
    """Expire PENDING_REVIEW and EDITED drafts past expires_at.

    Never expires PUBLISHED, FAILED, or PUBLISHING drafts, and never deletes
    source reports, historical collections, or published audit records.
    """
    current_time = now or datetime.now(timezone.utc)
    stmt = (
        update(PostDraft)
        .where(
            PostDraft.status.in_([DraftStatus.PENDING_REVIEW.value, DraftStatus.EDITED.value]),
            PostDraft.expires_at <= current_time,
        )
        .values(status=DraftStatus.EXPIRED.value, updated_at=current_time)
    )
    result = session.execute(stmt)
    session.flush()
    return int(result.rowcount or 0)
