"""Permitted RSS feed adapter for authorized entertainment trade feeds."""

from datetime import date
from decimal import Decimal
import re
import xml.etree.ElementTree as ET

import httpx

from app.collectors.base import BaseSourceAdapter
from app.schemas.domain import (
    AccessMethod,
    AdapterResult,
    CollectionMetric,
    RawCollectionReportInput,
    ReportingPeriodType,
    ReportSourceStatus,
)

# Conservative structured pattern for RSS items explicitly tagged with metric + ₹ Cr
_RSS_COLLECTION_RE = re.compile(
    r"(?P<title>.+?)\s*[-|:]\s*(?P<metric>India Net|India Gross|Overseas Gross|Worldwide Gross)\s*"
    r"(?P<period>Daily|Cumulative)\s*:\s*₹\s*(?P<amount>\d+(?:\.\d+)?)\s*Cr",
    re.IGNORECASE,
)

_METRIC_MAP = {
    "india net": CollectionMetric.INDIA_NET,
    "india gross": CollectionMetric.INDIA_GROSS,
    "overseas gross": CollectionMetric.OVERSEAS_GROSS,
    "worldwide gross": CollectionMetric.WORLDWIDE_GROSS,
}


class PermittedRssAdapter(BaseSourceAdapter):
    """Parses permitted RSS feeds without scraping HTML pages."""

    code = "permitted_trade_rss"
    name = "Permitted Trade RSS"
    access_method = AccessMethod.PERMITTED_RSS
    priority = 30
    reliability_score = 0.85

    def __init__(
        self,
        feed_urls: list[str] | None = None,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self.feed_urls = [u.strip() for u in (feed_urls or []) if u.strip()]
        self.transport = transport

    def is_configured(self) -> bool:
        return len(self.feed_urls) > 0

    async def fetch_reports(self, target_date: date) -> AdapterResult:
        if not self.is_configured():
            return AdapterResult(
                source_code=self.code,
                success=False,
                error_message="No permitted RSS feed URLs configured.",
                health_status="UNAVAILABLE",
            )

        reports: list[RawCollectionReportInput] = []
        async with httpx.AsyncClient(timeout=20.0, transport=self.transport) as client:
            for url in self.feed_urls:
                resp = await client.get(url)
                resp.raise_for_status()
                root = ET.fromstring(resp.text)
                for item in root.findall(".//item"):
                    title_text = (item.findtext("title") or "").strip()
                    link_text = (item.findtext("link") or url).strip()
                    match = _RSS_COLLECTION_RE.search(title_text)
                    if not match:
                        continue
                    metric = _METRIC_MAP[match.group("metric").lower()]
                    period = (
                        ReportingPeriodType.DAILY
                        if match.group("period").lower() == "daily"
                        else ReportingPeriodType.CUMULATIVE
                    )
                    reports.append(
                        RawCollectionReportInput(
                            source_code=self.code,
                            movie_title=match.group("title").strip(),
                            metric=metric,
                            period_type=period,
                            reporting_date=target_date,
                            amount_inr_crores=Decimal(match.group("amount")),
                            source_status=ReportSourceStatus.TRADE_REPORTED,
                            source_url=link_text,
                            original_report_ref=title_text,
                        )
                    )

        return AdapterResult(
            source_code=self.code,
            success=True,
            reports=reports,
            health_status="HEALTHY",
        )
