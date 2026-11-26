# Manual Official Box-Office Imports

Place verified `.json` report files here (e.g., official producer/distributor announcements or verified trade figures) to feed the collection, reconciliation, and draft-generation pipeline without scraping.

## JSON Format Example (`2026-11-27.json`)

```json
[
  {
    "movie_title": "Movie Title",
    "language": "Malayalam",
    "metric": "INDIA_NET",
    "period_type": "DAILY",
    "day_number": 1,
    "reporting_date": "2026-11-27",
    "amount_inr_crores": "12.40",
    "source_status": "PRODUCER_REPORTED",
    "source_url": "https://x.com/official_handle/status/1234567890",
    "original_report_ref": "Official Day 1 poster"
  }
]
```

### Supported Values
- `metric`: `INDIA_NET`, `INDIA_GROSS`, `OVERSEAS_GROSS`, `WORLDWIDE_GROSS`
- `period_type`: `DAILY`, `CUMULATIVE`
- `source_status`: `ESTIMATE`, `UPDATED_ESTIMATE`, `TRADE_REPORTED`, `PRODUCER_REPORTED`, `REPORTED_FINAL`, `AUDITED`
