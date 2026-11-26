"""Authorized licensed box-office API feed adapter."""

from datetime import date, datetime
from decimal import Decimal
import httpx

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


class LicensedFeedAdapter(BaseSourceAdapter):
    """Fetches structured box-office reports from an authorized JSON API."""

    code = "licensed_boxoffice_api"
    name = "Licensed Box-Office Feed"
    access_method = AccessMethod.LICENSED_FEED
    priority = 10
    reliability_score = 0.95

    def __init__(
        self,
        base_url: str = "",
        api_key: str = "",
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key
        self.transport = transport

    def is_configured(self) -> bool:
        return bool(self.base_url and self.api_key)

    async def fetch_reports(self, target_date: date) -> AdapterResult:
        if not self.is_configured():
            return AdapterResult(
                source_code=self.code,
                success=False,
                error_message="Licensed feed URL or API key missing.",
                health_status="UNAVAILABLE",
            )

        headers = {"Authorization": f"Bearer {self.api_key}", "Accept": "application/json"}
        async with httpx.AsyncClient(
            base_url=self.base_url,
            headers=headers,
            timeout=20.0,
            transport=self.transport,
        ) as client:
            resp = await client.get("/v1/collections", params={"date": target_date.isoformat()})
            resp.raise_for_status()
            data = resp.json()

        reports: list[RawCollectionReportInput] = []
        for row in data.get("reports", []):
            reports.append(
                RawCollectionReportInput(
                    source_code=self.code,
                    movie_title=row["movie_title"],
                    tmdb_id=row.get("tmdb_id"),
                    language=IndianLanguage(row["language"]) if row.get("language") else None,
                    metric=CollectionMetric(row["metric"]),
                    period_type=ReportingPeriodType(row["period_type"]),
                    day_number=row.get("day_number"),
                    reporting_date=date.fromisoformat(row["reporting_date"]),
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
