"""Pydantic domain schemas and strict enums for CinePulse India."""

from datetime import date, datetime
from decimal import Decimal
from enum import StrEnum
import hashlib
import json

from pydantic import BaseModel, Field, field_validator


class IndianLanguage(StrEnum):
    MALAYALAM = "Malayalam"
    TAMIL = "Tamil"
    TELUGU = "Telugu"
    KANNADA = "Kannada"
    HINDI = "Hindi"
    BENGALI = "Bengali"
    MARATHI = "Marathi"
    PUNJABI = "Punjabi"
    GUJARATI = "Gujarati"
    OTHER = "Other"


class CollectionMetric(StrEnum):
    INDIA_NET = "INDIA_NET"
    INDIA_GROSS = "INDIA_GROSS"
    OVERSEAS_GROSS = "OVERSEAS_GROSS"
    WORLDWIDE_GROSS = "WORLDWIDE_GROSS"


class ReportingPeriodType(StrEnum):
    DAILY = "DAILY"
    CUMULATIVE = "CUMULATIVE"


class ReportSourceStatus(StrEnum):
    ESTIMATE = "ESTIMATE"
    UPDATED_ESTIMATE = "UPDATED_ESTIMATE"
    TRADE_REPORTED = "TRADE_REPORTED"
    PRODUCER_REPORTED = "PRODUCER_REPORTED"
    REPORTED_FINAL = "REPORTED_FINAL"
    AUDITED = "AUDITED"


class DraftCategory(StrEnum):
    MOVIE_WISE = "MOVIE_WISE"
    TOP_5_INDIA = "TOP_5_INDIA"
    TOP_5_WORLDWIDE = "TOP_5_WORLDWIDE"
    MALAYALAM_TOP_5 = "MALAYALAM_TOP_5"
    TAMIL_TOP_5 = "TAMIL_TOP_5"
    TELUGU_TOP_5 = "TELUGU_TOP_5"
    KANNADA_TOP_5 = "KANNADA_TOP_5"
    HINDI_TOP_5 = "HINDI_TOP_5"
    BENGALI_TOP_5 = "BENGALI_TOP_5"
    MARATHI_TOP_5 = "MARATHI_TOP_5"
    OPENING_DAY = "OPENING_DAY"
    MILESTONES = "MILESTONES"
    LATEST_UPDATES = "LATEST_UPDATES"


class DraftStatus(StrEnum):
    PENDING_REVIEW = "PENDING_REVIEW"
    EDITED = "EDITED"
    PUBLISHING = "PUBLISHING"
    PUBLISHED = "PUBLISHED"
    FAILED = "FAILED"
    EXPIRED = "EXPIRED"
    CANCELLED = "CANCELLED"


class AccessMethod(StrEnum):
    AUTHORIZED_API = "AUTHORIZED_API"
    LICENSED_FEED = "LICENSED_FEED"
    PERMITTED_RSS = "PERMITTED_RSS"
    OFFICIAL_ANNOUNCEMENT = "OFFICIAL_ANNOUNCEMENT"
    MANUAL_IMPORT = "MANUAL_IMPORT"


class MovieMetadataInput(BaseModel):
    tmdb_id: int | None = None
    title: str = Field(min_length=1, max_length=256)
    original_title: str | None = None
    primary_language: IndianLanguage
    languages: list[IndianLanguage] = Field(default_factory=list)
    release_date: date | None = None
    poster_path: str | None = None
    production_companies: list[dict] = Field(default_factory=list)
    overview: str | None = None


class RawCollectionReportInput(BaseModel):
    source_code: str = Field(min_length=2, max_length=64)
    movie_title: str = Field(min_length=1, max_length=256)
    tmdb_id: int | None = None
    language: IndianLanguage | None = None
    metric: CollectionMetric
    period_type: ReportingPeriodType
    day_number: int | None = Field(default=None, ge=1, le=1000)
    reporting_date: date
    amount_inr_crores: Decimal = Field(ge=Decimal("0"))
    currency: str = Field(default="INR", min_length=3, max_length=8)
    source_status: ReportSourceStatus
    source_url: str = Field(min_length=4)
    original_report_ref: str | None = None
    published_at: datetime | None = None

    @field_validator("amount_inr_crores")
    @classmethod
    def quantize_amount(cls, value: Decimal) -> Decimal:
        return value.quantize(Decimal("0.0001"))

    def compute_content_hash(self) -> str:
        """Deterministic SHA-256 hash for duplicate report detection."""
        payload = {
            "source_code": self.source_code,
            "movie_title": self.movie_title.strip().lower(),
            "metric": self.metric.value,
            "period_type": self.period_type.value,
            "reporting_date": self.reporting_date.isoformat(),
            "amount_inr_crores": str(self.amount_inr_crores),
            "source_status": self.source_status.value,
        }
        encoded = json.dumps(payload, sort_keys=True).encode("utf-8")
        return hashlib.sha256(encoded).hexdigest()


class AdapterResult(BaseModel):
    source_code: str
    success: bool
    reports: list[RawCollectionReportInput] = Field(default_factory=list)
    error_message: str | None = None
    health_status: str = "HEALTHY"
