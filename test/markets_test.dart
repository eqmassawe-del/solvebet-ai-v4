import 'package:flutter_test/flutter_test.dart';
import 'package:mathbetai/domain/enums.dart';
import 'package:mathbetai/domain/market.dart';
import 'package:mathbetai/domain/match_data.dart';
import 'package:mathbetai/engine/markets/markets.dart';

import 'support/synthetic.dart';

Settlement settle(MarketSpec s, HistoricalMatch m, [Side homeAs = Side.home]) =>
    MarketRegistry.of(s.type).settle(s, m, homeAs);

void main() {
  final m21 = hm(5, 'SYN A', 'SYN B', 2, 1, hh: 1, ha: 0, ch: 6, ca: 3, seq: '10H,50A,80H');
  final m00 = hm(5, 'SYN A', 'SYN B', 0, 0, hh: 0, ha: 0, seq: '-');
  final m11 = hm(5, 'SYN A', 'SYN B', 1, 1);

  test('every market type has its own evaluator', () {
    for (final t in MarketType.values) {
      expect(MarketRegistry.of(t).type, t);
    }
  });

  group('settlement logic', () {
    test('1X2', () {
      expect(settle(const MarketSpec(type: MarketType.matchResult, pick: 'home'), m21), Settlement.win);
      expect(settle(const MarketSpec(type: MarketType.matchResult, pick: 'draw'), m21), Settlement.lose);
      expect(settle(const MarketSpec(type: MarketType.matchResult, pick: 'away'), m21), Settlement.lose);
      // mirrored perspective: fixture home is played by the away side of this past match
      expect(settle(const MarketSpec(type: MarketType.matchResult, pick: 'home'), m21, Side.away), Settlement.lose);
    });
    test('Double chance', () {
      expect(settle(const MarketSpec(type: MarketType.doubleChance, pick: 'X2'), m11), Settlement.win);
      expect(settle(const MarketSpec(type: MarketType.doubleChance, pick: '12'), m11), Settlement.lose);
    });
    test('Over/Under incl. whole and quarter lines', () {
      expect(settle(const MarketSpec(type: MarketType.overUnderGoals, pick: 'over', line: 2.5), m21), Settlement.win);
      expect(settle(const MarketSpec(type: MarketType.overUnderGoals, pick: 'under', line: 2.5), m21), Settlement.lose);
      expect(settle(const MarketSpec(type: MarketType.overUnderGoals, pick: 'over', line: 3), m21), Settlement.push);
      expect(settle(const MarketSpec(type: MarketType.overUnderGoals, pick: 'over', line: 3.25), m21), Settlement.halfLoss);
      expect(settle(const MarketSpec(type: MarketType.overUnderGoals, pick: 'over', line: 2.75), m21), Settlement.halfWin);
    });
    test('First / second half goals need half-time data', () {
      const fh = MarketSpec(type: MarketType.firstHalfGoals, pick: 'over', line: 0.5);
      const sh = MarketSpec(type: MarketType.secondHalfGoals, pick: 'over', line: 1.5);
      expect(settle(fh, m21), Settlement.win);
      expect(settle(sh, m21), Settlement.win);
      expect(settle(fh, m11), Settlement.unknown);
    });
    test('BTTS', () {
      expect(settle(const MarketSpec(type: MarketType.btts, pick: 'yes'), m21), Settlement.win);
      expect(settle(const MarketSpec(type: MarketType.btts, pick: 'no'), m00), Settlement.win);
    });
    test('Team total and corners', () {
      expect(settle(const MarketSpec(type: MarketType.teamTotalGoals, side: Side.away, pick: 'under', line: 1.5), m21),
          Settlement.win);
      expect(settle(const MarketSpec(type: MarketType.totalCorners, pick: 'over', line: 8.5), m21), Settlement.win);
      expect(settle(const MarketSpec(type: MarketType.teamCorners, side: Side.home, pick: 'over', line: 6.5), m21),
          Settlement.lose);
      expect(settle(const MarketSpec(type: MarketType.totalCorners, pick: 'over', line: 8.5), m11), Settlement.unknown);
    });
    test('Asian handicap and Draw No Bet', () {
      expect(settle(const MarketSpec(type: MarketType.handicap, side: Side.home, line: -1.5), m21), Settlement.lose);
      expect(settle(const MarketSpec(type: MarketType.handicap, side: Side.home, line: -1), m21), Settlement.push);
      expect(settle(const MarketSpec(type: MarketType.handicap, side: Side.away, line: 1.5), m21), Settlement.win);
      expect(settle(const MarketSpec(type: MarketType.drawNoBet, side: Side.home), m11), Settlement.push);
    });
    test('Custom market uses user-recorded results only', () {
      const c = MarketSpec(type: MarketType.custom, customName: 'x');
      expect(settle(c, m21), Settlement.unknown);
    });
  });

  group('goal sequence calculations', () {
    test('longest runs per side', () {
      final r = SequenceMath.longestRuns(HistoricalMatch.parseSequence('5H,10H,20A,30H,40H,50H')!);
      expect(r[Side.home], 3);
      expect(r[Side.away], 1);
    });
    test('3-in-a-row detected from order, not from final score', () {
      // 3-1 can be HHHA (yes) or HAHH (no) — same final score.
      final yes = hm(1, 'SYN A', 'SYN B', 3, 1, seq: '5H,10H,20H,80A');
      final no = hm(1, 'SYN A', 'SYN B', 3, 1, seq: '5H,10A,20H,80H');
      final unknown = hm(1, 'SYN A', 'SYN B', 3, 1);
      expect(SequenceMath.anyTeamRun(yes, 3), isTrue);
      expect(SequenceMath.anyTeamRun(no, 3), isFalse);
      expect(SequenceMath.anyTeamRun(unknown, 3), isNull);
      expect(settle(noThreeInARow, unknown), Settlement.unknown);
    });
    test('logically certain cases do not need the order', () {
      expect(SequenceMath.anyTeamRun(hm(1, 'SYN A', 'SYN B', 2, 2), 3), isFalse);
      expect(SequenceMath.anyTeamRun(hm(1, 'SYN A', 'SYN B', 4, 0), 3), isTrue);
    });
    test('inconsistent sequence is rejected (UNKNOWN)', () {
      final bad = hm(1, 'SYN A', 'SYN B', 3, 1, seq: '5H,10H');
      expect(bad.hasValidSequence, isFalse);
      expect(SequenceMath.anyTeamRun(bad, 3), isNull);
    });
    test('team consecutive goals', () {
      const spec = MarketSpec(type: MarketType.teamConsecutiveGoals, side: Side.home, pick: 'yes');
      expect(settle(spec, hm(1, 'SYN A', 'SYN B', 2, 1, seq: '5H,10A,80H')), Settlement.lose);
      expect(settle(spec, hm(1, 'SYN A', 'SYN B', 2, 1, seq: '5H,10H,80A')), Settlement.win);
    });
    test('parser rejects malformed or out-of-order tokens', () {
      expect(() => HistoricalMatch.parseSequence('5X'), throwsFormatException);
      expect(() => HistoricalMatch.parseSequence('50H,10A'), throwsFormatException);
      expect(HistoricalMatch.parseSequence(''), isNull);
      expect(HistoricalMatch.parseSequence('-'), isEmpty);
    });
  });

  test('spec validation flags incomplete definitions', () {
    expect(MarketRegistry.of(MarketType.overUnderGoals).validate(const MarketSpec(type: MarketType.overUnderGoals)).ok,
        isFalse);
    expect(MarketRegistry.of(MarketType.handicap).validate(const MarketSpec(type: MarketType.handicap, side: Side.home, line: -1.3)).ok,
        isFalse);
  });
}
