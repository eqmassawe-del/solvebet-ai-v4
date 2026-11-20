import '../domain/audit.dart';
import '../domain/enums.dart';
import '../domain/selection.dart';
import 'decision_matrix.dart';
import 'engine_config.dart';
import 'markets/markets.dart';
import 'scoring.dart';
import 'visa_a.dart';
import 'visa_b.dart';
import 'visa_c.dart';
import 'visa_d.dart';

/// The deterministic KING'S VISA engine. It is the sole authority on
/// approval. Optional AI analysis may explain a report but never changes it.
class KingsVisaEngine {
  KingsVisaEngine({EngineConfig config = const EngineConfig(), DateTime Function()? clock})
      : config = config.sanitized(),
        _clock = clock ?? (() => DateTime.now().toUtc());

  final EngineConfig config;
  final DateTime Function() _clock;

  AuditReport audit(Selection s) {
    final now = _clock();
    final a = evaluateVisaA(s, config, now);
    final b = evaluateVisaB(s, config);
    final c = evaluateVisaC(s, config);
    final d = evaluateVisaD(s, config);
    final verdict = decide(a.outcome, b.outcome, c.outcome, d.outcome);

    final ev = MarketRegistry.of(s.market.type);
    final failCond = ev.validate(s.market).ok
        ? ev.failCondition(s.market, s.homeTeam, s.awayTeam)
        : 'Undefined — market definition incomplete.';

    final score = (verdict == FinalVerdict.approved || verdict == FinalVerdict.watch)
        ? computeEvidenceScore(s, b, config, now)
        : null;

    return AuditReport(
      selectionId: s.id,
      createdAt: now,
      visaA: a,
      visaB: b,
      visaC: c,
      visaD: d,
      verdict: verdict,
      failureCondition: failCond,
      failureEvidence: _failureEvidence(b),
      primaryRisk: _primaryRisk(s, b, c, d),
      reasoning: _reasoning(verdict, [a, b, c, d]),
      score: score,
    );
  }

  String _failureEvidence(VisaStageResult b) {
    final combined = b.stats.where((x) => x.label.startsWith('Combined')).toList();
    if (combined.isEmpty) return 'No failure evidence computed.';
    return combined.map((x) => x.summary).join(' | ');
  }

  String _primaryRisk(Selection s, VisaStageResult b, VisaStageResult c, VisaStageResult d) {
    // Priority: plausible critical/high scenarios, structural critical/concern,
    // then the weakest historical window.
    final sc = [...s.scenarios]..sort((x, y) => y.severity.weight.compareTo(x.severity.weight));
    if (sc.isNotEmpty && sc.first.severity.weight >= Severity.high.weight) {
      return '${sc.first.title}: ${sc.first.pathway}';
    }
    for (final st in [CheckStatus.critical, CheckStatus.concern]) {
      for (final ch in s.checks) {
        if (ch.status == st && ch.evidence.isNotEmpty) return '${ch.factor.title}: ${ch.evidence}';
      }
    }
    final worst = b.stats.where((x) => x.failureRate != null).toList()
      ..sort((x, y) => y.failureRate!.compareTo(x.failureRate!));
    if (worst.isNotEmpty && worst.first.failures > 0) return 'Historical failures — ${worst.first.summary}';
    if (sc.isNotEmpty && sc.first.severity != Severity.unassessed) {
      return '${sc.first.title}: ${sc.first.pathway}';
    }
    final blocking = [...b.blocking, ...c.blocking, ...d.blocking];
    if (blocking.isNotEmpty) return 'Unresolved evidence gap: ${blocking.first.text}';
    return 'No dominant failure pathway identified from available evidence.';
  }

  String _reasoning(FinalVerdict v, List<VisaStageResult> stages) {
    final summary = stages.map((x) => 'VISA ${x.stage} ${x.outcome.label}').join(', ');
    switch (v) {
      case FinalVerdict.rejected:
        final failing = stages.where((x) => x.outcome == VisaOutcome.fail).map((x) => x.stage).join(', ');
        final first = stages
            .expand((x) => x.findings)
            .firstWhere((f) => f.level == FindingLevel.fail, orElse: () => const Finding(FindingLevel.fail, ''));
        return 'REJECTED — failed VISA $failing. ${first.text} ($summary)';
      case FinalVerdict.incomplete:
        final unk = stages.where((x) => x.outcome == VisaOutcome.unknown).map((x) => x.stage).join(', ');
        return 'INCOMPLETE — missing or insufficient evidence in VISA $unk. '
            'Unknown is never treated as a pass. ($summary)';
      case FinalVerdict.watch:
        final w = stages.where((x) => x.outcome == VisaOutcome.watch).map((x) => x.stage).join(', ');
        return 'WATCH — no gate failed, but VISA $w raised warning signals. '
            'Excluded from accumulator construction. ($summary)';
      case FinalVerdict.approved:
        return 'APPROVED — all four VISA gates passed on the recorded evidence. '
            'This is not a guarantee: approval means no failure pathway was found, '
            'not that the selection will win. ($summary)';
    }
  }
}
