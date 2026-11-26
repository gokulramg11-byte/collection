"""SQLAlchemy ORM models mirroring the Supabase PostgreSQL schema."""

from datetime import date, datetime, timezone
from decimal import Decimal
import uuid

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Integer,
    JSON,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    Uuid,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.session import Base


def utcnow() -> datetime:
    """Return timezone-aware UTC timestamp."""
    return datetime.now(timezone.utc)


class Movie(Base):
    __tablename__ = "movies"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    tmdb_id: Mapped[int | None] = mapped_column(Integer, unique=True, nullable=True)
    title: Mapped[str] = mapped_column(Text, nullable=False)
    original_title: Mapped[str | None] = mapped_column(Text, nullable=True)
    primary_language: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    languages: Mapped[list[str]] = mapped_column(JSON, nullable=False, default=list)
    release_date: Mapped[date | None] = mapped_column(Date, nullable=True, index=True)
    poster_path: Mapped[str | None] = mapped_column(Text, nullable=True)
    production_companies: Mapped[list[dict]] = mapped_column(JSON, nullable=False, default=list)
    overview: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_monitored: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utcnow, onupdate=utcnow)

    reports: Mapped[list["CollectionReport"]] = relationship(back_populates="movie")


class Source(Base):
    __tablename__ = "sources"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    code: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    name: Mapped[str] = mapped_column(Text, nullable=False)
    access_method: Mapped[str] = mapped_column(String(48), nullable=False)
    base_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    priority: Mapped[int] = mapped_column(Integer, nullable=False, default=100)
    reliability_score: Mapped[Decimal] = mapped_column(Numeric(4, 3), nullable=False, default=Decimal("0.800"))
    health_status: Mapped[str] = mapped_column(String(32), nullable=False, default="HEALTHY")
    last_success_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utcnow, onupdate=utcnow)


class CollectionReport(Base):
    __tablename__ = "collection_reports"
    __table_args__ = (
        UniqueConstraint(
            "movie_id",
            "source_id",
            "metric",
            "period_type",
            "reporting_date",
            "content_hash",
            name="uq_report_dedup",
        ),
        CheckConstraint("amount_inr_crores >= 0", name="ck_report_non_negative"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    movie_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("movies.id"), nullable=False, index=True)
    source_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("sources.id"), nullable=False)
    metric: Mapped[str] = mapped_column(String(32), nullable=False)
    period_type: Mapped[str] = mapped_column(String(24), nullable=False)
    day_number: Mapped[int | None] = mapped_column(Integer, nullable=True)
    reporting_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    amount_inr_crores: Mapped[Decimal] = mapped_column(Numeric(12, 4), nullable=False)
    currency: Mapped[str] = mapped_column(String(8), nullable=False, default="INR")
    source_status: Mapped[str] = mapped_column(String(32), nullable=False)
    source_url: Mapped[str] = mapped_column(Text, nullable=False)
    original_report_ref: Mapped[str | None] = mapped_column(Text, nullable=True)
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    retrieved_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utcnow)
    content_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    is_duplicate: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    revision_number: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utcnow)

    movie: Mapped[Movie] = relationship(back_populates="reports")
    source: Mapped[Source] = relationship()


class CollectionRevision(Base):
    __tablename__ = "collection_revisions"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    report_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("collection_reports.id"), nullable=False)
    previous_amount: Mapped[Decimal] = mapped_column(Numeric(12, 4), nullable=False)
    new_amount: Mapped[Decimal] = mapped_column(Numeric(12, 4), nullable=False)
    previous_status: Mapped[str] = mapped_column(String(32), nullable=False)
    new_status: Mapped[str] = mapped_column(String(32), nullable=False)
    revision_number: Mapped[int] = mapped_column(Integer, nullable=False)
    detected_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utcnow)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)


class ReconciledCollection(Base):
    __tablename__ = "reconciled_collections"
    __table_args__ = (
        UniqueConstraint("movie_id", "metric", "period_type", "reporting_date", name="uq_reconciled_unique"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    movie_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("movies.id"), nullable=False)
    metric: Mapped[str] = mapped_column(String(32), nullable=False)
    period_type: Mapped[str] = mapped_column(String(24), nullable=False)
    reporting_date: Mapped[date] = mapped_column(Date, nullable=False)
    day_number: Mapped[int | None] = mapped_column(Integer, nullable=True)
    reconciled_amount_inr_crores: Mapped[Decimal] = mapped_column(Numeric(12, 4), nullable=False)
    confidence_status: Mapped[str] = mapped_column(String(32), nullable=False)
    has_conflict: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    conflict_details: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    supporting_report_ids: Mapped[list[str]] = mapped_column(JSON, nullable=False, default=list)
    methodology_note: Mapped[str] = mapped_column(Text, nullable=False)
    reconciled_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utcnow, onupdate=utcnow)


class PostDraft(Base):
    __tablename__ = "post_drafts"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    category: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    title: Mapped[str] = mapped_column(Text, nullable=False)
    movie_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("movies.id"), nullable=True)
    reporting_date: Mapped[date] = mapped_column(Date, nullable=False)
    period_type: Mapped[str | None] = mapped_column(String(24), nullable=True)
    metric: Mapped[str | None] = mapped_column(String(32), nullable=True)
    generated_text: Mapped[str] = mapped_column(Text, nullable=False)
    edited_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    hashtags: Mapped[list[str]] = mapped_column(JSON, nullable=False, default=list)
    entries: Mapped[list[dict]] = mapped_column(JSON, nullable=False, default=list)
    main_figure_display: Mapped[str | None] = mapped_column(String(128), nullable=True)
    source_summary: Mapped[str] = mapped_column(Text, nullable=False)
    weighted_char_count: Mapped[int] = mapped_column(Integer, nullable=False)
    is_valid_length: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    status: Mapped[str] = mapped_column(String(24), nullable=False, default="PENDING_REVIEW", index=True)
    numerical_edit_confirmed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    numerical_edit_audit: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utcnow, onupdate=utcnow)


class PostSource(Base):
    __tablename__ = "post_sources"
    __table_args__ = (UniqueConstraint("draft_id", "report_id", name="uq_post_source"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    draft_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("post_drafts.id"), nullable=False)
    report_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("collection_reports.id"), nullable=False)
    reconciled_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("reconciled_collections.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utcnow)


class AppUser(Base):
    __tablename__ = "app_users"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(Text, nullable=False)
    display_name: Mapped[str | None] = mapped_column(Text, nullable=True)
    role: Mapped[str] = mapped_column(String(32), nullable=False, default="OPERATOR")
    notification_prefs: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utcnow, onupdate=utcnow)


class PublishedPost(Base):
    __tablename__ = "published_posts"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    draft_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("post_drafts.id"), unique=True, nullable=False)
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("app_users.id"), nullable=False)
    final_text: Mapped[str] = mapped_column(Text, nullable=False)
    x_post_id: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    x_url: Mapped[str] = mapped_column(Text, nullable=False)
    category: Mapped[str] = mapped_column(String(32), nullable=False)
    supporting_report_ids: Mapped[list[str]] = mapped_column(JSON, nullable=False, default=list)
    published_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utcnow)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utcnow)


class CollectionRun(Base):
    __tablename__ = "collection_runs"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    trigger_type: Mapped[str] = mapped_column(String(24), nullable=False)
    status: Mapped[str] = mapped_column(String(24), nullable=False, default="RUNNING")
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utcnow)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    movies_discovered: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    reports_collected: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    conflicts_detected: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    drafts_generated: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    drafts_expired: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    source_results: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    error_summary: Mapped[str | None] = mapped_column(Text, nullable=True)
