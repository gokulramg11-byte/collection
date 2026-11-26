"""Permitted RSS feed adapter for Google News RSS and authorized trade RSS feeds."""

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
    IndianLanguage,
    RawCollectionReportInput,
    ReportingPeriodType,
    ReportSourceStatus,
)

DEFAULT_INDIA_RSS_URLS: list[str] = [
    "https://news.google.com/rss/search?q=%22box+office+collection%22+day&hl=en-IN&gl=IN&ceid=IN:en",
    "https://news.google.com/rss/search?q=%22malayalam+box+office%22+collection&hl=en-IN&gl=IN&ceid=IN:en",
    "https://news.google.com/rss/search?q=%22tamil+box+office%22+collection&hl=en-IN&gl=IN&ceid=IN:en",
    "https://news.google.com/rss/search?q=%22telugu+box+office%22+collection&hl=en-IN&gl=IN&ceid=IN:en",
    "https://news.google.com/rss/search?q=%22kannada+box+office%22+collection&hl=en-IN&gl=IN&ceid=IN:en",
    "https://news.google.com/rss/search?q=%22hindi+box+office%22+collection&hl=en-IN&gl=IN&ceid=IN:en",
]

# 1. Strict structured pattern: "Movie - India Net Daily: ₹12.50 Cr"
_RSS_STRUCTURED_RE = re.compile(
    r"(?P<title>.+?)\s*[-|:]\s*(?P<metric>India Net|India Gross|Overseas Gross|Worldwide Gross)\s*"
    r"(?P<period>Daily|Cumulative)\s*:\s*₹\s*(?P<amount>\d+(?:\.\d+)?)\s*Cr",
    re.IGNORECASE,
)

# 2. Natural-language headline pattern: "₹45.20 Cr" or "Rs. 45.20 Crore"
_AMOUNT_CR_RE = re.compile(
    r"(?:₹|Rs\.?)\s*(?P<amount>\d+(?:,\d+)*(?:\.\d+)?)\s*(?:Cr|Crore|Crores)\b",
    re.IGNORECASE,
)
_DAY_NUM_RE = re.compile(r"\bDay\s*(\d{1,3})\b", re.IGNORECASE)
_TITLE_SPLIT_RE = re.compile(
    r"\s+(?:Box\s+Office|Worldwide\s+Box\s+Office|India\s+Box\s+Office|Collection|Day\s+\d+)\b",
    re.IGNORECASE,
)

_METRIC_MAP = {
    "india net": CollectionMetric.INDIA_NET,
    "india gross": CollectionMetric.INDIA_GROSS,
    "overseas gross": CollectionMetric.OVERSEAS_GROSS,
    "worldwide gross": CollectionMetric.WORLDWIDE_GROSS,
}

_LANGUAGE_KEYWORDS: dict[str, IndianLanguage] = {
    "malayalam": IndianLanguage.MALAYALAM,
    "mollywood": IndianLanguage.MALAYALAM,
    "tamil": IndianLanguage.TAMIL,
    "kollywood": IndianLanguage.TAMIL,
    "telugu": IndianLanguage.TELUGU,
    "tollywood": IndianLanguage.TELUGU,
    "kannada": IndianLanguage.KANNADA,
    "sandalwood": IndianLanguage.KANNADA,
    "hindi": IndianLanguage.HINDI,
    "bollywood": IndianLanguage.HINDI,
    "bengali": IndianLanguage.BENGALI,
    "marathi": IndianLanguage.MARATHI,
    "punjabi": IndianLanguage.PUNJABI,
    "gujarati": IndianLanguage.GUJARATI,
}


def _infer_language(text: str, feed_url: str) -> IndianLanguage | None:
    combined = f"{text} {feed_url}".lower()
    for kw, lang in _LANGUAGE_KEYWORDS.items():
        if kw in combined:
            return lang
    return None


def parse_rss_headline(
    headline: str,
    link: str,
    target_date: date,
    feed_url: str,
    source_code: str = "permitted_trade_rss",
) -> RawCollectionReportInput | None:
    """Parse an RSS headline into a strict RawCollectionReportInput if explicit."""
    clean = headline.strip()
    if not clean:
        return None

    # Check strict structured format first
    structured = _RSS_STRUCTURED_RE.search(clean)
    if structured:
        metric = _METRIC_MAP[structured.group("metric").lower()]
        period = (
            ReportingPeriodType.DAILY
            if structured.group("period").lower() == "daily"
            else ReportingPeriodType.CUMULATIVE
        )
        return RawCollectionReportInput(
            source_code=source_code,
            movie_title=structured.group("title").strip(),
            language=_infer_language(clean, feed_url),
            metric=metric,
            period_type=period,
            reporting_date=target_date,
            amount_inr_crores=Decimal(structured.group("amount")),
            source_status=ReportSourceStatus.TRADE_REPORTED,
            source_url=link,
            original_report_ref=clean,
        )

    # Natural-language headline must explicitly mention box office/collection AND a ₹/Rs Cr amount
    lower = clean.lower()
    if "box office" not in lower and "collection" not in lower:
        return None

    amt_match = _AMOUNT_CR_RE.search(clean)
    if not amt_match:
        return None

    amount_str = amt_match.group("amount").replace(",", "")
    try:
        amount = Decimal(amount_str)
    except Exception:  # noqa: BLE001
        return None

    # Strip trailing " - Publisher" from Google News titles before extracting movie title
    title_part = re.sub(r"\s+-\s+[^-]+$", "", clean).strip()
    split_match = _TITLE_SPLIT_RE.search(title_part)
    if not split_match or split_match.start() < 2:
        return None

    movie_title = title_part[: split_match.start()].strip(" :-|")
    if len(movie_title) < 2 or len(movie_title) > 100:
        return None

    if "worldwide" in lower or "global" in lower:
        metric = CollectionMetric.WORLDWIDE_GROSS
    elif "overseas" in lower:
        metric = CollectionMetric.OVERSEAS_GROSS
    elif "india gross" in lower or ("gross" in lower and "net" not in lower):
        metric = CollectionMetric.INDIA_GROSS
    else:
        metric = CollectionMetric.INDIA_NET

    day_match = _DAY_NUM_RE.search(clean)
    day_num = int(day_match.group(1)) if day_match else None
    cumulative_markers = ("total", "crosses", "cumulative", "hits", "overall", "lifetime")
    if any(m in lower for m in cumulative_markers):
        period = ReportingPeriodType.CUMULATIVE
    elif "opening day" in lower or day_num is not None:
        period = ReportingPeriodType.DAILY
        if "opening day" in lower and day_num is None:
            day_num = 1
    else:
        period = ReportingPeriodType.DAILY

    return RawCollectionReportInput(
        source_code=source_code,
        movie_title=movie_title,
        language=_infer_language(clean, feed_url),
        metric=metric,
        period_type=period,
        day_number=day_num,
        reporting_date=target_date,
        amount_inr_crores=amount,
        source_status=ReportSourceStatus.ESTIMATE,
        source_url=link,
        original_report_ref=clean,
    )


class PermittedRssAdapter(BaseSourceAdapter):
    """Parses Google News RSS and permitted trade RSS feeds without HTML scraping."""

    code = "permitted_trade_rss"
    name = "Google News & Permitted Trade RSS"
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
        headers = {
            "User-Agent": "CinePulseIndia/1.0 (+https://github.com/gokulramg11-byte/collection)",
            "Accept": "application/rss+xml, application/xml, text/xml",
        }
        async with httpx.AsyncClient(
            headers=headers,
            timeout=20.0,
            follow_redirects=True,
            transport=self.transport,
        ) as client:
            for url in self.feed_urls:
                resp = await client.get(url)
                resp.raise_for_status()
                root = ET.fromstring(resp.text)
                for item in root.findall(".//item"):
                    title_text = (item.findtext("title") or "").strip()
                    link_text = (item.findtext("link") or url).strip()
                    parsed = parse_rss_headline(
                        headline=title_text,
                        link=link_text,
                        target_date=target_date,
                        feed_url=url,
                        source_code=self.code,
                    )
                    if parsed is not None:
                        reports.append(parsed)

        return AdapterResult(
            source_code=self.code,
            success=True,
            reports=reports,
            health_status="HEALTHY",
        )
