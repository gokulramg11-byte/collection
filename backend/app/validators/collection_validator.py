"""Validation rules for box-office collection reports."""

from datetime import date
from decimal import Decimal

from app.schemas.domain import RawCollectionReportInput


class ValidationError(ValueError):
    """Raised when a collection report violates data integrity rules."""


def validate_collection_report(
    report: RawCollectionReportInput,
    movie_release_date: date | None = None,
) -> None:
    """Validate metric, amount, currency, and reporting period integrity."""
    if report.amount_inr_crores < Decimal("0"):
        raise ValidationError("Collection amount cannot be negative.")

    if report.amount_inr_crores > Decimal("10000"):
        raise ValidationError("Collection amount exceeds plausible single-film cap (10,000 Cr).")

    if report.currency.upper() != "INR":
        raise ValidationError(f"Unsupported currency '{report.currency}'. Normalize to INR crores before storage.")

    if not report.source_url.strip():
        raise ValidationError("source_url is required for every collection report.")

    if movie_release_date is not None and report.reporting_date < movie_release_date:
        # Allow paid previews up to 2 days before official release
        delta_days = (movie_release_date - report.reporting_date).days
        if delta_days > 2:
            raise ValidationError(
                f"Reporting date {report.reporting_date} is {delta_days} days before release {movie_release_date}."
            )
