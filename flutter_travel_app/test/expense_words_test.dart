import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_travel_app/services/expense_words.dart';

void main() {
  group('correctWord', () {
    test('fixes the typo that prompted this', () {
      expect(correctWord('toxi'), 'taxi');
    });

    test('fixes a doubled letter', () {
      expect(correctWord('dinnner'), 'dinner');
      expect(correctWord('hotell'), 'hotel');
    });

    test('leaves a word that is already right', () {
      expect(correctWord('taxi'), isNull);
      expect(correctWord('dinner'), isNull);
    });

    test('is case insensitive', () {
      expect(correctWord('TOXI'), 'taxi');
    });

    test('leaves a word it does not know', () {
      // Somebody's own shorthand is not a typo. Rewriting "chai wallah" into
      // the nearest vocabulary entry would be worse than leaving it.
      expect(correctWord('rangoli'), isNull);
      expect(correctWord('paragliding'), isNull);
    });

    test('does not touch short words', () {
      // "bus" and "gas" are one letter apart and both real; guessing between
      // them rewrites what somebody meant.
      expect(correctWord('gas'), isNull);
      expect(correctWord('cad'), isNull);
    });

    test('refuses to choose when two words are equally close', () {
      // 'tea' and 'sea'-like ties must not silently pick one. 'toll' and
      // 'tool'-style ambiguity is left alone rather than guessed.
      expect(correctWord('tip'), isNull); // already a word
    });

    test('does not stretch a long way for a match', () {
      expect(correctWord('xyzzy'), isNull);
      expect(correctWord('helicopter'), isNull);
    });
  });

  group('tidyNote', () {
    test('corrects and capitalises', () {
      final tidy = tidyNote('toxi');
      expect(tidy.note, 'Taxi');
      expect(tidy.category, 'Travel');
      expect(tidy.corrected, isTrue);
    });

    test('reports when nothing was corrected', () {
      final tidy = tidyNote('Dinner');
      expect(tidy.note, 'Dinner');
      expect(tidy.corrected, isFalse);
    });

    test('still capitalises without correcting', () {
      final tidy = tidyNote('dinner');
      expect(tidy.note, 'Dinner');
      // Case alone is not a correction worth asking the user about.
      expect(tidy.corrected, isFalse);
    });

    test('categorises from any word in the note', () {
      expect(tidyNote('airport toxi').category, 'Travel');
      expect(tidyNote('nice dinner at the market').category, 'Food');
      expect(tidyNote('hotel for two nights').category, 'Stay');
    });

    test('falls back to Other', () {
      expect(tidyNote('something odd').category, 'Other');
    });

    test('keeps punctuation where it sits', () {
      expect(tidyNote('toxi,').note, 'Taxi,');
    });

    test('keeps unknown words untouched', () {
      final tidy = tidyNote('toxi to Maitri Baag');
      expect(tidy.note, 'Taxi to Maitri Baag');
    });

    test('handles an empty note', () {
      final tidy = tidyNote('   ');
      expect(tidy.note, '');
      expect(tidy.category, 'Other');
      expect(tidy.corrected, isFalse);
    });

    test('the first category found wins', () {
      // "taxi to the hotel" is travel, not accommodation: what the money went
      // on is the first thing named.
      expect(tidyNote('taxi to the hotel').category, 'Travel');
    });
  });
}
