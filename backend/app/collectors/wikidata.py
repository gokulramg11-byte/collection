"""Wikidata SPARQL client for Indian movie metadata (zero-API-key open-data fallback).

Wikidata is CC0 open data and is used ONLY for movie discovery/metadata,
never as an authoritative box-office collection source.
"""

from datetime import date, timedelta
import httpx

from app.schemas.domain import IndianLanguage, MovieMetadataInput

WIKIDATA_SPARQL_URL = "https://query.wikidata.org/sparql"

# Wikidata QIDs strictly for the 6 supported languages:
# Malayalam, Tamil, English, Hindi, Telugu, Kannada
WIKIDATA_LANGUAGE_QIDS: dict[str, IndianLanguage] = {
    "Q36236": IndianLanguage.MALAYALAM,
    "Q5885": IndianLanguage.TAMIL,
    "Q1860": IndianLanguage.ENGLISH,
    "Q1568": IndianLanguage.HINDI,
    "Q8097": IndianLanguage.TELUGU,
    "Q33673": IndianLanguage.KANNADA,
}


class WikidataClient:
    """Async client for discovering Indian films via Wikidata SPARQL (no API key required)."""

    def __init__(self, transport: httpx.AsyncBaseTransport | None = None) -> None:
        self.transport = transport

    async def discover_indian_releases(
        self,
        reference_date: date,
        lookback_days: int = 45,
        limit: int = 50,
    ) -> list[MovieMetadataInput]:
        start_date = reference_date - timedelta(days=lookback_days)
        lang_values = " ".join(f"wd:{qid}" for qid in WIKIDATA_LANGUAGE_QIDS)
        sparql = f"""
SELECT DISTINCT ?film ?filmLabel ?lang ?releaseDate WHERE {{
  VALUES ?lang {{ {lang_values} }}
  ?film wdt:P31 wd:Q11424 ;
        wdt:P495 wd:Q668 ;
        wdt:P364 ?lang ;
        wdt:P577 ?releaseDate .
  FILTER(?releaseDate >= "{start_date.isoformat()}T00:00:00Z"^^xsd:dateTime &&
         ?releaseDate <= "{reference_date.isoformat()}T23:59:59Z"^^xsd:dateTime)
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
}}
ORDER BY DESC(?releaseDate)
LIMIT {limit}
""".strip()

        headers = {
            "Accept": "application/sparql-results+json",
            "User-Agent": "CinePulseIndia/1.0 (https://github.com/gokulramg11-byte/collection)",
        }

        async with httpx.AsyncClient(
            headers=headers,
            timeout=25.0,
            transport=self.transport,
        ) as client:
            resp = await client.get(WIKIDATA_SPARQL_URL, params={"query": sparql})
            resp.raise_for_status()
            payload = resp.json()

        movies: list[MovieMetadataInput] = []
        seen_titles: set[str] = set()
        for row in payload.get("results", {}).get("bindings", []):
            title = (row.get("filmLabel", {}).get("value") or "").strip()
            if not title or title.startswith("Q") and title[1:].isdigit():
                continue
            if title.lower() in seen_titles:
                continue
            seen_titles.add(title.lower())

            lang_uri = row.get("lang", {}).get("value", "")
            lang_qid = lang_uri.rsplit("/", 1)[-1]
            language = WIKIDATA_LANGUAGE_QIDS.get(lang_qid, IndianLanguage.OTHER)

            rel_raw = row.get("releaseDate", {}).get("value", "")[:10]
            try:
                rel_date = date.fromisoformat(rel_raw) if rel_raw else None
            except ValueError:
                rel_date = None

            movies.append(
                MovieMetadataInput(
                    tmdb_id=None,
                    title=title,
                    primary_language=language,
                    languages=[language],
                    release_date=rel_date,
                )
            )
        return movies
