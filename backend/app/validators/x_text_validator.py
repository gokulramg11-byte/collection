"""X (Twitter) weighted character counter and post validator.

Follows X's weighted character counting rules:
- Standard ASCII & Latin characters: weight 1
- URLs (http:// or https://): fixed weight 23 (t.co wrapping)
- CJK, emojis, and non-BMP Unicode codepoints: weight 2
- Maximum weighted length for standard X posts: 280
"""

from dataclasses import dataclass
import re

X_MAX_WEIGHTED_CHARS = 280
X_URL_WEIGHT = 23

_URL_PATTERN = re.compile(r"https?://[^\s]+", re.IGNORECASE)


def _is_double_weight_codepoint(cp: int) -> bool:
    """Return True if Unicode codepoint counts as weight 2 under X rules."""
    # Non-BMP (emojis, supplementary planes)
    if cp > 0xFFFF:
        return True
    # Common emoji / dingbat / symbol ranges in BMP
    if 0x2600 <= cp <= 0x27BF:
        return True
    # CJK Unified Ideographs, Hiragana, Katakana, Hangul
    if (
        0x1100 <= cp <= 0x11FF
        or 0x2E80 <= cp <= 0x9FFF
        or 0xAC00 <= cp <= 0xD7AF
        or 0xF900 <= cp <= 0xFAFF
        or 0xFE30 <= cp <= 0xFE4F
    ):
        return True
    return False


@dataclass(frozen=True)
class XValidationResult:
    weighted_length: int
    max_length: int
    is_valid: bool
    remaining: int
    suggestions: list[str]


def count_x_weighted_chars(text: str) -> int:
    """Compute X-compatible weighted character count."""
    if not text:
        return 0

    total = 0
    cursor = 0
    for match in _URL_PATTERN.finditer(text):
        prefix = text[cursor : match.start()]
        total += sum(2 if _is_double_weight_codepoint(ord(ch)) else 1 for ch in prefix)
        total += X_URL_WEIGHT
        cursor = match.end()

    tail = text[cursor:]
    total += sum(2 if _is_double_weight_codepoint(ord(ch)) else 1 for ch in tail)
    return total


def validate_x_post(text: str) -> XValidationResult:
    """Validate post text against X weighted 280-char limit without truncating figures."""
    cleaned = text.strip()
    if not cleaned:
        return XValidationResult(
            weighted_length=0,
            max_length=X_MAX_WEIGHTED_CHARS,
            is_valid=False,
            remaining=X_MAX_WEIGHTED_CHARS,
            suggestions=["Post content cannot be empty."],
        )

    weighted = count_x_weighted_chars(cleaned)
    remaining = X_MAX_WEIGHTED_CHARS - weighted
    suggestions: list[str] = []

    if remaining < 0:
        over = abs(remaining)
        suggestions.append(f"Reduce text by {over} weighted characters.")
        suggestions.append("Trim secondary hashtags or commentary instead of truncating collection figures or source attribution.")

    return XValidationResult(
        weighted_length=weighted,
        max_length=X_MAX_WEIGHTED_CHARS,
        is_valid=0 < weighted <= X_MAX_WEIGHTED_CHARS,
        remaining=remaining,
        suggestions=suggestions,
    )
