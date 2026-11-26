/// X (Twitter) weighted character counter for 280-character limit validation.
///
/// Matches X's weighted rules:
/// - URLs (`http://` / `https://`): fixed 23 weighted chars
/// - Non-BMP (emojis) & CJK/symbol ranges: 2 weighted chars
/// - Standard ASCII / Latin: 1 weighted char
class XValidationResult {
  const XValidationResult({
    required this.weightedLength,
    required this.maxLength,
    required this.isValid,
    required this.remaining,
    required this.suggestions,
  });

  final int weightedLength;
  final int maxLength;
  final bool isValid;
  final int remaining;
  final List<String> suggestions;
}

class XCharacterCounter {
  const XCharacterCounter._();

  static const int maxWeightedChars = 280;
  static const int urlWeight = 23;

  static final RegExp _urlPattern = RegExp(r'https?://[^\s]+', caseSensitive: false);

  static bool _isDoubleWeightRune(int rune) {
    if (rune > 0xFFFF) return true;
    if (rune >= 0x2600 && rune <= 0x27BF) return true;
    if ((rune >= 0x1100 && rune <= 0x11FF) ||
        (rune >= 0x2E80 && rune <= 0x9FFF) ||
        (rune >= 0xAC00 && rune <= 0xD7AF) ||
        (rune >= 0xF900 && rune <= 0xFAFF) ||
        (rune >= 0xFE30 && rune <= 0xFE4F)) {
      return true;
    }
    return false;
  }

  static int _countSegment(String segment) {
    var count = 0;
    for (final rune in segment.runes) {
      count += _isDoubleWeightRune(rune) ? 2 : 1;
    }
    return count;
  }

  static int countWeighted(String text) {
    if (text.isEmpty) return 0;
    var total = 0;
    var cursor = 0;
    for (final match in _urlPattern.allMatches(text)) {
      total += _countSegment(text.substring(cursor, match.start));
      total += urlWeight;
      cursor = match.end;
    }
    total += _countSegment(text.substring(cursor));
    return total;
  }

  static XValidationResult validate(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const XValidationResult(
        weightedLength: 0,
        maxLength: maxWeightedChars,
        isValid: false,
        remaining: maxWeightedChars,
        suggestions: ['Post content cannot be empty.'],
      );
    }

    final weighted = countWeighted(trimmed);
    final remaining = maxWeightedChars - weighted;
    final suggestions = <String>[];
    if (remaining < 0) {
      suggestions.add('Reduce text by ${remaining.abs()} weighted characters.');
      suggestions.add(
        'Trim commentary or secondary hashtags instead of truncating box-office figures or source attribution.',
      );
    }

    return XValidationResult(
      weightedLength: weighted,
      maxLength: maxWeightedChars,
      isValid: weighted > 0 && weighted <= maxWeightedChars,
      remaining: remaining,
      suggestions: suggestions,
    );
  }
}
