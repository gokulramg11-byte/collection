"""Movie matching service connecting collection reports to canonical Movie records."""

import re
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.entities import Movie
from app.schemas.domain import IndianLanguage, MovieMetadataInput, RawCollectionReportInput


def normalize_title(title: str) -> str:
    """Normalize movie title for deterministic matching."""
    cleaned = re.sub(r"[^a-z0-9\s]", "", title.lower())
    return re.sub(r"\s+", " ", cleaned).strip()


def upsert_movie_from_metadata(session: Session, meta: MovieMetadataInput) -> Movie:
    """Insert or update a Movie record from TMDB or authorized metadata."""
    existing: Movie | None = None
    if meta.tmdb_id is not None:
        existing = session.scalar(select(Movie).where(Movie.tmdb_id == meta.tmdb_id))

    if existing is None:
        norm = normalize_title(meta.title)
        for candidate in session.scalars(select(Movie)).all():
            if normalize_title(candidate.title) == norm:
                existing = candidate
                break

    if existing is not None:
        existing.title = meta.title
        existing.original_title = meta.original_title or existing.original_title
        existing.primary_language = meta.primary_language.value
        existing.languages = sorted(set([*existing.languages, *[l.value for l in meta.languages]]))
        existing.release_date = meta.release_date or existing.release_date
        existing.poster_path = meta.poster_path or existing.poster_path
        if meta.production_companies:
            existing.production_companies = meta.production_companies
        if meta.overview:
            existing.overview = meta.overview
        session.flush()
        return existing

    movie = Movie(
        tmdb_id=meta.tmdb_id,
        title=meta.title,
        original_title=meta.original_title,
        primary_language=meta.primary_language.value,
        languages=[l.value for l in (meta.languages or [meta.primary_language])],
        release_date=meta.release_date,
        poster_path=meta.poster_path,
        production_companies=meta.production_companies,
        overview=meta.overview,
        is_monitored=True,
    )
    session.add(movie)
    session.flush()
    return movie


def match_movie_for_report(session: Session, report: RawCollectionReportInput) -> Movie:
    """Match an incoming collection report to a Movie, creating a minimal record if needed."""
    if report.tmdb_id is not None:
        by_tmdb = session.scalar(select(Movie).where(Movie.tmdb_id == report.tmdb_id))
        if by_tmdb is not None:
            return by_tmdb

    norm_target = normalize_title(report.movie_title)
    candidates = session.scalars(select(Movie)).all()
    for movie in candidates:
        if normalize_title(movie.title) == norm_target:
            return movie
        if movie.original_title and normalize_title(movie.original_title) == norm_target:
            return movie

    lang = (report.language or IndianLanguage.OTHER).value
    created = Movie(
        tmdb_id=report.tmdb_id,
        title=report.movie_title.strip(),
        primary_language=lang,
        languages=[lang],
        is_monitored=True,
    )
    session.add(created)
    session.flush()
    return created
