/// Parses OCR text from a betting-slip screenshot into DRAFT selections.
///
/// Extraction is best-effort and never trusted: every draft must be reviewed
/// and confirmed by the user in the selection editor before analysis.
class SlipDraft {
  const SlipDraft({required this.home, required this.away, this.odds, this.marketText = '', required this.rawLine});
  final String home;
  final String away;
  final double? odds;
  final String marketText;
  final String rawLine;
}

class SlipParser {
  static final _vs = RegExp(r'^(.{2,40}?)\s+(?:vs\.?|v|-|–)\s+(.{2,40}?)$', caseSensitive: false);
  static final _odd = RegExp(r'(?<![\d.])(\d{1,3}\.\d{1,2})(?![\d.])');

  static String _stripTrailingOdd(String l) {
    final all = _odd.allMatches(l).toList();
    if (all.isEmpty) return l.trim();
    final last = all.last;
    return (l.substring(0, last.start) + l.substring(last.end)).trim();
  }

  static List<SlipDraft> parse(String ocrText) {
    final lines = ocrText.split(RegExp(r'[\r\n]+')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final out = <SlipDraft>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final m = _vs.firstMatch(_stripTrailingOdd(line));
      if (m == null) continue;
      final home = m.group(1)!.trim(), away = m.group(2)!.trim();
      if (RegExp(r'^\d').hasMatch(home) || RegExp(r'^\d').hasMatch(away)) continue;
      // Look for odds on the same line or within the next two lines.
      double? odds;
      var market = '';
      for (var j = i; j < lines.length && j <= i + 2; j++) {
        // Slips print the price last; earlier decimals are market lines (e.g. "Over 2.5").
        final all = _odd.allMatches(lines[j]).toList();
        if (all.isNotEmpty) {
          final om = all.last;
          final v = double.parse(om.group(1)!);
          if (v > 1.0 && v < 1000) {
            odds = v;
            if (j != i) market = _stripTrailingOdd(lines[j]);
            break;
          }
        }
        if (j > i && _vs.hasMatch(lines[j])) break;
      }
      if (market.isEmpty && i + 1 < lines.length && !_vs.hasMatch(lines[i + 1])) {
        market = _stripTrailingOdd(lines[i + 1]);
      }
      out.add(SlipDraft(home: home, away: away, odds: odds, marketText: market, rawLine: line));
    }
    return out;
  }
}
