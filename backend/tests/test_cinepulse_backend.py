"""Comprehensive Pytest suite for CinePulse India backend."""

from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
import json
from pathlib import Path
import tempfile

import httpx
import pytest

from app.collectors.base import BaseSourceAdapter, SourceRegistry
from app.collectors.sources.licensed_feed import LicensedFeedAdapter
from app.collectors.sources.manual_import import ManualImportAdapter
from app.collectors.sources.rss_feed import PermittedRssAdapter
from app.collectors.tmdb import TmdbClient
from app.collectors.wikidata import WikidataClient
from app.config.settings import Settings
from app.database.session import create_db_engine, get_session_factory, session_scope
from app.main import run_daily_pipeline
from app.models.entities import (
    Base,
    CollectionReport,
    CollectionRevision,
    Movie,
    PostDraft,
    ReconciledCollection,
    Source,
)
from app.post_generation.generator import generate_drafts_for_date
from app.post_generation.rankings import build_top_5_ranking
from app.reconciliation.engine import ingest_report, reconcile_bucket
from app.schemas.domain import (
    AccessMethod,
    AdapterResult,
    CollectionMetric,
    DraftCategory,
    DraftStatus,
    IndianLanguage,
    RawCollectionReportInput,
    ReportingPeriodType,
    ReportSourceStatus,
)
from app.services.draft_expiry import expire_stale_drafts
from app.validators.collection_validator import ValidationError, validate_collection_report
from app.validators.x_text_validator import count_x_weighted_chars, validate_x_post


@pytest.fixture()
def db_session():
    engine = create_db_engine("sqlite+pysqlite:///:memory:")
    Base.metadata.create_all(engine)
    factory = get_session_factory("sqlite+pysqlite:///:memory:")
    # Bind factory to the same in-memory engine
    factory.configure(bind=engine)
    with session_scope(factory) as session:
        yield session


def _seed_source(session, code: str, name: str, priority: int = 10, reliability: str = "0.900") -> Source:
    src = Source(
        code=code,
        name=name,
        access_method=AccessMethod.LICENSED_FEED.value,
        priority=priority,
        reliability_score=Decimal(reliability),
    )
    session.add(src)
    session.flush()
    return src


def test_x_weighted_character_validation():
    assert count_x_weighted_chars("Hello") == 5
    # URL always counts as 23 weighted chars regardless of actual length
    assert count_x_weighted_chars("Check https://example.com/very/long/path/here") == 6 + 23
    # Emoji counts as 2 weighted chars
    assert count_x_weighted_chars("🔥") == 2

    long_text = "A" * 281
    res = validate_x_post(long_text)
    assert res.is_valid is False
    assert res.weighted_length == 281
    assert res.remaining == -1
    assert len(res.suggestions) >= 1


def test_collection_validator_rejects_negative_and_pre_release():
    bad_amount = RawCollectionReportInput(
        source_code="s1",
        movie_title="Test Film",
        metric=CollectionMetric.INDIA_NET,
        period_type=ReportingPeriodType.DAILY,
        reporting_date=date(2026, 11, 20),
        amount_inr_crores=Decimal("10.0"),
        source_status=ReportSourceStatus.ESTIMATE,
        source_url="https://example.com/r1",
    )
    with pytest.raises(ValidationError):
        validate_collection_report(bad_amount, movie_release_date=date(2026, 11, 28))

    with pytest.raises(ValidationError):
        validate_collection_report(
            bad_amount.model_copy(update={"currency": "USD"}),
            movie_release_date=date(2026, 11, 20),
        )


def test_duplicate_and_revision_detection(db_session):
    src = _seed_source(db_session, "trade_a", "Trade A")
    report = RawCollectionReportInput(
        source_code="trade_a",
        movie_title="Kantara Chapter 1",
        language=IndianLanguage.KANNADA,
        metric=CollectionMetric.INDIA_NET,
        period_type=ReportingPeriodType.DAILY,
        day_number=1,
        reporting_date=date(2026, 11, 20),
        amount_inr_crores=Decimal("18.50"),
        source_status=ReportSourceStatus.ESTIMATE,
        source_url="https://example.com/k1",
    )

    first = ingest_report(db_session, src, report)
    assert first.is_duplicate is False
    assert first.revision_recorded is False

    # Exact duplicate
    dup = ingest_report(db_session, src, report)
    assert dup.is_duplicate is True
    assert dup.revision_recorded is False

    # Revised amount from same source
    revised_input = report.model_copy(
        update={
            "amount_inr_crores": Decimal("21.25"),
            "source_status": ReportSourceStatus.TRADE_REPORTED,
        }
    )
    rev = ingest_report(db_session, src, revised_input)
    assert rev.is_duplicate is False
    assert rev.revision_recorded is True
    revisions = db_session.query(CollectionRevision).all()
    assert len(revisions) == 1
    assert revisions[0].previous_amount == Decimal("18.5000")
    assert revisions[0].new_amount == Decimal("21.2500")


def test_conflict_detection_never_averages_and_keeps_metrics_separate(db_session):
    src_est = _seed_source(db_session, "est_src", "Estimate Tracker", priority=50, reliability="0.750")
    src_prod = _seed_source(db_session, "prod_src", "Producer Official", priority=5, reliability="0.980")

    r1 = RawCollectionReportInput(
        source_code="est_src",
        movie_title="Empuraan",
        language=IndianLanguage.MALAYALAM,
        metric=CollectionMetric.INDIA_NET,
        period_type=ReportingPeriodType.DAILY,
        day_number=1,
        reporting_date=date(2026, 11, 25),
        amount_inr_crores=Decimal("22.00"),
        source_status=ReportSourceStatus.ESTIMATE,
        source_url="https://example.com/est",
    )
    r2 = r1.model_copy(
        update={
            "source_code": "prod_src",
            "amount_inr_crores": Decimal("27.50"),
            "source_status": ReportSourceStatus.PRODUCER_REPORTED,
            "source_url": "https://example.com/prod",
        }
    )
    # Separate Worldwide Gross report must stay in its own bucket
    r3 = r2.model_copy(
        update={
            "metric": CollectionMetric.WORLDWIDE_GROSS,
            "amount_inr_crores": Decimal("62.00"),
        }
    )

    out1 = ingest_report(db_session, src_est, r1)
    ingest_report(db_session, src_prod, r2)
    ingest_report(db_session, src_prod, r3)

    movie_id = out1.saved_report.movie_id
    rec_net = reconcile_bucket(
        db_session, movie_id, CollectionMetric.INDIA_NET.value, ReportingPeriodType.DAILY.value, date(2026, 11, 25)
    )
    rec_ww = reconcile_bucket(
        db_session, movie_id, CollectionMetric.WORLDWIDE_GROSS.value, ReportingPeriodType.DAILY.value, date(2026, 11, 25)
    )

    assert rec_net is not None
    assert rec_net.has_conflict is True
    # Must select Producer Reported (27.50), NEVER average (24.75)
    assert rec_net.reconciled_amount_inr_crores == Decimal("27.5000")
    assert len(rec_net.conflict_details["competing_reports"]) == 2

    assert rec_ww is not None
    assert rec_ww.reconciled_amount_inr_crores == Decimal("62.0000")
    assert rec_ww.has_conflict is False


def test_top5_ranking_and_post_generation(db_session):
    src = _seed_source(db_session, "feed_a", "Feed A")
    rep_date = date(2026, 11, 26)
    samples = [
        ("Movie A", IndianLanguage.MALAYALAM, "12.50"),
        ("Movie B", IndianLanguage.MALAYALAM, "8.20"),
        ("Movie C", IndianLanguage.TAMIL, "19.00"),
        ("Movie D", IndianLanguage.HINDI, "24.10"),
    ]
    for title, lang, amt in samples:
        raw = RawCollectionReportInput(
            source_code="feed_a",
            movie_title=title,
            language=lang,
            metric=CollectionMetric.INDIA_NET,
            period_type=ReportingPeriodType.DAILY,
            day_number=2,
            reporting_date=rep_date,
            amount_inr_crores=Decimal(amt),
            source_status=ReportSourceStatus.TRADE_REPORTED,
            source_url=f"https://example.com/{title.replace(' ', '_')}",
        )
        out = ingest_report(db_session, src, raw)
        reconcile_bucket(
            db_session,
            out.saved_report.movie_id,
            CollectionMetric.INDIA_NET.value,
            ReportingPeriodType.DAILY.value,
            rep_date,
        )

    ranking = build_top_5_ranking(
        db_session,
        category=DraftCategory.TOP_5_INDIA,
        reporting_date=rep_date,
        metric=CollectionMetric.INDIA_NET,
        period_type=ReportingPeriodType.DAILY,
    )
    assert ranking is not None
    assert ranking.is_partial is True
    assert len(ranking.entries) == 4
    assert ranking.entries[0].title == "Movie D"

    drafts = generate_drafts_for_date(db_session, rep_date)
    categories = {d.category for d in drafts}
    assert DraftCategory.MOVIE_WISE.value in categories
    assert DraftCategory.TOP_5_INDIA.value in categories
    assert DraftCategory.MALAYALAM_TOP_5.value in categories
    assert all(d.status == DraftStatus.PENDING_REVIEW.value for d in drafts)


def test_draft_expiry_preserves_published_failed_and_publishing(db_session):
    now = datetime(2026, 11, 26, 12, 0, tzinfo=timezone.utc)
    past = now - timedelta(hours=1)
    future = now + timedelta(hours=24)

    statuses = [
        (DraftStatus.PENDING_REVIEW.value, past, DraftStatus.EXPIRED.value),
        (DraftStatus.EDITED.value, past, DraftStatus.EXPIRED.value),
        (DraftStatus.PUBLISHED.value, past, DraftStatus.PUBLISHED.value),
        (DraftStatus.FAILED.value, past, DraftStatus.FAILED.value),
        (DraftStatus.PUBLISHING.value, past, DraftStatus.PUBLISHING.value),
        (DraftStatus.PENDING_REVIEW.value, future, DraftStatus.PENDING_REVIEW.value),
    ]
    created_ids = []
    for initial, exp, _ in statuses:
        d = PostDraft(
            category=DraftCategory.MOVIE_WISE.value,
            title=f"Draft {initial}",
            reporting_date=date(2026, 11, 24),
            generated_text="Test post",
            source_summary="1 source",
            weighted_char_count=9,
            is_valid_length=True,
            status=initial,
            expires_at=exp,
        )
        db_session.add(d)
        db_session.flush()
        created_ids.append(d.id)

    expired_count = expire_stale_drafts(db_session, now=now)
    assert expired_count == 2
    # Idempotent second run
    assert expire_stale_drafts(db_session, now=now) == 0

    for did, (_, _, expected) in zip(created_ids, statuses, strict=True):
        row = db_session.get(PostDraft, did)
        assert row.status == expected


class _FailingAdapter(BaseSourceAdapter):
    code = "failing_source"
    name = "Failing Source"
    access_method = AccessMethod.AUTHORIZED_API

    def is_configured(self) -> bool:
        return True

    async def fetch_reports(self, target_date: date) -> AdapterResult:
        raise RuntimeError("Simulated upstream 503")


@pytest.mark.asyncio
async def test_partial_source_failure_and_full_pipeline():
    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_path = Path(tmpdir)
        manual_file = tmp_path / "official.json"
        manual_file.write_text(
            json.dumps(
                [
                    {
                        "movie_title": "Pushpa 2",
                        "language": "Telugu",
                        "metric": "WORLDWIDE_GROSS",
                        "period_type": "CUMULATIVE",
                        "day_number": 5,
                        "reporting_date": "2026-11-26",
                        "amount_inr_crores": "512.40",
                        "source_status": "PRODUCER_REPORTED",
                        "source_url": "https://example.com/pushpa2",
                    }
                ]
            ),
            encoding="utf-8",
        )
        db_file = tmp_path / "test_pipeline.db"
        cfg = Settings(
            database_url=f"sqlite+pysqlite:///{db_file.as_posix()}",
            manual_import_dir=str(tmp_path),
        )
        reg = SourceRegistry([_FailingAdapter(), ManualImportAdapter(str(tmp_path))])

        tmdb_transport = httpx.MockTransport(
            lambda req: httpx.Response(
                200,
                json={
                    "results": [
                        {
                            "id": 99001,
                            "title": "Pushpa 2",
                            "original_language": "te",
                            "release_date": "2026-11-22",
                            "poster_path": "/p2.jpg",
                        }
                    ]
                },
            )
        )
        tmdb = TmdbClient(api_key="test-key", transport=tmdb_transport)

        summary = await run_daily_pipeline(
            target_date=date(2026, 11, 26),
            trigger_type="MANUAL",
            settings=cfg,
            registry=reg,
            tmdb_client=tmdb,
            wikidata_client=WikidataClient(
                transport=httpx.MockTransport(
                    lambda req: httpx.Response(200, json={"results": {"bindings": []}})
                )
            ),
        )

        assert summary["status"] == "PARTIAL_SUCCESS"
        assert summary["movies_discovered"] == 1
        assert summary["reports_collected"] == 1
        assert summary["drafts_generated"] >= 2  # MOVIE_WISE + MILESTONES (>=500 Cr)


@pytest.mark.asyncio
async def test_github_json_export_sanitized():
    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_path = Path(tmpdir)
        export_dir = tmp_path / "export"
        db_file = tmp_path / "export_test.db"
        cfg = Settings(
            database_url=f"sqlite+pysqlite:///{db_file.as_posix()}",
            tmdb_api_key="super-secret-should-never-appear",
        )
        reg = SourceRegistry([])
        empty_wiki = WikidataClient(
            transport=httpx.MockTransport(
                lambda req: httpx.Response(200, json={"results": {"bindings": []}})
            )
        )
        summary = await run_daily_pipeline(
            target_date=date(2026, 11, 26),
            trigger_type="MANUAL",
            settings=cfg,
            registry=reg,
            wikidata_client=empty_wiki,
            export_dir=str(export_dir),
        )
        assert summary["exported"] is not None
        for fname in [
            "movies.json",
            "sources.json",
            "reports.json",
            "reconciled.json",
            "drafts.json",
            "runs.json",
            "manifest.json",
        ]:
            fpath = export_dir / fname
            assert fpath.exists()
            assert "super-secret-should-never-appear" not in fpath.read_text(encoding="utf-8")


@pytest.mark.asyncio
async def test_licensed_and_rss_adapters_with_mock_transport():
    api_transport = httpx.MockTransport(
        lambda req: httpx.Response(
            200,
            json={
                "reports": [
                    {
                        "movie_title": "Drishyam 3",
                        "language": "Malayalam",
                        "metric": "INDIA_NET",
                        "period_type": "DAILY",
                        "day_number": 1,
                        "reporting_date": "2026-11-26",
                        "amount_inr_crores": "9.45",
                        "source_status": "TRADE_REPORTED",
                        "source_url": "https://api.example.com/r/1",
                    }
                ]
            },
        )
    )
    api_adapter = LicensedFeedAdapter(
        base_url="https://api.example.com",
        api_key="secret",
        transport=api_transport,
    )
    api_res = await api_adapter.fetch_reports(date(2026, 11, 26))
    assert api_res.success is True
    assert len(api_res.reports) == 1

    rss_xml = """<?xml version="1.0"?>
    <rss><channel><item>
        <title>Drishyam 3 - India Net Daily: ₹9.50 Cr</title>
        <link>https://rss.example.com/item1</link>
    </item></channel></rss>"""
    rss_transport = httpx.MockTransport(lambda req: httpx.Response(200, text=rss_xml))
    rss_adapter = PermittedRssAdapter(
        feed_urls=["https://rss.example.com/feed.xml"],
        transport=rss_transport,
    )
    rss_res = await rss_adapter.fetch_reports(date(2026, 11, 26))
    assert rss_res.success is True
    assert len(rss_res.reports) == 1
    assert rss_res.reports[0].amount_inr_crores == Decimal("9.5000")
