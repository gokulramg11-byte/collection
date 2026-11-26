"""CinePulse India daily collection and draft-generation pipeline.

CRITICAL: This module NEVER publishes to X. Publishing is strictly manual
from the Flutter Android app via official X OAuth 2.0 PKCE.
"""

import argparse
import asyncio
from datetime import date, datetime, timezone
import logging

from sqlalchemy import select

from app.collectors.base import SourceRegistry
from app.collectors.sources.licensed_feed import LicensedFeedAdapter
from app.collectors.sources.manual_import import ManualImportAdapter
from app.collectors.sources.rss_feed import PermittedRssAdapter
from app.collectors.tmdb import TmdbClient
from app.collectors.wikidata import WikidataClient
from app.config.settings import Settings, get_settings
from app.database.session import create_db_engine, get_session_factory, session_scope
from app.export.github_json_exporter import export_github_json
from app.models.entities import Base, CollectionRun, Source
from app.post_generation.generator import generate_drafts_for_date
from app.reconciliation.engine import ingest_report, reconcile_bucket
from app.services.draft_expiry import expire_stale_drafts
from app.services.movie_matcher import upsert_movie_from_metadata
from app.validators.collection_validator import ValidationError

logger = logging.getLogger(__name__)


def build_default_registry(settings: Settings) -> SourceRegistry:
    """Build the authorized source adapter registry from settings."""
    rss_urls = [u.strip() for u in settings.permitted_rss_urls.split(",") if u.strip()]
    registry = SourceRegistry()
    registry.register(ManualImportAdapter(import_dir=settings.manual_import_dir))
    registry.register(
        LicensedFeedAdapter(
            base_url=settings.licensed_feed_base_url,
            api_key=settings.licensed_feed_api_key,
        )
    )
    registry.register(PermittedRssAdapter(feed_urls=rss_urls))
    return registry


async def run_daily_pipeline(
    target_date: date | None = None,
    trigger_type: str = "SCHEDULED",
    settings: Settings | None = None,
    registry: SourceRegistry | None = None,
    tmdb_client: TmdbClient | None = None,
    wikidata_client: WikidataClient | None = None,
    export_dir: str | None = None,
) -> dict:
    """Execute the full collection, reconciliation, draft-generation, and expiry pipeline."""
    cfg = settings or get_settings()
    run_date = target_date or datetime.now(timezone.utc).date()
    reg = registry or build_default_registry(cfg)
    tmdb = tmdb_client or TmdbClient(
        api_key=cfg.tmdb_api_key,
        read_access_token=cfg.tmdb_read_access_token,
    )
    wikidata = wikidata_client or WikidataClient()

    engine = create_db_engine(cfg.database_url)
    Base.metadata.create_all(engine)
    factory = get_session_factory(cfg.database_url)

    # 1. Discover newly released Indian movies (TMDB primary, Wikidata open-data fallback)
    discovered_movies = []
    if tmdb.is_configured():
        try:
            discovered_movies = await tmdb.discover_indian_releases(reference_date=run_date)
        except Exception as exc:  # noqa: BLE001
            logger.warning("TMDB discovery failed: %s", exc)

    if not discovered_movies:
        try:
            discovered_movies = await wikidata.discover_indian_releases(reference_date=run_date)
        except Exception as exc:  # noqa: BLE001
            logger.warning("Wikidata discovery fallback failed: %s", exc)

    # 2. Run authorized source adapters with fault isolation
    adapter_results = await reg.collect_all(run_date)

    with session_scope(factory) as session:
        run = CollectionRun(trigger_type=trigger_type, status="RUNNING")
        session.add(run)
        session.flush()

        for meta in discovered_movies:
            upsert_movie_from_metadata(session, meta)
        run.movies_discovered = len(discovered_movies)

        # Ensure source registry rows exist
        sources_by_code: dict[str, Source] = {}
        for adapter in reg.adapters:
            src = session.scalar(select(Source).where(Source.code == adapter.code))
            if src is None:
                src = Source(
                    code=adapter.code,
                    name=adapter.name,
                    access_method=adapter.access_method.value,
                    base_url=adapter.base_url,
                    priority=adapter.priority,
                    reliability_score=adapter.reliability_score,
                )
                session.add(src)
                session.flush()
            sources_by_code[adapter.code] = src

        buckets_to_reconcile: set[tuple] = set()
        source_summary: dict[str, dict] = {}
        reports_saved = 0

        for res in adapter_results:
            src = sources_by_code.get(res.source_code)
            if src is not None:
                src.health_status = res.health_status
                src.last_error = res.error_message
                if res.success:
                    src.last_success_at = datetime.now(timezone.utc)

            source_summary[res.source_code] = {
                "success": res.success,
                "health_status": res.health_status,
                "report_count": len(res.reports),
                "error": res.error_message,
            }
            if not res.success or src is None:
                continue

            for raw in res.reports:
                try:
                    outcome = ingest_report(session, src, raw)
                except ValidationError as exc:
                    logger.warning("Rejected invalid report from %s: %s", res.source_code, exc)
                    continue
                if outcome.saved_report is not None and not outcome.is_duplicate:
                    reports_saved += 1
                    buckets_to_reconcile.add(
                        (
                            outcome.saved_report.movie_id,
                            outcome.saved_report.metric,
                            outcome.saved_report.period_type,
                            outcome.saved_report.reporting_date,
                        )
                    )

        conflicts = 0
        for movie_id, metric, period_type, rep_date in buckets_to_reconcile:
            rec = reconcile_bucket(
                session,
                movie_id=movie_id,
                metric=metric,
                period_type=period_type,
                reporting_date=rep_date,
                conflict_threshold_pct=cfg.conflict_threshold_pct,
            )
            if rec is not None and rec.has_conflict:
                conflicts += 1

        drafts = generate_drafts_for_date(session, run_date, expiry_hours=cfg.draft_expiry_hours)
        expired = expire_stale_drafts(session)

        any_success = any(r.success for r in adapter_results)
        all_success = all(r.success for r in adapter_results) if adapter_results else True
        run.status = "SUCCESS" if all_success else ("PARTIAL_SUCCESS" if any_success else "FAILED")
        run.completed_at = datetime.now(timezone.utc)
        run.reports_collected = reports_saved
        run.conflicts_detected = conflicts
        run.drafts_generated = len(drafts)
        run.drafts_expired = expired
        run.source_results = source_summary

        export_counts = None
        if export_dir:
            export_counts = export_github_json(session, export_dir)

        return {
            "run_id": str(run.id),
            "status": run.status,
            "movies_discovered": run.movies_discovered,
            "reports_collected": run.reports_collected,
            "conflicts_detected": run.conflicts_detected,
            "drafts_generated": run.drafts_generated,
            "drafts_expired": run.drafts_expired,
            "exported": export_counts,
        }


def main() -> None:
    parser = argparse.ArgumentParser(description="CinePulse India Daily Collection & Draft Pipeline")
    parser.add_argument("--date", type=str, default=None, help="Target reporting date (YYYY-MM-DD)")
    parser.add_argument("--trigger", type=str, default="MANUAL", choices=["SCHEDULED", "MANUAL"])
    parser.add_argument("--export-dir", type=str, default=None, help="Optional directory to export sanitized JSON")
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    target = date.fromisoformat(args.date) if args.date else None
    result = asyncio.run(
        run_daily_pipeline(
            target_date=target,
            trigger_type=args.trigger,
            export_dir=args.export_dir,
        )
    )
    logger.info("Pipeline completed: %s", result)


if __name__ == "__main__":
    main()
