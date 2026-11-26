"""Manual JSON/CSV import adapter for official producer/distributor announcements."""

from datetime import date, datetime
from decimal import Decimal
import json
from pathlib import Path

from app.collectors.base import BaseSourceAdapter
from app.schemas.domain import (
    AccessMethod,
    AdapterResult,
    CollectionMetric,
    IndianLanguage,
    RawCollectionReportInput,
    ReportingPeriodType,
    ReportSourceStatus,
)


class ManualImportAdapter(BaseSourceAdapter):
    """Reads operator-verified JSON report files placed in manual_import_dir."""

    code = "manual_official_import"
    name = "Official Producer / Manual Import"
    access_method = AccessMethod.MANUAL_IMPORT
    priority = 5
    reliability_score = 0.98

    def __init__(self, import_dir: str = "./data/manual_imports") -> None:
        self.import_dir = Path(import_dir)

    def is_configured(self) -> bool:
        return self.import_dir.exists() and self.import_dir.is_dir()

    async def fetch_reports(self, target_date: date) -> AdapterResult:
        if not self.is_configured():
            return AdapterResult(
                source_code=self.code,
                success=False,
                error_message=f"Import directory does not exist: {self.import_dir}",
                health_status="MANUAL_ONLY",
            )

        reports: list[RawCollectionReportInput] = []
        for file_path in sorted(self.import_dir.glob("*.json")):
            payload = json.loads(file_path.read_text(encoding="utf-8"))
            items = payload if isinstance(payload, list) else payload.get("reports", [])
            for row in items:
                rep_date = date.fromisoformat(row["reporting_date"])
                if rep_date != target_date:
                    continue
                reports.append(
                    RawCollectionReportInput(
                        source_code=self.code,
                        movie_title=row["movie_title"],
                        tmdb_id=row.get("tmdb_id"),
                        language=IndianLanguage(row["language"]) if row.get("language") else None,
                        metric=CollectionMetric(row["metric"]),
                        period_type=ReportingPeriodType(row["period_type"]),
                        day_number=row.get("day_number"),
                        reporting_date=rep_date,
                        amount_inr_crores=Decimal(str(row["amount_inr_crores"])),
                        currency=row.get("currency", "INR"),
                        source_status=ReportSourceStatus(row["source_status"]),
                        source_url=row["source_url"],
                        original_report_ref=row.get("original_report_ref"),
                        published_at=datetime.fromisoformat(row["published_at"]) if row.get("published_at") else None,
                    )
                )

        return AdapterResult(
            source_code=self.code,
            success=True,
            reports=reports,
            health_status="HEALTHY",
        )
