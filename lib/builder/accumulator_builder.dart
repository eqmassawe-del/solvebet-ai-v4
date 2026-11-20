import '../domain/audit.dart';
import '../domain/enums.dart';
import '../domain/selection.dart';
import '../engine/markets/markets.dart';

/// An audited selection available to the builder.
class BuilderCandidate {
  const BuilderCandidate(this.selection, this.report);
  final Selection selection;
  final AuditReport? report;

  String get key => '${selection.id ?? selection.matchLabel}|${selection.market.toJson()}';
  String get label =>
      '${selection.matchLabel} — ${MarketRegistry.of(selection.market.type).describe(selection.market, selection.homeTeam, selection.awayTeam)}';
  double get score => report?.score?.total ?? 0;
  String get matchKey => (selection.matchRef.isNotEmpty
          ? selection.matchRef
          : '${selection.homeTeam}|${selection.awayTeam}|${selection.kickoff?.toIso8601String() ?? ''}')
      .toLowerCase();
}

class BuilderRequest {
  const BuilderRequest({
    required this.targetOdds,
    this.maxLegs = 6,
    this.minLegScore = 60,
    this.maxPerLeague = 2,
    this.legPenalty = 4,
    this.correlationPenalty = 3,
    this.stake,
  });

  final double targetOdds;
  final int maxLegs;

  /// Approved selections below this evidence score are excluded.
  final double minLegScore;
  final int maxPerLeague;

  /// Quality points deducted per additional leg (each leg is another way to lose).
  final double legPenalty;
  final double correlationPenalty;
  final double? stake;
}

class Exclusion {
  const Exclusion(this.label, this.reason);
  final String label;
  final String reason;
}

class AccaCombo {
  AccaCombo(this.legs, this.warnings, this.quality);
  final List<BuilderCandidate> legs;
  final List<String> warnings;
  final double quality;

  /// Product of decimal odds — valid only where the bookmaker accepts the
  /// multiple. No independence assumption is made and no win probability is
  /// derived from it.
  double get combinedOdds => legs.fold<double>(1, (p, l) => p * (l.selection.odds ?? 1));
  double get minScore => legs.map((l) => l.score).reduce((a, b) => a < b ? a : b);
  double get meanScore => legs.map((l) => l.score).reduce((a, b) => a + b) / legs.length;

  /// Bookmaker-implied probability (1 / combined odds) — includes margin and
  /// is shown for reference only. NOT a model probability.
  double get bookmakerImplied => 1 / combinedOdds;
}

class BuilderResult {
  const BuilderResult({
    required this.request,
    required this.best,
    required this.targetReached,
    required this.shortlist,
    required this.excluded,
    required this.message,
  });

  final BuilderRequest request;
  final AccaCombo? best;
  final bool targetReached;
  final List<AccaCombo> shortlist;
  final List<Exclusion> excluded;
  final String message;
}

/// Detects correlation / common-factor exposure in a set of legs.
List<String> exposureWarnings(List<BuilderCandidate> legs, {int maxPerLeague = 2}) {
  final w = <String>[];
  final byLeague = <String, int>{};
  final byCountry = <String, int>{};
  final byMarket = <String, int>{};
  final teams = <String, int>{};
  final byMatch = <String, int>{};
  for (final l in legs) {
    final s = l.selection;
    byMatch[l.matchKey] = (byMatch[l.matchKey] ?? 0) + 1;
    if (s.league.isNotEmpty) byLeague[s.league] = (byLeague[s.league] ?? 0) + 1;
    if (s.country.isNotEmpty) byCountry[s.country] = (byCountry[s.country] ?? 0) + 1;
    final mk = '${s.market.type.title} ${s.market.pick}'.trim();
    byMarket[mk] = (byMarket[mk] ?? 0) + 1;
    for (final t in [s.homeTeam, s.awayTeam]) {
      teams[t.toLowerCase()] = (teams[t.toLowerCase()] ?? 0) + 1;
    }
  }
  byMatch.forEach((k, v) {
    if (v > 1) w.add('Shared match exposure: $v legs from the same fixture (strongly correlated).');
  });
  byLeague.forEach((k, v) {
    if (v > maxPerLeague) w.add('League concentration: $v legs in $k (limit $maxPerLeague).');
    if (v == maxPerLeague && v > 1) w.add('Same-league exposure: $v legs in $k share league-wide factors.');
  });
  byCountry.forEach((k, v) {
    if (v >= 3) w.add('Country concentration: $v legs in $k (shared refereeing/weather/scheduling).');
  });
  byMarket.forEach((k, v) {
    if (v >= 3) w.add('Common-factor exposure: $v legs on "$k" — one systematic shift fails them together.');
  });
  teams.forEach((k, v) {
    if (v > 1) w.add('Team "$k" appears in $v legs.');
  });
  return w;
}

/// KING'S BUILDER — best-of-available accumulator construction.
class AccumulatorBuilder {
  BuilderResult build(List<BuilderCandidate> all, BuilderRequest req) {
    final excluded = <Exclusion>[];
    final pool = <BuilderCandidate>[];

    for (final c in all) {
      final v = c.report?.verdict;
      if (c.report == null) {
        excluded.add(Exclusion(c.label, 'Never audited.'));
      } else if (v == FinalVerdict.rejected) {
        excluded.add(Exclusion(c.label, 'REJECTED — failed a VISA gate.'));
      } else if (v == FinalVerdict.incomplete) {
        excluded.add(Exclusion(c.label, 'INCOMPLETE — evidence missing; unknown is never a pass.'));
      } else if (v == FinalVerdict.watch) {
        excluded.add(Exclusion(c.label, 'WATCH — automatically removed from accumulator construction.'));
      } else if (c.selection.odds == null || c.selection.odds! <= 1) {
        excluded.add(Exclusion(c.label, 'No valid decimal odds.'));
      } else if (c.score < req.minLegScore) {
        excluded.add(Exclusion(c.label,
            'Evidence score ${c.score.toStringAsFixed(1)} below minimum ${req.minLegScore.toStringAsFixed(0)}.'));
      } else {
        pool.add(c);
      }
    }

    // Shared-match exposure: keep only the strongest leg per fixture.
    final byMatch = <String, BuilderCandidate>{};
    for (final c in pool) {
      final cur = byMatch[c.matchKey];
      if (cur == null || c.score > cur.score) {
        if (cur != null) {
          excluded.add(Exclusion(cur.label, 'Same fixture as a stronger leg (shared match exposure).'));
        }
        byMatch[c.matchKey] = c;
      } else {
        excluded.add(Exclusion(c.label, 'Same fixture as a stronger leg (shared match exposure).'));
      }
    }
    final cands = byMatch.values.toList()..sort((a, b) => b.score.compareTo(a.score));

    if (cands.isEmpty) {
      return BuilderResult(
        request: req,
        best: null,
        targetReached: false,
        shortlist: const [],
        excluded: excluded,
        message: 'Insufficient evidence: no APPROVED selections meet the builder criteria. '
            'No accumulator can be defended.',
      );
    }

    final combos = _enumerate(cands, req);
    combos.sort((a, b) => b.quality.compareTo(a.quality));
    final reaching = combos.where((c) => c.combinedOdds >= req.targetOdds - 1e-9).toList();

    AccaCombo? best;
    bool reached;
    String msg;
    if (reaching.isNotEmpty) {
      reaching.sort((a, b) {
        final q = b.quality.compareTo(a.quality);
        return q != 0 ? q : a.legs.length.compareTo(b.legs.length);
      });
      best = reaching.first;
      reached = true;
      msg = 'Target ${req.targetOdds.toStringAsFixed(2)} reached with ${best.legs.length} leg(s) '
          'at combined odds ${best.combinedOdds.toStringAsFixed(2)}.';
    } else {
      // Best-of-available: the highest-odds combination that still respects
      // every constraint. The target is NOT forced.
      final byOdds = [...combos]..sort((a, b) => b.combinedOdds.compareTo(a.combinedOdds));
      best = byOdds.first;
      reached = false;
      msg = 'Target ${req.targetOdds.toStringAsFixed(2)} NOT reachable from ${cands.length} qualifying '
          'selection(s). Strongest available combination reaches ${best.combinedOdds.toStringAsFixed(2)}. '
          'Do not add weaker selections to chase the target.';
    }

    return BuilderResult(
      request: req,
      best: best,
      targetReached: reached,
      shortlist: combos.take(10).toList(),
      excluded: excluded,
      message: msg,
    );
  }

  AccaCombo? _make(List<BuilderCandidate> legs, BuilderRequest req) {
    final leagues = <String, int>{};
    for (final l in legs) {
      final lg = l.selection.league;
      if (lg.isEmpty) continue;
      leagues[lg] = (leagues[lg] ?? 0) + 1;
      if (leagues[lg]! > req.maxPerLeague) return null; // hard constraint
    }
    final w = exposureWarnings(legs, maxPerLeague: req.maxPerLeague);
    final mean = legs.map((l) => l.score).reduce((a, b) => a + b) / legs.length;
    final mn = legs.map((l) => l.score).reduce((a, b) => a < b ? a : b);
    final q = 0.6 * mean + 0.4 * mn - req.legPenalty * (legs.length - 1) - req.correlationPenalty * w.length;
    return AccaCombo(List.unmodifiable(legs), w, q);
  }

  List<AccaCombo> _enumerate(List<BuilderCandidate> cands, BuilderRequest req) {
    final out = <AccaCombo>[];
    final maxLegs = req.maxLegs.clamp(1, cands.length);
    if (cands.length <= 16) {
      void rec(int start, List<BuilderCandidate> cur) {
        if (cur.isNotEmpty) {
          final c = _make(cur, req);
          if (c != null) out.add(c);
        }
        if (cur.length == maxLegs) return;
        for (var i = start; i < cands.length; i++) {
          cur.add(cands[i]);
          rec(i + 1, cur);
          cur.removeLast();
        }
      }

      rec(0, []);
      return out;
    }
    // Beam search for larger pools.
    const width = 200;
    var beam = <List<int>>[[]];
    for (var depth = 0; depth < maxLegs; depth++) {
      final next = <List<int>>[];
      for (final b in beam) {
        final start = b.isEmpty ? 0 : b.last + 1;
        for (var i = start; i < cands.length; i++) {
          next.add([...b, i]);
        }
      }
      final scored = <(List<int>, AccaCombo)>[];
      for (final n in next) {
        final c = _make(n.map((i) => cands[i]).toList(), req);
        if (c != null) scored.add((n, c));
      }
      scored.sort((a, b) => b.$2.combinedOdds * b.$2.quality > a.$2.combinedOdds * a.$2.quality ? 1 : -1);
      out.addAll(scored.map((e) => e.$2));
      beam = scored.take(width).map((e) => e.$1).toList();
      if (beam.isEmpty) break;
    }
    return out;
  }
}
