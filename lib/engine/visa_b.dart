import 'dart:math' as math;

import '../domain/audit.dart';
import '../domain/enums.dart';
import '../domain/market.dart';
import '../domain/match_data.dart';
import '../domain/selection.dart';
import 'engine_config.dart';
import 'markets/market_evaluator.dart';
import 'markets/markets.dart';

/// Settles a team's history for the selection. Records are newest first.
List<ObservationRecord> settleHistory(
  Selection s,
  Side fixtureSide,
  List<HistoricalMatch> history,
) {
  final ev = MarketRegistry.of(s.market.type);
  final team = s.teamName(fixtureSide);
  final sorted = [...history]..sort((a, b) => b.date.compareTo(a.date));
  final out = <ObservationRecord>[];
  for (final m in sorted) {
    final teamSide = m.sideOf(team);
    if (teamSide == null) {
      out.add(ObservationRecord(
        date: m.date,
        label: '${m.homeTeam} ${m.scoreLabel} ${m.awayTeam}',
        settlement: Settlement.unknown,
        comparable: m.comparable,
        origin: m.origin,
        source: m.source,
        note: 'Team not found in record',
      ));
      continue;
    }
    // Which side of this past match stands in for the fixture's home team.
    final homeAs = fixtureSide == Side.home ? teamSide : teamSide.other;
    final st = ev.settle(s.market, m, homeAs);
    final missing = _missingFields(ev.requiredFields(s.market), m);
    out.add(ObservationRecord(
      date: m.date,
      label: '${m.homeTeam} ${m.scoreLabel} ${m.awayTeam}',
      settlement: st,
      comparable: m.comparable,
      origin: m.origin,
      source: m.source,
      margin: ev.margin(s.market, m, homeAs),
      venue: teamSide,
      hadRedCard: m.hasRedCardData ? m.hadRedCard : null,
      note: st == Settlement.unknown && missing.isNotEmpty ? 'Missing: ${missing.join(', ')}' : '',
    ));
  }
  return out;
}

/// Settles one historical match for the selection; null if the team is not
/// part of the record.
Settlement? settleOne(Selection s, Side fixtureSide, HistoricalMatch m) {
  final teamSide = m.sideOf(s.teamName(fixtureSide));
  if (teamSide == null) return null;
  final homeAs = fixtureSide == Side.home ? teamSide : teamSide.other;
  return MarketRegistry.of(s.market.type).settle(s.market, m, homeAs);
}

List<String> _missingFields(Set<EvidenceField> req, HistoricalMatch m) => [
      if (req.contains(EvidenceField.fullTime) && !m.hasFullTime) 'full-time score',
      if (req.contains(EvidenceField.halfTime) && !m.hasHalfTime) 'half-time score',
      if (req.contains(EvidenceField.goalSequence) && !m.hasValidSequence) 'goal sequence',
      if (req.contains(EvidenceField.corners) && !m.hasCorners) 'corners',
      if (req.contains(EvidenceField.userSettlement) && m.marketResultOverride == null) 'market result',
    ];

FailureStats computeStats(String label, Iterable<ObservationRecord> recs) {
  var considered = 0, valid = 0, failures = 0, unknown = 0, pushes = 0, nonComp = 0;
  for (final r in recs) {
    considered++;
    if (!r.comparable) {
      nonComp++;
      continue;
    }
    if (r.settlement == Settlement.unknown) {
      unknown++;
    } else if (r.settlement == Settlement.push) {
      pushes++;
    } else {
      valid++;
      if (r.settlement.isFailure) failures++;
    }
  }
  return FailureStats(
    label: label,
    considered: considered,
    valid: valid,
    failures: failures,
    unknown: unknown,
    pushes: pushes,
    nonComparable: nonComp,
  );
}

/// VISA B — CURRENT FAILURE EVIDENCE. Outcomes: PASS, FAIL, WATCH, UNKNOWN.
VisaStageResult evaluateVisaB(Selection s, EngineConfig cfg) {
  final f = <Finding>[];
  final homeRecs = settleHistory(s, Side.home, s.homeHistory);
  final awayRecs = settleHistory(s, Side.away, s.awayHistory);
  final h = s.homeTeam, a = s.awayTeam;

  final hBroad = homeRecs.take(cfg.broadWindow).toList();
  final aBroad = awayRecs.take(cfg.broadWindow).toList();
  final hRecent = hBroad.take(cfg.recentWindow).toList();
  final aRecent = aBroad.take(cfg.recentWindow).toList();

  final hR = computeStats('$h last ${cfg.recentWindow}', hRecent);
  final aR = computeStats('$a last ${cfg.recentWindow}', aRecent);
  final cR = computeStats('Combined last ${cfg.recentWindow}', [...hRecent, ...aRecent]);
  final cB = computeStats('Combined last ${cfg.broadWindow}', [...hBroad, ...aBroad]);
  final hVenue = computeStats('$h at home (last ${cfg.broadWindow})', hBroad.where((r) => r.venue == Side.home));
  final aVenue = computeStats('$a away (last ${cfg.broadWindow})', aBroad.where((r) => r.venue == Side.away));
  final stats = [hR, aR, cR, cB, hVenue, aVenue];

  var hasFail = false, hasUnknown = false, hasWatch = false;
  void unknown(String t) {
    hasUnknown = true;
    f.add(Finding(FindingLevel.unknown, t));
  }

  void fail(String t) {
    hasFail = true;
    f.add(Finding(FindingLevel.fail, t));
  }

  void watch(String t) {
    hasWatch = true;
    f.add(Finding(FindingLevel.watch, t));
  }

  // --- sufficiency ---
  for (final st in [hR, aR]) {
    if (st.valid < cfg.minRecentValidPerTeam) {
      unknown('${st.label}: only ${st.valid} valid comparable observation(s); '
          '${cfg.minRecentValidPerTeam} required.');
    }
    if (st.considered > 0 && st.unknown / st.considered > cfg.maxUnknownShareRecent) {
      unknown('${st.label}: ${st.unknown}/${st.considered} observations cannot be settled '
          '(missing data counts as UNKNOWN, never as success).');
    }
  }
  if (cB.valid < cfg.minTotalValid) {
    unknown('${cB.label}: ${cB.valid} valid observations; ${cfg.minTotalValid} required.');
  }

  // --- failure frequency ---
  final failCountGate = (cfg.failRateFail * cfg.minTotalValid).ceil();
  bool exceeds(FailureStats st, int minSample) {
    final r = st.failureRate;
    if (r == null) return false;
    return st.valid >= minSample && r >= cfg.failRateFail;
  }

  if (exceeds(hR, cfg.minRecentValidPerTeam)) fail('${hR.summary} — at/above ${_pct(cfg.failRateFail)} fail threshold.');
  if (exceeds(aR, cfg.minRecentValidPerTeam)) fail('${aR.summary} — at/above ${_pct(cfg.failRateFail)} fail threshold.');
  if (exceeds(cB, cfg.minTotalValid)) fail('${cB.summary} — at/above ${_pct(cfg.failRateFail)} fail threshold.');
  // With an insufficient sample, failures can still be numerous enough that
  // no amount of additional evidence could bring the rate below threshold.
  if (cB.valid < cfg.minTotalValid && cB.failures >= failCountGate && !hasFail) {
    fail('${cB.failures} market failures in the last ${cfg.broadWindow} matches already exceed the '
        'tolerance for the minimum sample (${cfg.minTotalValid}).');
  }

  // --- watch signals ---
  final cRate = cR.failureRate;
  if (cRate != null && cRate > cfg.failRateWatch && cR.valid > 0) {
    watch('${cR.summary} — above ${_pct(cfg.failRateWatch)} watch threshold.');
  }
  if (cfg.watchOnEmphasisFailure) {
    for (final e in [(h, hBroad), (a, aBroad)]) {
      final em = e.$2.take(cfg.emphasisWindow).where((r) => r.comparable && r.settlement.isFailure);
      if (em.isNotEmpty) {
        watch('${e.$1}: market failed in ${em.length} of the last ${cfg.emphasisWindow} matches '
            '(${em.map((r) => r.label).join('; ')}).');
      }
    }
  }
  for (final v in [hVenue, aVenue]) {
    final r = v.failureRate;
    if (r != null && v.valid >= 3 && r >= cfg.failRateFail) {
      watch('Venue split — ${v.summary}.');
    }
  }
  // Margin-of-safety deterioration.
  for (final e in [(h, hBroad), (a, aBroad)]) {
    final m = e.$2.where((r) => r.comparable && r.margin != null).map((r) => r.margin!).toList();
    if (m.length >= cfg.emphasisWindow + 2) {
      final recent = _avg(m.take(cfg.emphasisWindow));
      final all = _avg(m);
      if (all - recent >= cfg.marginDeteriorationWatch) {
        watch('${e.$1}: safety margin deteriorating (last ${cfg.emphasisWindow} avg '
            '${recent.toStringAsFixed(2)} vs last ${m.length} avg ${all.toStringAsFixed(2)}).');
      }
    }
  }

  // --- context ---
  final redRecs = [...hBroad, ...aBroad].where((r) => r.hadRedCard == true).toList();
  final redKnown = [...hBroad, ...aBroad].where((r) => r.hadRedCard != null).length;
  f.add(Finding(
    FindingLevel.info,
    'Red-card history: ${redRecs.length} of $redKnown matches with card data had a red card'
    '${redRecs.isEmpty ? '' : '; market failed in ${redRecs.where((r) => r.settlement.isFailure).length} of them'}.',
  ));
  final excluded = cB.nonComparable;
  if (excluded > 0) {
    f.add(Finding(FindingLevel.info, '$excluded non-comparable observation(s) excluded from denominators.'));
  }
  f.add(const Finding(FindingLevel.info,
      'Historical success frequency is descriptive only — it is NOT a calibrated win probability.'));
  if (!hasFail && !hasUnknown && !hasWatch) {
    f.add(Finding(FindingLevel.ok, '${cR.summary}; ${cB.summary}.'));
  }

  final outcome = hasFail
      ? VisaOutcome.fail
      : hasUnknown
          ? VisaOutcome.unknown
          : hasWatch
              ? VisaOutcome.watch
              : VisaOutcome.pass;

  return VisaStageResult(
    stage: 'B',
    title: 'CURRENT FAILURE EVIDENCE',
    outcome: outcome,
    findings: f,
    stats: stats,
    records: {'$h history': hBroad, '$a history': aBroad},
  );
}

double _avg(Iterable<double> xs) {
  final l = xs.toList();
  return l.isEmpty ? 0 : l.reduce((x, y) => x + y) / l.length;
}

String _pct(double x) => '${(x * 100).toStringAsFixed(0)}%';

/// Exposed for scoring.
double averageMargin(Iterable<ObservationRecord> recs) {
  final m = recs.where((r) => r.comparable && r.margin != null).map((r) => math.min(r.margin!, 3.0));
  return _avg(m);
}
