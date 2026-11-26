"""Application configuration loaded from environment variables."""

from functools import lru_cache
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """CinePulse India backend settings."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_env: str = Field(default="development")
    log_level: str = Field(default="INFO")
    display_timezone: str = Field(default="Asia/Kolkata")
    draft_expiry_hours: int = Field(default=48, ge=1, le=168)
    conflict_threshold_pct: float = Field(default=5.0, ge=0.1, le=50.0)

    # Database / Supabase
    supabase_url: str = Field(default="")
    supabase_service_role_key: str = Field(default="")
    database_url: str = Field(default="sqlite+pysqlite:///:memory:")

    # TMDB (metadata & posters only)
    tmdb_api_key: str = Field(default="")
    tmdb_read_access_token: str = Field(default="")

    # Authorized box-office feeds
    licensed_feed_api_key: str = Field(default="")
    licensed_feed_base_url: str = Field(default="")
    permitted_rss_urls: str = Field(default="")
    manual_import_dir: str = Field(default="./data/manual_imports")


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Return cached settings instance."""
    return Settings()
