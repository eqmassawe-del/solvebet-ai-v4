import 'package:flutter_test/flutter_test.dart';
import 'package:mathbetai/builder/accumulator_builder.dart';
import 'package:mathbetai/capital/capital.dart';
import 'package:mathbetai/capital/simulation.dart';
import 'package:mathbetai/domain/audit.dart';
import 'package:mathbetai/domain/enums.dart';
import 'package:mathbetai/domain/market.dart';
import 'package:mathbetai/domain/selection.dart';
import 'package:mathbetai/engine/kings_visa_engine.dart';

import 'support/synthetic.dart';

BuilderCandidate cand(int id, String home, String away, double odds, FinalVerdict v,
    {double score = 80, String league = 'SYN League', MarketSpec market = noThreeInARow}) {
  final s = Selection(
    id: id,
    homeTeam: home,
    awayTeam: away,
    league: league,
    kickoff: testKickoff,
    market: market,
    odds: odds,
  );
  final base = KingsVisaEngine(clock: () => testNow).audit(passingSelection());
  final r = AuditReport(
    selectionId: id,
    createdAt: testNow,
    visaA: base.visaA,
    visaB: base.visaB,
    visaC: base.visaC,
    visaD: base.visaD,
    verdict: v,
    failureCondition: '',
    failureEvidence: '',
    primaryRisk: '',
    reasoning: '',
    score: EvidenceScore(total: score, components: const {}, weights: const {}),
  );
  return BuilderCandidate(s, r);
}

void main() {
  final b = AccumulatorBuilder();

  group('KING\'S BUILDER', () {
    test('WATCH, INCOMPLETE and REJECTED selections are removed', () {
      final res = b.build([
        cand(1, 'SYN A', 'SYN B', 1.5, FinalVerdict.approved, league: 'L1'),
        cand(2, 'SYN C', 'SYN D', 1.5, FinalVerdict.watch, league: 'L2'),
        cand(3, 'SYN E', 'SYN F', 1.5, FinalVerdict.incomplete, league: 'L3'),
        cand(4, 'SYN G', 'SYN H', 1.5, FinalVerdict.rejected, league: 'L4'),
      ], const BuilderRequest(targetOdds: 1.4));
      expect(res.best!.legs.map((l) => l.selection.id), [1]);
      expect(res.excluded.where((e) => e.reason.startsWith('WATCH')).length, 1);
      expect(res.excluded.length, 3);
    });

    test('combined odds = product of decimal odds', () {
      final res = b.build([
        cand(1, 'SYN A', 'SYN B', 1.5, FinalVerdict.approved, league: 'L1'),
        cand(2, 'SYN C', 'SYN D', 2.0, FinalVerdict.approved, league: 'L2'),
      ], const BuilderRequest(targetOdds: 3.0));
      expect(res.targetReached, isTrue);
      expect(res.best!.combinedOdds, closeTo(3.0, 1e-9));
    });

    test('target is not forced when insufficient qualifying selections exist', () {
      final res = b.build([
        cand(1, 'SYN A', 'SYN B', 1.3, FinalVerdict.approved, league: 'L1'),
        cand(2, 'SYN C', 'SYN D', 1.4, FinalVerdict.approved, league: 'L2'),
        cand(3, 'SYN E', 'SYN F', 20, FinalVerdict.watch, league: 'L3'),
      ], const BuilderRequest(targetOdds: 100));
      expect(res.targetReached, isFalse);
      expect(res.best!.combinedOdds, closeTo(1.82, 1e-9));
      expect(res.message, contains('NOT reachable'));
    });

    test('no approved selections → insufficient evidence', () {
      final res = b.build([cand(1, 'SYN A', 'SYN B', 1.5, FinalVerdict.watch)], const BuilderRequest(targetOdds: 2));
      expect(res.best, isNull);
      expect(res.message, contains('Insufficient evidence'));
    });

    test('shared match exposure keeps only the strongest leg per fixture', () {
      final res = b.build([
        cand(1, 'SYN A', 'SYN B', 1.5, FinalVerdict.approved, score: 70),
        cand(2, 'SYN A', 'SYN B', 1.6, FinalVerdict.approved, score: 90,
            market: const MarketSpec(type: MarketType.btts, pick: 'no')),
      ], const BuilderRequest(targetOdds: 1.2));
      expect(res.best!.legs.single.selection.id, 2);
      expect(res.excluded.single.reason, contains('shared match exposure'));
    });

    test('correlation / common-factor warnings', () {
      final legs = [
        cand(1, 'SYN A', 'SYN B', 1.3, FinalVerdict.approved, league: 'L1'),
        cand(2, 'SYN C', 'SYN D', 1.3, FinalVerdict.approved, league: 'L1'),
        cand(3, 'SYN E', 'SYN A', 1.3, FinalVerdict.approved, league: 'L2'),
      ];
      final w = exposureWarnings(legs);
      expect(w.any((x) => x.contains('Same-league')), isTrue);
      expect(w.any((x) => x.contains('Common-factor')), isTrue);
      expect(w.any((x) => x.contains('"syn a"')), isTrue);
    });

    test('league concentration limit is a hard constraint', () {
      final res = b.build([
        for (var i = 0; i < 4; i++) cand(i, 'SYN H$i', 'SYN A$i', 1.5, FinalVerdict.approved, league: 'L1'),
      ], const BuilderRequest(targetOdds: 1000, maxPerLeague: 2));
      expect(res.best!.legs.length, 2);
    });
  });

  group('CAPITAL CONTROL', () {
    final t0 = DateTime.utc(2026, 11, 1, 10);
    Bet bet(int d, double odds, double stake, BetStatus st) => Bet(
        createdAt: t0.add(Duration(days: d)), label: 'b', odds: odds, stake: stake, status: st,
        settledAt: t0.add(Duration(days: d, hours: 3)));

    test('P/L, yield, ROI, streaks and drawdown', () {
      final bets = [
        bet(0, 2.0, 10000, BetStatus.won), // +10000
        bet(1, 1.5, 10000, BetStatus.lost), // -10000
        bet(2, 1.5, 10000, BetStatus.lost), // -10000
        bet(3, 3.0, 5000, BetStatus.voided), // 0
        bet(4, 1.8, 10000, BetStatus.won), // +8000
      ];
      final m = CapitalEngine.compute(bets, const CapitalSettings(), nowUtc: t0.add(const Duration(days: 10)));
      expect(m.realizedPnl, closeTo(-2000, 1e-6));
      expect(m.current, closeTo(498000, 1e-6));
      expect(m.turnover, 40000);
      expect(m.yieldPct, closeTo(-5, 1e-9));
      expect(m.roiPct, closeTo(-0.4, 1e-9));
      expect(m.wins, 2);
      expect(m.losses, 2);
      expect(m.voids, 1);
      expect(m.longestLossStreak, 2);
      expect(m.currentStreak, 1);
      expect(m.maxDrawdown, closeTo(20000 / 510000, 1e-9));
    });

    test('stake never exceeds user limits', () {
      const cfg = CapitalSettings(stakePercent: 10, maxStakePercent: 2);
      final m = CapitalEngine.compute([], cfg);
      final a = CapitalEngine.recommendStake(cfg, m);
      expect(a.stake, lessThanOrEqualTo(10000));
      expect(a.reasons.any((r) => r.contains('Capped')), isTrue);
    });

    test('daily loss limit blocks staking', () {
      final now = DateTime.now().toUtc();
      final bets = [Bet(createdAt: now, settledAt: now, label: 'x', odds: 2, stake: 30000, status: BetStatus.lost)];
      const cfg = CapitalSettings();
      final m = CapitalEngine.compute(bets, cfg, nowUtc: now);
      expect(CapitalEngine.recommendStake(cfg, m).blocked, isTrue);
    });

    test('daily target with little data is reported as insufficient, never as expected', () {
      final m = CapitalEngine.compute([bet(0, 2, 1000, BetStatus.won)], const CapitalSettings());
      final a = CapitalEngine.assessTarget(const CapitalSettings(), m);
      expect(a.verdict, TargetVerdict.insufficientData);
      expect(a.lines.first, contains('not an expected or guaranteed'));
    });

    test('simulation is deterministic and respects assumptions', () {
      const p = SimulationParams(odds: 1.5, winFrequency: 0.5, runs: 300, days: 30);
      final r1 = BankrollSimulator.run(p), r2 = BankrollSimulator.run(p);
      expect(r1.median, r2.median);
      expect(p.evPerUnit, closeTo(-0.25, 1e-9));
      expect(r1.median, lessThan(p.startBankroll)); // negative EV loses on median
      expect(r1.probLoss, greaterThan(0.9));
    });
  });
}
