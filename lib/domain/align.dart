/// Word-level alignment for pronunciation drills (spec §6.3).
/// LCS between normalized target and heard words; returns which target
/// words were matched. Honest framing: this measures ASR intelligibility,
/// not phoneme accuracy.
library;

List<String> normalizeWords(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), '')
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .toList();

/// Returns a bool per target word: true if matched (in order) in [heard].
List<bool> alignWords(List<String> target, List<String> heard) {
  final n = target.length, m = heard.length;
  final dp = List.generate(n + 1, (_) => List.filled(m + 1, 0));
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      dp[i][j] = target[i - 1] == heard[j - 1]
          ? dp[i - 1][j - 1] + 1
          : (dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1]);
    }
  }
  final matched = List.filled(n, false);
  var i = n, j = m;
  while (i > 0 && j > 0) {
    if (target[i - 1] == heard[j - 1]) {
      matched[i - 1] = true;
      i--;
      j--;
    } else if (dp[i - 1][j] >= dp[i][j - 1]) {
      i--;
    } else {
      j--;
    }
  }
  return matched;
}

double alignScore(String target, String heard) {
  final t = normalizeWords(target);
  if (t.isEmpty) return 0;
  final matched = alignWords(t, normalizeWords(heard));
  return matched.where((x) => x).length / t.length;
}
