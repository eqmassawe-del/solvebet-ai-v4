import '../domain/audit.dart';
import '../domain/selection.dart';
import 'engine_config.dart';
import 'visa_b.dart';

/// Explainable 0–100 evidence score used for ranking.
///
/// IMPORTANT: this is a measure of *evidence strength*, not a win
/// probability. It is only computed after the hard VISA gates; the decision
/// matrix never sees it.
EvidenceScore computeEvidenceScore(
  Selection s,
  VisaStageResult b,
  EngineConfig cfg,
  DateTime nowUtc,
) {
  double clamp01(double x) => x.isNaN ? 0 : x.clamp(0.0, 1.0);

  FailureStats? stat(String prefix) {
    for (final st in b.stats) {
      if (st.label.startsWith(prefix)) return st;
    }
    return null;
  }

  final recent = stat('Combined last ${cfg.recentWindow}');
  final broad = stat('Combined last ${cfg.broadWindow}');

  // 1. Recent market behaviour (blend recent/broad, recent weighted 2:1).
  final rr = recent?.failureRate, br = broad?.failureRate;
  final recentBehavior = (rr == null && br == null)
      ? 0.0
      : clamp01(1 - (((rr ?? br!) * 2) + (br ?? rr!)) / 3);

  // 2. Quality & size of evidence.
  final target = 2 * cfg.broadWindow;
  final considered = broad?.considered ?? 0;
  final unknownShare = considered == 0 ? 1.0 : (broad!.unknown / considered);
  final evidenceQuality = clamp01(((broad?.valid ?? 0) / target) * (1 - unknownShare));

  // 3. Comparable-opponent evidence.
  final comparability = considered == 0 ? 0.0 : clamp01(1 - broad!.nonComparable / considered);

  // 4. Market-specific safety margin (avg cushion; 2+ = full marks).
  final recs = b.records.values.expand((r) => r);
  final hasMargins = recs.any((r) => r.margin != null);
  final marketMargin = hasMargins ? clamp01(averageMargin(recs) / 2) : 0.5;

  // 5. Structural stability.
  var penalty = 0.0;
  for (final c in s.checks) {
    if (c.status == CheckStatus.concern) penalty += 0.15;
    if (c.status == CheckStatus.critical) penalty += 0.5;
    if (c.status == CheckStatus.notAssessed && !c.factor.mandatory) penalty += 0.03;
  }
  final structuralStability = clamp01(1 - penalty);

  // 6. Stress-test resilience.
  final sev = s.scenarios.where((x) => x.severity != Severity.unassessed).toList();
  final stressResilience = sev.isEmpty
      ? 0.0
      : clamp01(1 - sev.map((x) => x.severity.weight).reduce((a, b) => a + b) / (sev.length * 4));

  // 7. Data freshness (odds age and history recency).
  double oddsFresh = 0;
  if (s.oddsUpdatedAt != null) {
    final h = nowUtc.difference(s.oddsUpdatedAt!).inMinutes / 60.0;
    oddsFresh = clamp01(1 - (h - 2).clamp(0, double.infinity) / (cfg.oddsMaxAgeHours - 2).clamp(1, 1000));
  }
  double histFresh = 0;
  final all = [...s.homeHistory, ...s.awayHistory];
  if (all.isNotEmpty) {
    final latest = all.map((m) => m.date).reduce((a, b) => a.isAfter(b) ? a : b);
    final days = (s.kickoff ?? nowUtc).difference(latest).inDays;
    histFresh = clamp01(1 - (days - 14).clamp(0, 1000) / (cfg.historyMaxAgeDays - 14).clamp(1, 1000));
  }
  final dataFreshness = (oddsFresh + histFresh) / 2;

  final components = <String, double>{
    'recentBehavior': recentBehavior,
    'evidenceQuality': evidenceQuality,
    'comparability': comparability,
    'marketMargin': marketMargin,
    'structuralStability': structuralStability,
    'stressResilience': stressResilience,
    'dataFreshness': dataFreshness,
  };
  final w = cfg.weights;
  final wSum = components.keys.map((k) => w[k] ?? 0).fold<double>(0, (a, b) => a + b);
  final total = wSum == 0
      ? 0.0
      : components.entries.map((e) => e.value * (w[e.key] ?? 0)).fold<double>(0, (a, b) => a + b) /
          wSum *
          100;
  return EvidenceScore(total: double.parse(total.toStringAsFixed(1)), components: components, weights: w);
}
