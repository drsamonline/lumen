/// Cheap typo tolerance for file-name search.
///
/// A full Levenshtein matrix is unnecessary here: the only question the UI asks
/// is "is this within one edit?", so this walks the strings once and gives up
/// as soon as a second difference appears.
///
/// One adjacent transposition counts as a single edit. That is the Damerau
/// rule rather than plain Levenshtein, and it matters: "reciept" for "receipt"
/// is the most common typo in English and is two substitutions under plain
/// Levenshtein, so without this the canonical case would not match.
class Fuzzy {
  /// 0 = identical, 1 = exactly one insertion, deletion or substitution away,
  /// 2 = further than that.
  static int withinOneEdit(String a, String b) {
    if (identical(a, b) || a == b) return 0;
    final la = a.length;
    final lb = b.length;
    final lengthDelta = la - lb;
    if (lengthDelta > 1 || lengthDelta < -1) return 2;

    if (la == lb) {
      var differences = 0;
      var firstDifference = -1;
      for (var i = 0; i < la; i++) {
        if (a.codeUnitAt(i) != b.codeUnitAt(i)) {
          differences++;
          if (differences == 1) firstDifference = i;
          if (differences > 2) return 2;
        }
      }
      if (differences == 0) return 0;
      if (differences == 1) return 1;

      // Exactly two: accept it only if they are an adjacent swap.
      final i = firstDifference;
      if (i >= 0 &&
          i + 1 < la &&
          a.codeUnitAt(i) == b.codeUnitAt(i + 1) &&
          a.codeUnitAt(i + 1) == b.codeUnitAt(i)) {
        return 1;
      }
      return 2;
    }

    // One string is a single character longer: walk both and allow one skip.
    final longer = la > lb ? a : b;
    final shorter = la > lb ? b : a;
    var i = 0;
    var j = 0;
    var skipped = false;
    while (i < longer.length && j < shorter.length) {
      if (longer.codeUnitAt(i) == shorter.codeUnitAt(j)) {
        i++;
        j++;
        continue;
      }
      if (skipped) return 2;
      skipped = true;
      i++;
    }
    return 1;
  }
}
