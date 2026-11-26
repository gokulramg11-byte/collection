import 'package:cinepulse_india/core/utils/x_character_counter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('XCharacterCounter', () {
    test('counts ASCII characters with weight 1', () {
      expect(XCharacterCounter.countWeighted('CinePulse India'), 15);
    });

    test('counts URLs as fixed 23 weighted characters', () {
      const text = 'Report: https://example.com/box-office/2026/11/26/long-url';
      // "Report: " = 8 + URL = 23 -> 31
      expect(XCharacterCounter.countWeighted(text), 31);
    });

    test('counts emojis as 2 weighted characters', () {
      expect(XCharacterCounter.countWeighted('🔥'), 2);
    });

    test('rejects empty or >280 weighted char posts without truncating', () {
      final emptyRes = XCharacterCounter.validate('   ');
      expect(emptyRes.isValid, isFalse);

      final longRes = XCharacterCounter.validate('A' * 281);
      expect(longRes.isValid, isFalse);
      expect(longRes.remaining, -1);
      expect(longRes.suggestions, isNotEmpty);
    });
  });
}
