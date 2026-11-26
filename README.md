# CinePulse India

A production-oriented Indian box-office tracking and manual X publishing platform covering Malayalam, Tamil, Telugu, Kannada, Hindi, Bengali, Marathi, Punjabi, Gujarati, and other Indian-language cinema.

## Core Architecture & Guarantees

- **Strict Data Integrity:** `INDIA_NET`, `INDIA_GROSS`, `OVERSEAS_GROSS`, and `WORLDWIDE_GROSS` are never mixed or averaged. Every figure preserves its source, URL, status (`ESTIMATE`, `UPDATED_ESTIMATE`, `TRADE_REPORTED`, `PRODUCER_REPORTED`, `REPORTED_FINAL`, `AUDITED`), and revision history.
- **Zero Auto-Publishing:** GitHub Actions and the Python backend **only** collect authorized reports, reconcile compatible metrics, and generate `PENDING_REVIEW` drafts. Publishing to X happens **only** when an authenticated operator explicitly reviews and taps **Publish to X** inside the Flutter Android app.
- **Official X OAuth 2.0 PKCE:** Native public-client PKCE flow (`tweet.write`, `users.read`, `offline.access`). X tokens are stored exclusively in Android Keystore-backed `flutter_secure_storage`—never in Supabase or GitHub Actions.
- **TMDB Attribution:** TMDB is used strictly for movie metadata and posters, never as an authoritative box-office collection source.

## Repository Layout

```text
cinepulse_india/
├── backend/                  # Python 3.12+ collector, reconciliation & draft pipeline
├── mobile/                   # Flutter Android app (Material 3, Riverpod, GoRouter, Supabase)
├── database/migrations/      # Supabase PostgreSQL schema, RLS policies & 48h draft expiry
├── .github/workflows/        # Daily 08:30 IST (03:00 UTC) collection & CI workflows
├── docs/                     # Stitch design index & phase progress log
├── DESIGN.md                 # Stitch-derived Dark Cinema × Fintech design system
└── README.md
```

## Setup & Deployment

### 1. Supabase Database
Run the migrations in order in your Supabase SQL Editor (or `supabase db push`):
1. `database/migrations/001_initial_schema.sql`
2. `database/migrations/002_rls_and_expiry.sql`

### 2. Python Backend & Daily Pipeline
```bash
cd backend
cp .env.example .env   # Fill SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, DATABASE_URL, TMDB_API_KEY
pip install -r requirements.txt
pytest -v
python -m app.main --trigger MANUAL
```

### 3. GitHub Actions Automation
Add the following Repository Secrets in GitHub:
- `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `DATABASE_URL`
- `TMDB_API_KEY`, `TMDB_READ_ACCESS_TOKEN`
- Optional authorized feeds: `LICENSED_FEED_API_KEY`, `LICENSED_FEED_BASE_URL`, `PERMITTED_RSS_URLS`

The scheduled workflow `.github/workflows/daily_collection.yml` runs daily at `03:00 UTC` (`08:30 IST`) and supports manual `workflow_dispatch`.

### 4. Flutter Android App
```bash
cd mobile
cp .env.example .env   # Fill SUPABASE_URL, SUPABASE_ANON_KEY, X_CLIENT_ID
flutter pub get
flutter analyze
flutter test
flutter build apk --release --dart-define-from-file=.env
```
