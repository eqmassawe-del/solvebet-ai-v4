import 'package:flutter_test/flutter_test.dart';
import 'package:mathbetai/domain/audit.dart';
import 'package:mathbetai/domain/enums.dart';
import 'package:mathbetai/domain/market.dart';
import 'package:mathbetai/domain/selection.dart';
import 'package:mathbetai/engine/decision_matrix.dart';
import 'package:mathbetai/engine/engine_config.dart';
import 'package:mathbetai/engine/kings_visa_engine.dart';
import 'package:mathbetai/engine/visa_a.dart';
import 'package:mathbetai/engine/visa_b.dart';
import 'package:mathbetai/engine/visa_c.dart';
import 'package:mathbetai/engine/visa_d.dart';

import 'support/synthetic.dart';

void main() {
  final engine = KingsVisaEngine(clock: () => testNow);
  const cfg = EngineConfig();

  group('Decision matrix (mandatory table)', () {
    const P = VisaOutcome.pass, W = VisaOutcome.watch, F = VisaOutcome.fail, U = VisaOutcome.unknown;
    test('PASS PASS PASS PASS → APPROVED', () => expect(decide(P, P, P, P), FinalVerdict.approved));
    test('PASS WATCH PASS PASS → WATCH', () => expect(decide(P, W, P, P), FinalVerdict.watch));
    test('PASS PASS FAIL PASS → REJECTED', () => expect(decide(P, P, F, P), FinalVerdict.rejected));
    test('PASS PASS PASS FAIL → REJECTED', () => expect(decide(P, P, P, F), FinalVerdict.rejected));
    test('UNKNOWN PASS PASS PASS → INCOMPLETE', () => expect(decide(U, P, P, P), FinalVerdict.incomplete));
    test('PASS UNKNOWN PASS PASS → INCOMPLETE', () => expect(decide(P, U, P, P), FinalVerdict.incomplete));

    test('exhaustive precedence: FAIL > UNKNOWN > WATCH > PASS', () {
      for (final a in VisaOutcome.values) {
        for (final b in VisaOutcome.values) {
          for (final c in VisaOutcome.values) {
            for (final d in VisaOutcome.values) {
              final all = [a, b, c, d];
              final v = decide(a, b, c, d);
              if (all.contains(F)) {
                expect(v, FinalVerdict.rejected);
              } else if (all.contains(U)) {
                expect(v, FinalVerdict.incomplete, reason: 'UNKNOWN must never become PASS');
              } else if (all.contains(W)) {
                expect(v, FinalVerdict.watch);
              } else {
                expect(v, FinalVerdict.approved);
              }
            }
          }
        }
      }
    });
  });

  group('Full audit', () {
    test('fully evidenced selection is APPROVED with an evidence score', () {
      final r = engine.audit(passingSelection());
      expect(r.visaA.outcome, VisaOutcome.pass, reason: r.visaA.findings.map((f) => f.text).join('\n'));
      expect(r.visaB.outcome, VisaOutcome.pass, reason: r.visaB.findings.map((f) => f.text).join('\n'));
      expect(r.visaC.outcome, VisaOutcome.pass);
      expect(r.visaD.outcome, VisaOutcome.pass, reason: r.visaD.findings.map((f) => f.text).join('\n'));
      expect(r.verdict, FinalVerdict.approved);
      expect(r.score, isNotNull);
      expect(r.score!.total, inInclusiveRange(0, 100));
      expect(r.failureCondition, contains('three goals in a row'));
    });

    test('a failed gate overrides any score (high score cannot rescue)', () {
      final s = passingSelection();
      final checks = s.checks
          .map((c) => c.factor == StructuralFactor.motivation
              ? c.copyWith(status: CheckStatus.critical, evidence: 'Team already relegated, fielding youth XI')
              : c)
          .toList();
      final r = engine.audit(s.copyWith(checks: checks));
      expect(r.visaC.outcome, VisaOutcome.fail);
      expect(r.verdict, FinalVerdict.rejected);
      expect(r.score, isNull);
    });

    test('missing match histories → INCOMPLETE, never approved', () {
      final s = passingSelection().copyWith(homeHistory: [], awayHistory: []);
      final r = engine.audit(s);
      expect(r.visaA.outcome, VisaOutcome.unknown);
      expect(r.visaB.outcome, VisaOutcome.unknown);
      expect(r.verdict, FinalVerdict.incomplete);
    });

    test('synthetic-origin data can never be approved', () {
      final s = passingSelection().copyWith(origin: DataOrigin.synthetic);
      expect(engine.audit(s).verdict, FinalVerdict.rejected);
    });
  });

  group('VISA A — market & identity', () {
    test('missing odds → UNKNOWN', () {
      final s = Selection(
        homeTeam: synHome,
        awayTeam: synAway,
        league: 'L',
        kickoff: testKickoff,
        market: noThreeInARow,
        homeHistory: calmHistory(synHome),
        awayHistory: calmHistory(synAway),
      );
      expect(evaluateVisaA(s, cfg, testNow).outcome, VisaOutcome.unknown);
    });
    test('odds ≤ 1.00 → FAIL', () {
      final s = passingSelection().copyWith(odds: 1.0);
      expect(evaluateVisaA(s, cfg, testNow).outcome, VisaOutcome.fail);
    });
    test('identical teams → FAIL', () {
      final s = passingSelection().copyWith(awayTeam: synHome);
      expect(evaluateVisaA(s, cfg, testNow).outcome, VisaOutcome.fail);
    });
    test('kickoff in the past → FAIL', () {
      final s = passingSelection().copyWith(kickoff: testNow.subtract(const Duration(hours: 1)));
      expect(evaluateVisaA(s, cfg, testNow).outcome, VisaOutcome.fail);
    });
    test('stale odds → UNKNOWN', () {
      final s = passingSelection().copyWith(oddsUpdatedAt: testNow.subtract(const Duration(days: 3)));
      expect(evaluateVisaA(s, cfg, testNow).outcome, VisaOutcome.unknown);
    });
    test('custom market without settlement definition → UNKNOWN', () {
      final s = passingSelection(market: const MarketSpec(type: MarketType.custom, customName: 'Odd market'));
      expect(evaluateVisaA(s, cfg, testNow).outcome, VisaOutcome.unknown);
    });
    test('valid identity → PASS and identifies the failure event', () {
      final r = evaluateVisaA(passingSelection(), cfg, testNow);
      expect(r.outcome, VisaOutcome.pass);
      expect(r.findings.any((f) => f.text.startsWith('FAILURE EVENT')), isTrue);
    });
  });

  group('VISA B — current failure evidence', () {
    test('failure rate is failures / valid comparable observations', () {
      final r = evaluateVisaB(passingSelection(), cfg);
      final combined = r.stats.firstWhere((s) => s.label == 'Combined last 10');
      expect(combined.valid, 20);
      expect(combined.failures, 0);
      expect(combined.failureRate, 0);
      expect(combined.successRate, 1);
    });

    test('frequent recent failures → FAIL', () {
      final s = passingSelection();
      final bad = [
        hm(3, synHome, 'SYN X', 3, 0),
        hm(10, 'SYN Y', synHome, 0, 4),
        hm(17, synHome, 'SYN Z', 4, 1, seq: '5H,10H,20H,80A,85H'),
        ...s.homeHistory.skip(3),
      ];
      final r = evaluateVisaB(s.copyWith(homeHistory: bad), cfg);
      expect(r.outcome, VisaOutcome.fail);
    });

    test('a single failure in the most recent 3 → WATCH', () {
      final s = passingSelection();
      final h = [hm(2, synHome, 'SYN X', 3, 0), ...s.homeHistory.take(9)];
      final r = evaluateVisaB(s.copyWith(homeHistory: h), cfg);
      expect(r.outcome, VisaOutcome.watch, reason: r.findings.map((f) => f.text).join('\n'));
    });

    test('missing goal sequences are UNKNOWN, not successes', () {
      final s = passingSelection();
      // 2-1 scores without sequence cannot be settled for 3-in-a-row... but
      // they can: neither side reached 3. Use 3-1 scores, which genuinely need the order.
      final h = List.generate(10, (i) => hm(3 + i * 7, synHome, 'SYN O$i', 3, 1));
      final r = evaluateVisaB(s.copyWith(homeHistory: h), cfg);
      final st = r.stats.firstWhere((x) => x.label.startsWith(synHome));
      expect(st.unknown, 5);
      expect(st.valid, 0);
      expect(r.outcome, VisaOutcome.unknown);
    });

    test('non-comparable observations are excluded from the denominator', () {
      final s = passingSelection();
      final h = s.homeHistory.map((m) => m.copyWith(comparable: false)).toList();
      final r = evaluateVisaB(s.copyWith(homeHistory: h), cfg);
      final st = r.stats.firstWhere((x) => x.label.startsWith(synHome));
      expect(st.nonComparable, 5);
      expect(st.valid, 0);
      expect(r.outcome, VisaOutcome.unknown);
    });
  });

  group('VISA C — structural risk & mandatory red-card check', () {
    test('red-card check missing → UNKNOWN', () {
      final s = passingSelection();
      final checks = s.checks
          .map((c) => c.factor == StructuralFactor.redCardExposure ? StructuralCheck(factor: c.factor) : c)
          .toList();
      final r = evaluateVisaC(s.copyWith(checks: checks), cfg);
      expect(r.outcome, VisaOutcome.unknown);
      expect(r.findings.any((f) => f.text.contains('MANDATORY red-card')), isTrue);
    });
    test('red-card check without stated uncertainty → UNKNOWN', () {
      final s = passingSelection();
      final checks = s.checks
          .map((c) => c.factor == StructuralFactor.redCardExposure ? c.copyWith(uncertainty: '') : c)
          .toList();
      expect(evaluateVisaC(s.copyWith(checks: checks), cfg).outcome, VisaOutcome.unknown);
    });
    test('model-generated evidence does not satisfy a mandatory check', () {
      final s = passingSelection();
      final checks = s.checks
          .map((c) => c.factor == StructuralFactor.lineups ? c.copyWith(origin: DataOrigin.modelGenerated) : c)
          .toList();
      expect(evaluateVisaC(s.copyWith(checks: checks), cfg).outcome, VisaOutcome.unknown);
    });
    test('a concern → WATCH; critical → FAIL', () {
      final s = passingSelection();
      List<StructuralCheck> withStatus(CheckStatus st) => s.checks
          .map((c) => c.factor == StructuralFactor.fixtureCongestion ? c.copyWith(status: st) : c)
          .toList();
      expect(evaluateVisaC(s.copyWith(checks: withStatus(CheckStatus.concern)), cfg).outcome, VisaOutcome.watch);
      expect(evaluateVisaC(s.copyWith(checks: withStatus(CheckStatus.critical)), cfg).outcome, VisaOutcome.fail);
    });
  });

  group('VISA D — stress & adversarial test', () {
    test('no scenarios → UNKNOWN', () {
      expect(evaluateVisaD(passingSelection().copyWith(scenarios: []), cfg).outcome, VisaOutcome.unknown);
    });
    test('critical scenario → FAIL', () {
      final s = passingSelection();
      final sc = [s.scenarios.first.copyWith(severity: Severity.critical), ...s.scenarios.skip(1)];
      expect(evaluateVisaD(s.copyWith(scenarios: sc), cfg).outcome, VisaOutcome.fail);
    });
    test('high severity with sufficient evidence → WATCH; insufficient → UNKNOWN', () {
      final s = passingSelection();
      final hi = [s.scenarios.first.copyWith(severity: Severity.high), ...s.scenarios.skip(1)];
      expect(evaluateVisaD(s.copyWith(scenarios: hi), cfg).outcome, VisaOutcome.watch);
      final unk = [s.scenarios.first.copyWith(severity: Severity.high, evidenceSufficient: false), ...s.scenarios.skip(1)];
      expect(evaluateVisaD(s.copyWith(scenarios: unk), cfg).outcome, VisaOutcome.unknown);
    });
    test('missing red-card scenario → UNKNOWN', () {
      final s = passingSelection();
      final sc = s.scenarios.where((x) => x.kind != ScenarioKind.earlyRedCard).toList();
      expect(evaluateVisaD(s.copyWith(scenarios: sc), cfg).outcome, VisaOutcome.unknown);
    });
    test('history contradicting a LOW rating raises WATCH', () {
      final s = passingSelection();
      // Three red-card matches in which the market failed (team scored 3 unanswered).
      final h = [
        hm(2, synHome, 'SYN R1', 3, 0, rh: 0, ra: 1),
        hm(9, synHome, 'SYN R2', 3, 0, rh: 0, ra: 1),
        hm(16, synHome, 'SYN R3', 3, 0, rh: 0, ra: 1),
        ...s.homeHistory.skip(3),
      ];
      final r = evaluateVisaD(s.copyWith(homeHistory: h), cfg);
      expect(r.outcome, VisaOutcome.watch);
      expect(r.findings.any((f) => f.text.contains('history contradicts')), isTrue);
    });
  });

  test('audit report survives JSON round-trip', () {
    final r = engine.audit(passingSelection());
    final back = AuditReport.fromJson(r.toJson());
    expect(back.verdict, r.verdict);
    expect(back.visaB.stats.length, r.visaB.stats.length);
    expect(back.score!.total, r.score!.total);
  });

  test('threshold changes cannot disable gates (sanitised)', () {
    const loose = EngineConfig(failRateFail: 5.0, minTotalValid: 0, minRecentValidPerTeam: 0);
    final s = loose.sanitized();
    expect(s.failRateFail, lessThanOrEqualTo(0.6));
    expect(s.minTotalValid, greaterThanOrEqualTo(4));
    expect(s.minRecentValidPerTeam, greaterThanOrEqualTo(2));
    final e = KingsVisaEngine(config: loose, clock: () => testNow);
    expect(e.audit(passingSelection().copyWith(homeHistory: [], awayHistory: [])).verdict, FinalVerdict.incomplete);
  });
}
