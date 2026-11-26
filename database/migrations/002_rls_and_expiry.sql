-- CinePulse India — Row Level Security (RLS) & Server-Side Draft Expiry

-- 1. Enable RLS on all tables
ALTER TABLE public.movies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.collection_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.collection_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reconciled_collections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.post_drafts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.post_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.published_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.collection_runs ENABLE ROW LEVEL SECURITY;

-- 2. App Users: strict self-only access
CREATE POLICY "Users can view own profile"
    ON public.app_users FOR SELECT
    TO authenticated
    USING (auth.uid() = id);

CREATE POLICY "Users can update own profile"
    ON public.app_users FOR UPDATE
    TO authenticated
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can insert own profile"
    ON public.app_users FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = id);

-- 3. Authenticated Operator Read Access for Analytics & Drafts
CREATE POLICY "Authenticated operators read movies"
    ON public.movies FOR SELECT TO authenticated USING (TRUE);

CREATE POLICY "Authenticated operators read sources"
    ON public.sources FOR SELECT TO authenticated USING (TRUE);

CREATE POLICY "Authenticated operators read collection_reports"
    ON public.collection_reports FOR SELECT TO authenticated USING (TRUE);

CREATE POLICY "Authenticated operators read collection_revisions"
    ON public.collection_revisions FOR SELECT TO authenticated USING (TRUE);

CREATE POLICY "Authenticated operators read reconciled_collections"
    ON public.reconciled_collections FOR SELECT TO authenticated USING (TRUE);

CREATE POLICY "Authenticated operators read post_drafts"
    ON public.post_drafts FOR SELECT TO authenticated USING (TRUE);

CREATE POLICY "Authenticated operators read post_sources"
    ON public.post_sources FOR SELECT TO authenticated USING (TRUE);

CREATE POLICY "Authenticated operators read collection_runs"
    ON public.collection_runs FOR SELECT TO authenticated USING (TRUE);

-- 4. Authenticated Operator Draft Review & Manual Publishing Updates
-- Operators can edit/cancel/publish drafts, but cannot delete historical reports.
CREATE POLICY "Authenticated operators update post_drafts"
    ON public.post_drafts FOR UPDATE
    TO authenticated
    USING (status IN ('PENDING_REVIEW', 'EDITED', 'PUBLISHING', 'FAILED'))
    WITH CHECK (status IN ('PENDING_REVIEW', 'EDITED', 'PUBLISHING', 'PUBLISHED', 'FAILED', 'CANCELLED'));

CREATE POLICY "Authenticated operators read published_posts"
    ON public.published_posts FOR SELECT TO authenticated USING (TRUE);

CREATE POLICY "Authenticated operators insert own published_posts"
    ON public.published_posts FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

-- 5. Idempotent Server-Side Draft Expiry Function
-- Rules:
--   - PENDING_REVIEW older than 48h -> EXPIRED
--   - EDITED older than 48h -> EXPIRED
--   - PUBLISHED, FAILED, PUBLISHING are NEVER expired by cleanup
--   - Source reports, historical collections, and published audit records are NEVER deleted
CREATE OR REPLACE FUNCTION public.expire_stale_drafts()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    affected_count INT;
BEGIN
    UPDATE public.post_drafts
    SET
        status = 'EXPIRED',
        updated_at = NOW()
    WHERE
        status IN ('PENDING_REVIEW', 'EDITED')
        AND expires_at <= NOW();

    GET DIAGNOSTICS affected_count = ROW_COUNT;
    RETURN affected_count;
END;
$$;

-- 6. Automatic updated_at trigger helper
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_movies_updated ON public.movies;
CREATE TRIGGER trg_movies_updated BEFORE UPDATE ON public.movies
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_sources_updated ON public.sources;
CREATE TRIGGER trg_sources_updated BEFORE UPDATE ON public.sources
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_reconciled_updated ON public.reconciled_collections;
CREATE TRIGGER trg_reconciled_updated BEFORE UPDATE ON public.reconciled_collections
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_drafts_updated ON public.post_drafts;
CREATE TRIGGER trg_drafts_updated BEFORE UPDATE ON public.post_drafts
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_users_updated ON public.app_users;
CREATE TRIGGER trg_users_updated BEFORE UPDATE ON public.app_users
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
