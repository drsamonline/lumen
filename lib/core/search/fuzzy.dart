/// Cheap typo tolerance for file-name search.
///
/// A full Levenshtein matrix is unnecessary here: the only question the UI asks
/// is "is this within one edit?", so this walks the strings once and gives up
/// as soon as a second difference appears.
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
      for (var i = 0; i < la; i++) {
        if (a.codeUnitAt(i) != b.codeUnitAt(i)) {
          differences++;
          if (differences > 1) return 2;
        }
      }
      return differences == 0 ? 0 : 1;
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
