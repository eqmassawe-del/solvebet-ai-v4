import '../domain/audit.dart';
import '../domain/enums.dart';
import '../domain/match_data.dart';
import '../domain/selection.dart';
import 'engine_config.dart';
import 'visa_b.dart';

/// Historical behaviour of the market in past matches where a stress
/// condition actually occurred. Engine-derived; never a probability.
class StressSample {
  const StressSample(this.description, this.matches, this.failures);
  final String description;
  final int matches;
  final int failures;
  double? get failureRate => matches == 0 ? null : failures / matches;
  String get summary => matches == 0
      ? 'No recorded matches with this condition.'
      : 'In $matches recorded match(es) where $description, the market failed $failures time(s).';
}

bool? _conditionPresent(ScenarioKind kind, HistoricalMatch m) {
  switch (kind) {
    case ScenarioKind.earlyRedCard:
      return m.hasRedCardData ? m.hadRedCard : null;
    case ScenarioKind.earlyGoal:
      if (!m.hasFullTime) return null;
      if (m.totalGoals == 0) return false;
      if (!m.hasValidSequence) return null;
      return m.goalSequence!.first.minute <= 15;
    case ScenarioKind.lateSurge:
      if (!m.hasFullTime) return null;
      if (m.totalGoals == 0) return false;
      if (!m.hasValidSequence) return null;
      return m.goalSequence!.any((g) => g.minute >= 80);
    case ScenarioKind.defensiveCollapse:
      if (!m.hasFullTime) return null;
      return m.ftHome! >= 3 || m.ftAway! >= 3;
    default:
      return null;
  }
}

String _conditionText(ScenarioKind k) => switch (k) {
      ScenarioKind.earlyRedCard => 'a red card was shown (timing not recorded)',
      ScenarioKind.earlyGoal => 'the first goal came inside 15 minutes',
      ScenarioKind.lateSurge => 'a goal was scored after 80 minutes',
      ScenarioKind.defensiveCollapse => 'a side conceded 3+ goals',
      _ => 'the condition occurred',
    };

/// Computes the engine-derived stress sample for a scenario kind, or null if
/// the kind cannot be measured from match records.
StressSample? stressSample(Selection s, ScenarioKind kind) {
  if (!{
    ScenarioKind.earlyRedCard,
    ScenarioKind.earlyGoal,
    ScenarioKind.lateSurge,
    ScenarioKind.defensiveCollapse,
  }.contains(kind)) {
    return null;
  }
  var n = 0, fails = 0;
  for (final e in [(Side.home, s.homeHistory), (Side.away, s.awayHistory)]) {
    for (final m in e.$2) {
      if (!m.comparable) continue;
      if (_conditionPresent(kind, m) != true) continue;
      final st = settleOne(s, e.$1, m);
      if (st == null || !st.isValid) continue;
      n++;
      if (st.isFailure) fails++;
    }
  }
  return StressSample(_conditionText(kind), n, fails);
}

/// VISA D — STRESS & ADVERSARIAL TEST. Outcomes: PASS, FAIL, WATCH, UNKNOWN.
///
/// No numeric probabilities are assigned to hypothetical scenarios. Each
/// scenario is classified by severity and evidence sufficiency.
VisaStageResult evaluateVisaD(Selection s, EngineConfig cfg) {
  final f = <Finding>[];
  var hasFail = false, hasUnknown = false, hasWatch = false;

  if (s.scenarios.isEmpty) {
    return const VisaStageResult(
      stage: 'D',
      title: 'STRESS & ADVERSARIAL TEST',
      outcome: VisaOutcome.unknown,
      findings: [Finding(FindingLevel.unknown, 'Stress test not performed — no adverse scenarios assessed.')],
    );
  }

  if (!s.scenarios.any((x) => x.kind == ScenarioKind.earlyRedCard)) {
    hasUnknown = true;
    f.add(const Finding(FindingLevel.unknown, 'A red-card stress scenario is mandatory.'));
  }

  var assessedCount = 0;
  for (final sc in s.scenarios) {
    final usable = sc.origin != DataOrigin.modelGenerated && sc.origin != DataOrigin.synthetic;
    final sample = stressSample(s, sc.kind);
    final sampleNote = sample == null ? '' : ' [History: ${sample.summary}]';
    if (!sc.assessed || !usable) {
      hasUnknown = true;
      f.add(Finding(FindingLevel.unknown,
          '${sc.title}: not assessed (severity and evidence sufficiency required).$sampleNote'));
      continue;
    }
    if (sc.evidence.trim().isEmpty) {
      hasUnknown = true;
      f.add(Finding(FindingLevel.unknown, '${sc.title}: no plausibility evidence documented.$sampleNote'));
      continue;
    }
    assessedCount++;
    final detail = '${sc.title} [${sc.severity.label}] — ${sc.pathway} Evidence: ${sc.evidence}$sampleNote';
    if (sc.severity == Severity.critical) {
      hasFail = true;
      f.add(Finding(FindingLevel.fail, 'Selection defeated by plausible scenario: $detail', origin: sc.origin));
    } else if (sc.severity == Severity.high) {
      if (sc.evidenceSufficient == false) {
        hasUnknown = true;
        f.add(Finding(FindingLevel.unknown, 'High-severity risk cannot be assessed (insufficient evidence): $detail'));
      } else {
        hasWatch = true;
        f.add(Finding(FindingLevel.watch, detail, origin: sc.origin));
      }
    } else {
      if (sc.evidenceSufficient == false && sc.severity == Severity.medium) {
        hasWatch = true;
        f.add(Finding(FindingLevel.watch, 'Medium risk with insufficient evidence: $detail'));
      } else {
        f.add(Finding(FindingLevel.ok, detail, origin: sc.origin));
      }
      // Adversarial cross-check against the engine-derived sample.
      final r = sample?.failureRate;
      if (sample != null &&
          r != null &&
          sample.matches >= cfg.contradictionMinSample &&
          r >= cfg.contradictionFailRate) {
        hasWatch = true;
        f.add(Finding(FindingLevel.watch,
            '${sc.title}: rated ${sc.severity.label} but history contradicts it — ${sample.summary}'));
      }
    }
  }

  if (assessedCount < cfg.minScenariosAssessed) {
    hasUnknown = true;
    f.add(Finding(FindingLevel.unknown,
        'Only $assessedCount scenario(s) fully assessed; ${cfg.minScenariosAssessed} required.'));
  }

  final outcome = hasFail
      ? VisaOutcome.fail
      : hasUnknown
          ? VisaOutcome.unknown
          : hasWatch
              ? VisaOutcome.watch
              : VisaOutcome.pass;
  return VisaStageResult(stage: 'D', title: 'STRESS & ADVERSARIAL TEST', outcome: outcome, findings: f);
}
