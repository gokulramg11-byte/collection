"""TMDB API client for Indian movie metadata and posters ONLY.

TMDB must NEVER be treated as an authoritative box-office collection source.
"""

from datetime import date, timedelta
import httpx

from app.schemas.domain import IndianLanguage, MovieMetadataInput

TMDB_BASE_URL = "https://api.themoviedb.org/3"
TMDB_IMAGE_BASE_URL = "https://image.tmdb.org/t/p/w500"

TMDB_LANGUAGE_MAP: dict[str, IndianLanguage] = {
    "ml": IndianLanguage.MALAYALAM,
    "ta": IndianLanguage.TAMIL,
    "en": IndianLanguage.ENGLISH,
    "hi": IndianLanguage.HINDI,
    "te": IndianLanguage.TELUGU,
    "kn": IndianLanguage.KANNADA,
}


class TmdbClient:
    """Async client for TMDB v3 discovery and movie details."""

    def __init__(
        self,
        api_key: str = "",
        read_access_token: str = "",
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self.api_key = api_key
        self.read_access_token = read_access_token
        self.transport = transport

    def is_configured(self) -> bool:
        return bool(self.api_key or self.read_access_token)

    def _headers(self) -> dict[str, str]:
        headers = {"Accept": "application/json"}
        if self.read_access_token:
            headers["Authorization"] = f"Bearer {self.read_access_token}"
        return headers

    def _params(self, extra: dict | None = None) -> dict:
        params = dict(extra or {})
        if self.api_key and not self.read_access_token:
            params["api_key"] = self.api_key
        return params

    async def discover_indian_releases(
        self,
        reference_date: date,
        lookback_days: int = 30,
    ) -> list[MovieMetadataInput]:
        """Discover recent Indian theatrical releases across major Indian languages."""
        if not self.is_configured():
            return []

        start_date = reference_date - timedelta(days=lookback_days)
        params = self._params(
            {
                "with_origin_country": "IN",
                "primary_release_date.gte": start_date.isoformat(),
                "primary_release_date.lte": reference_date.isoformat(),
                "sort_by": "popularity.desc",
                "page": 1,
            }
        )

        async with httpx.AsyncClient(
            base_url=TMDB_BASE_URL,
            headers=self._headers(),
            timeout=20.0,
            transport=self.transport,
        ) as client:
            response = await client.get("/discover/movie", params=params)
            response.raise_for_status()
            payload = response.json()

        movies: list[MovieMetadataInput] = []
        for item in payload.get("results", []):
            lang_code = (item.get("original_language") or "").lower()
            if lang_code not in TMDB_LANGUAGE_MAP:
                continue
            language = TMDB_LANGUAGE_MAP[lang_code]
            rel_str = item.get("release_date") or None
            rel_date = date.fromisoformat(rel_str) if rel_str else None
            poster = item.get("poster_path")
            poster_url = f"{TMDB_IMAGE_BASE_URL}{poster}" if poster else None

            movies.append(
                MovieMetadataInput(
                    tmdb_id=item.get("id"),
                    title=item.get("title") or item.get("original_title") or "Untitled",
                    original_title=item.get("original_title"),
                    primary_language=language,
                    languages=[language],
                    release_date=rel_date,
                    poster_path=poster_url,
                    overview=item.get("overview"),
                )
            )
        return movies
