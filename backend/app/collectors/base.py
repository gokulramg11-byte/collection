"""Base interface and registry for authorized box-office source adapters."""

from abc import ABC, abstractmethod
from datetime import date
import logging

from app.schemas.domain import AccessMethod, AdapterResult

logger = logging.getLogger(__name__)


class BaseSourceAdapter(ABC):
    """Abstract base class for all authorized box-office data sources."""

    code: str
    name: str
    access_method: AccessMethod
    base_url: str | None = None
    priority: int = 100
    reliability_score: float = 0.80

    @abstractmethod
    def is_configured(self) -> bool:
        """Return True when required credentials or paths are configured."""

    @abstractmethod
    async def fetch_reports(self, target_date: date) -> AdapterResult:
        """Fetch and parse box-office reports for target_date."""


class SourceRegistry:
    """Runs enabled source adapters with fault isolation."""

    def __init__(self, adapters: list[BaseSourceAdapter] | None = None) -> None:
        self._adapters: list[BaseSourceAdapter] = adapters or []

    def register(self, adapter: BaseSourceAdapter) -> None:
        self._adapters.append(adapter)

    @property
    def adapters(self) -> list[BaseSourceAdapter]:
        return list(self._adapters)

    async def collect_all(self, target_date: date) -> list[AdapterResult]:
        """Execute each adapter independently; a failure in one never stops others."""
        results: list[AdapterResult] = []
        for adapter in self._adapters:
            if not adapter.is_configured():
                results.append(
                    AdapterResult(
                        source_code=adapter.code,
                        success=False,
                        reports=[],
                        error_message="Source not configured or disabled.",
                        health_status="UNAVAILABLE",
                    )
                )
                continue

            try:
                result = await adapter.fetch_reports(target_date)
                results.append(result)
            except Exception as exc:  # noqa: BLE001 - isolate adapter failure
                logger.exception("Adapter %s failed for %s", adapter.code, target_date)
                results.append(
                    AdapterResult(
                        source_code=adapter.code,
                        success=False,
                        reports=[],
                        error_message=str(exc),
                        health_status="UNAVAILABLE",
                    )
                )
        return results
