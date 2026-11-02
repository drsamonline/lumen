import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/search/fuzzy.dart';

void main() {
  group('withinOneEdit', () {
    test('identical strings score 0', () {
      expect(Fuzzy.withinOneEdit('receipt', 'receipt'), 0);
      expect(Fuzzy.withinOneEdit('', ''), 0);
    });

    test('a single substitution scores 1', () {
      expect(Fuzzy.withinOneEdit('receipt', 'receipy'), 1);
      expect(Fuzzy.withinOneEdit('cat', 'cut'), 1);
    });

    test('a single insertion scores 1', () {
      expect(Fuzzy.withinOneEdit('cat', 'cart'), 1);
      expect(Fuzzy.withinOneEdit('reciept', 'recieptt'), 1);
    });

    test('a single deletion scores 1', () {
      expect(Fuzzy.withinOneEdit('cart', 'cat'), 1);
      expect(Fuzzy.withinOneEdit('receipt', 'reciept'), 1);
    });

    test('two differences score 2', () {
      expect(Fuzzy.withinOneEdit('cat', 'dog'), 2);
      expect(Fuzzy.withinOneEdit('receipt', 'resipy'), 2);
      // Two separate substitutions, not a swap.
      expect(Fuzzy.withinOneEdit('abcd', 'axcx'), 2);
    });

    test('an adjacent transposition scores 1', () {
      // The canonical English typo, and the reason this is Damerau rather than
      // plain Levenshtein.
      expect(Fuzzy.withinOneEdit('receipt', 'reciept'), 1);
      expect(Fuzzy.withinOneEdit('reciept', 'receipt'), 1);
      expect(Fuzzy.withinOneEdit('beach', 'baech'), 1);
    });

    test('a non-adjacent swap scores 2', () {
      expect(Fuzzy.withinOneEdit('abcd', 'dbca'), 2);
      expect(Fuzzy.withinOneEdit('beach', 'hcaeb'), 2);
    });

    test('a length gap over one scores 2', () {
      expect(Fuzzy.withinOneEdit('a', 'abcd'), 2);
      expect(Fuzzy.withinOneEdit('', 'abc'), 2);
    });

    test('is symmetric', () {
      const pairs = <List<String>>[
        <String>['cat', 'cart'],
        <String>['receipt', 'reciept'],
        <String>['beach', 'beacg'],
        <String>['abc', 'xyz'],
      ];
      for (final pair in pairs) {
        expect(
          Fuzzy.withinOneEdit(pair[0], pair[1]),
          Fuzzy.withinOneEdit(pair[1], pair[0]),
          reason: pair.join(' vs '),
        );
      }
    });
  });
}
