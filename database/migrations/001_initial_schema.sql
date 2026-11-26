-- CinePulse India — Initial PostgreSQL / Supabase Schema
-- All timestamps are stored in UTC (timestamptz) and rendered in Asia/Kolkata (IST) in the UI.

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. Supported Enums
DO $$ BEGIN
    CREATE TYPE collection_metric AS ENUM (
        'INDIA_NET',
        'INDIA_GROSS',
        'OVERSEAS_GROSS',
        'WORLDWIDE_GROSS'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE reporting_period_type AS ENUM (
        'DAILY',
        'CUMULATIVE'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE report_source_status AS ENUM (
        'ESTIMATE',
        'UPDATED_ESTIMATE',
        'TRADE_REPORTED',
        'PRODUCER_REPORTED',
        'REPORTED_FINAL',
        'AUDITED'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE draft_status AS ENUM (
        'PENDING_REVIEW',
        'EDITED',
        'PUBLISHING',
        'PUBLISHED',
        'FAILED',
        'EXPIRED',
        'CANCELLED'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE draft_category AS ENUM (
        'MOVIE_WISE',
        'TOP_5_INDIA',
        'TOP_5_WORLDWIDE',
        'MALAYALAM_TOP_5',
        'TAMIL_TOP_5',
        'TELUGU_TOP_5',
        'KANNADA_TOP_5',
        'HINDI_TOP_5',
        'BENGALI_TOP_5',
        'MARATHI_TOP_5',
        'OPENING_DAY',
        'MILESTONES',
        'LATEST_UPDATES'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 2. Movies
CREATE TABLE IF NOT EXISTS public.movies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tmdb_id BIGINT UNIQUE,
    title TEXT NOT NULL,
    original_title TEXT,
    primary_language TEXT NOT NULL,
    languages TEXT[] NOT NULL DEFAULT '{}',
    release_date DATE,
    poster_path TEXT,
    production_companies JSONB NOT NULL DEFAULT '[]'::jsonb,
    overview TEXT,
    is_monitored BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_movies_language ON public.movies (primary_language);
CREATE INDEX IF NOT EXISTS idx_movies_release_date ON public.movies (release_date DESC);
CREATE INDEX IF NOT EXISTS idx_movies_monitored ON public.movies (is_monitored) WHERE is_monitored = TRUE;

-- 3. Sources
CREATE TABLE IF NOT EXISTS public.sources (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    access_method TEXT NOT NULL, -- AUTHORIZED_API | LICENSED_FEED | PERMITTED_RSS | OFFICIAL_ANNOUNCEMENT | MANUAL_IMPORT
    base_url TEXT,
    is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    priority INT NOT NULL DEFAULT 100,
    reliability_score NUMERIC(4, 3) NOT NULL DEFAULT 0.800,
    health_status TEXT NOT NULL DEFAULT 'HEALTHY', -- HEALTHY | DEGRADED | UNAVAILABLE | MANUAL_ONLY
    last_success_at TIMESTAMPTZ,
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. Collection Reports (raw source-specific reports, never silently overwritten)
CREATE TABLE IF NOT EXISTS public.collection_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    movie_id UUID NOT NULL REFERENCES public.movies(id) ON DELETE RESTRICT,
    source_id UUID NOT NULL REFERENCES public.sources(id) ON DELETE RESTRICT,
    metric collection_metric NOT NULL,
    period_type reporting_period_type NOT NULL,
    day_number INT,
    reporting_date DATE NOT NULL,
    amount_inr_crores NUMERIC(12, 4) NOT NULL CHECK (amount_inr_crores >= 0),
    currency TEXT NOT NULL DEFAULT 'INR',
    source_status report_source_status NOT NULL,
    source_url TEXT NOT NULL,
    original_report_ref TEXT,
    published_at TIMESTAMPTZ,
    retrieved_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    content_hash TEXT NOT NULL,
    is_duplicate BOOLEAN NOT NULL DEFAULT FALSE,
    revision_number INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_report_dedup UNIQUE (movie_id, source_id, metric, period_type, reporting_date, content_hash)
);

CREATE INDEX IF NOT EXISTS idx_reports_movie_date ON public.collection_reports (movie_id, reporting_date DESC);
CREATE INDEX IF NOT EXISTS idx_reports_metric_period ON public.collection_reports (metric, period_type, reporting_date DESC);

-- 5. Collection Revisions (tracks updates to an existing source report)
CREATE TABLE IF NOT EXISTS public.collection_revisions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id UUID NOT NULL REFERENCES public.collection_reports(id) ON DELETE RESTRICT,
    previous_amount NUMERIC(12, 4) NOT NULL,
    new_amount NUMERIC(12, 4) NOT NULL,
    previous_status report_source_status NOT NULL,
    new_status report_source_status NOT NULL,
    revision_number INT NOT NULL,
    detected_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    notes TEXT
);

-- 6. Reconciled Collections (only compatible metric + period_type)
CREATE TABLE IF NOT EXISTS public.reconciled_collections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    movie_id UUID NOT NULL REFERENCES public.movies(id) ON DELETE RESTRICT,
    metric collection_metric NOT NULL,
    period_type reporting_period_type NOT NULL,
    reporting_date DATE NOT NULL,
    day_number INT,
    reconciled_amount_inr_crores NUMERIC(12, 4) NOT NULL,
    confidence_status report_source_status NOT NULL,
    has_conflict BOOLEAN NOT NULL DEFAULT FALSE,
    conflict_details JSONB,
    supporting_report_ids UUID[] NOT NULL DEFAULT '{}',
    methodology_note TEXT NOT NULL,
    reconciled_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_reconciled_unique UNIQUE (movie_id, metric, period_type, reporting_date)
);

CREATE INDEX IF NOT EXISTS idx_reconciled_date ON public.reconciled_collections (reporting_date DESC, metric, period_type);
CREATE INDEX IF NOT EXISTS idx_reconciled_conflicts ON public.reconciled_collections (has_conflict) WHERE has_conflict = TRUE;

-- 7. Post Drafts
CREATE TABLE IF NOT EXISTS public.post_drafts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category draft_category NOT NULL,
    title TEXT NOT NULL,
    movie_id UUID REFERENCES public.movies(id) ON DELETE SET NULL,
    reporting_date DATE NOT NULL,
    period_type reporting_period_type,
    metric collection_metric,
    generated_text TEXT NOT NULL,
    edited_text TEXT,
    hashtags TEXT[] NOT NULL DEFAULT '{}',
    entries JSONB NOT NULL DEFAULT '[]'::jsonb,
    main_figure_display TEXT,
    source_summary TEXT NOT NULL,
    weighted_char_count INT NOT NULL,
    is_valid_length BOOLEAN NOT NULL DEFAULT TRUE,
    status draft_status NOT NULL DEFAULT 'PENDING_REVIEW',
    numerical_edit_confirmed BOOLEAN NOT NULL DEFAULT FALSE,
    numerical_edit_audit JSONB,
    last_error TEXT,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '48 hours'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_drafts_status_created ON public.post_drafts (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_drafts_category ON public.post_drafts (category, reporting_date DESC);

-- 8. Post Sources (join table preserving source-report references)
CREATE TABLE IF NOT EXISTS public.post_sources (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    draft_id UUID NOT NULL REFERENCES public.post_drafts(id) ON DELETE CASCADE,
    report_id UUID NOT NULL REFERENCES public.collection_reports(id) ON DELETE RESTRICT,
    reconciled_id UUID REFERENCES public.reconciled_collections(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_post_source UNIQUE (draft_id, report_id)
);

-- 9. App Users (linked to Supabase auth.users; NEVER stores X OAuth tokens)
CREATE TABLE IF NOT EXISTS public.app_users (
    id UUID PRIMARY KEY,
    email TEXT NOT NULL,
    display_name TEXT,
    role TEXT NOT NULL DEFAULT 'OPERATOR',
    notification_prefs JSONB NOT NULL DEFAULT '{"new_drafts": true, "conflicts": true, "expiring": true, "failures": true}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 10. Published Posts (permanent audit trail of manual X publications)
CREATE TABLE IF NOT EXISTS public.published_posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    draft_id UUID NOT NULL UNIQUE REFERENCES public.post_drafts(id) ON DELETE RESTRICT,
    user_id UUID NOT NULL REFERENCES public.app_users(id) ON DELETE RESTRICT,
    final_text TEXT NOT NULL,
    x_post_id TEXT NOT NULL UNIQUE,
    x_url TEXT NOT NULL,
    category draft_category NOT NULL,
    supporting_report_ids UUID[] NOT NULL DEFAULT '{}',
    published_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_published_at ON public.published_posts (published_at DESC);

-- 11. Collection Runs
CREATE TABLE IF NOT EXISTS public.collection_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trigger_type TEXT NOT NULL, -- SCHEDULED | MANUAL
    status TEXT NOT NULL DEFAULT 'RUNNING', -- RUNNING | SUCCESS | PARTIAL_SUCCESS | FAILED
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    movies_discovered INT NOT NULL DEFAULT 0,
    reports_collected INT NOT NULL DEFAULT 0,
    conflicts_detected INT NOT NULL DEFAULT 0,
    drafts_generated INT NOT NULL DEFAULT 0,
    drafts_expired INT NOT NULL DEFAULT 0,
    source_results JSONB NOT NULL DEFAULT '{}'::jsonb,
    error_summary TEXT
);

CREATE INDEX IF NOT EXISTS idx_runs_started_at ON public.collection_runs (started_at DESC);
