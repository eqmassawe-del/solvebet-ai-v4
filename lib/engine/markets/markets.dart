import '../../domain/enums.dart';
import '../../domain/market.dart';
import '../../domain/match_data.dart';
import 'market_evaluator.dart';

typedef _ME = MarketEvaluator;

String _sideName(Side? s, String home, String away) =>
    s == null ? '?' : (s == Side.home ? home : away);

bool _isOU(String p) => p == 'over' || p == 'under';
bool _isYN(String p) => p == 'yes' || p == 'no';

// ---------------------------------------------------------------- 1X2 -----
class MatchResultEvaluator extends MarketEvaluator {
  const MatchResultEvaluator();
  @override
  MarketType get type => MarketType.matchResult;
  @override
  Set<EvidenceField> requiredFields(MarketSpec s) => {EvidenceField.fullTime};
  @override
  SpecValidation validate(MarketSpec s) {
    final ok = ['home', 'draw', 'away'].contains(s.pick);
    return SpecValidation(ok, ok ? [] : ['1X2 pick must be home, draw or away.']);
  }

  @override
  String describe(MarketSpec s, String h, String a) => switch (s.pick) {
        'home' => '1X2: $h to win',
        'away' => '1X2: $a to win',
        _ => '1X2: Draw',
      };
  @override
  String winCondition(MarketSpec s, String h, String a) => switch (s.pick) {
        'home' => '$h scores more goals than $a after 90 minutes + stoppage time.',
        'away' => '$a scores more goals than $h after 90 minutes + stoppage time.',
        _ => 'Both teams score the same number of goals after 90 minutes + stoppage time.',
      };
  @override
  String failCondition(MarketSpec s, String h, String a) => switch (s.pick) {
        'home' => '$h fails to win (draw or $a win).',
        'away' => '$a fails to win (draw or $h win).',
        _ => 'Either team wins.',
      };
  @override
  Settlement settle(MarketSpec s, HistoricalMatch m, Side homeAs) {
    if (!m.hasFullTime) return Settlement.unknown;
    final h = m.goalsFor(homeAs)!, a = m.goalsFor(homeAs.other)!;
    final won = switch (s.pick) { 'home' => h > a, 'away' => a > h, _ => h == a };
    return won ? Settlement.win : Settlement.lose;
  }

  @override
  double? margin(MarketSpec s, HistoricalMatch m, Side homeAs) {
    if (!m.hasFullTime || s.pick == 'draw') return null;
    final h = m.goalsFor(homeAs)!, a = m.goalsFor(homeAs.other)!;
    return (s.pick == 'home' ? h - a : a - h).toDouble();
  }

  @override
  List<StressTemplate> stressTemplates(MarketSpec s, String h, String a) {
    final team = s.pick == 'away' ? a : h;
    if (s.pick == 'draw') {
      return [
        CommonStress.earlyGoal('A single goal ends the draw unless answered.', 'One goal with no reply settles the bet as lost.'),
        CommonStress.redCard('A sending-off unbalances the match.', 'The 11-man side gains control and wins.'),
        CommonStress.lateSurge('Late pressure from either side.', 'A late winner turns a draw into a loss.'),
      ];
    }
    return [
      CommonStress.redCard('A $team red card removes the edge required to win.', '$team plays with 10 and fails to win.'),
      CommonStress.earlyGoal('Conceding first forces $team to chase.', 'Opponent leads early and defends a low block.'),
      CommonStress.injury('Losing a key $team attacker reduces chance creation.', '$team cannot break the opponent down.'),
      CommonStress.rotation('$team rotating weakens the expected edge.', 'Weakened XI draws or loses.'),
      CommonStress.stronger('Opponent outperforms recent level.', 'Opponent takes points.'),
    ];
  }
}

// ------------------------------------------------------- Double chance -----
class DoubleChanceEvaluator extends MarketEvaluator {
  const DoubleChanceEvaluator();
  @override
  MarketType get type => MarketType.doubleChance;
  @override
  Set<EvidenceField> requiredFields(MarketSpec s) => {EvidenceField.fullTime};
  @override
  SpecValidation validate(MarketSpec s) {
    final ok = ['1X', 'X2', '12'].contains(s.pick);
    return SpecValidation(ok, ok ? [] : ['Double chance pick must be 1X, X2 or 12.']);
  }

  @override
  String describe(MarketSpec s, String h, String a) => switch (s.pick) {
        '1X' => 'Double Chance: $h or Draw',
        'X2' => 'Double Chance: Draw or $a',
        _ => 'Double Chance: $h or $a (no draw)',
      };
  @override
  String winCondition(MarketSpec s, String h, String a) => switch (s.pick) {
        '1X' => '$h wins or the match is drawn (90 min).',
        'X2' => '$a wins or the match is drawn (90 min).',
        _ => 'Either team wins (90 min).',
      };
  @override
  String failCondition(MarketSpec s, String h, String a) => switch (s.pick) {
        '1X' => '$a wins.',
        'X2' => '$h wins.',
        _ => 'The match ends in a draw.',
      };
  @override
  Settlement settle(MarketSpec s, HistoricalMatch m, Side homeAs) {
    if (!m.hasFullTime) return Settlement.unknown;
    final h = m.goalsFor(homeAs)!, a = m.goalsFor(homeAs.other)!;
    final won = switch (s.pick) { '1X' => h >= a, 'X2' => a >= h, _ => h != a };
    return won ? Settlement.win : Settlement.lose;
  }

  @override
  double? margin(MarketSpec s, HistoricalMatch m, Side homeAs) {
    if (!m.hasFullTime || s.pick == '12') return null;
    final h = m.goalsFor(homeAs)!, a = m.goalsFor(homeAs.other)!;
    return (s.pick == '1X' ? h - a : a - h).toDouble() + 1; // 0 = lost by one
  }

  @override
  List<StressTemplate> stressTemplates(MarketSpec s, String h, String a) {
    final covered = s.pick == '1X' ? h : (s.pick == 'X2' ? a : 'either side');
    return [
      CommonStress.redCard('A $covered red card exposes it to defeat.', 'Opponent exploits the extra player and wins.'),
      CommonStress.earlyGoal('Conceding early forces $covered to chase.', 'Counter-attacks extend the deficit.'),
      CommonStress.collapse('A short collapse produces a multi-goal defeat.', 'Opponent wins.'),
      CommonStress.stronger('Opponent outperforms recent level.', 'Opponent wins.'),
    ];
  }
}

// ---------------------------------------------- Over/Under goals (FT/1H/2H) -
class GoalsOverUnderEvaluator extends MarketEvaluator {
  const GoalsOverUnderEvaluator(this.type);
  @override
  final MarketType type;

  String get _period => switch (type) {
        MarketType.firstHalfGoals => 'first-half',
        MarketType.secondHalfGoals => 'second-half',
        _ => 'full-time',
      };

  @override
  Set<EvidenceField> requiredFields(MarketSpec s) => switch (type) {
        MarketType.firstHalfGoals => {EvidenceField.halfTime},
        MarketType.secondHalfGoals => {EvidenceField.fullTime, EvidenceField.halfTime},
        _ => {EvidenceField.fullTime},
      };
  @override
  SpecValidation validate(MarketSpec s) {
    final p = <String>[];
    if (!_isOU(s.pick)) p.add('Pick must be over or under.');
    if (!_ME.validLine(s.line) || (s.line ?? -1) < 0) p.add('A valid goal line (e.g. 2.5) is required.');
    return SpecValidation(p.isEmpty, p);
  }

  @override
  String describe(MarketSpec s, String h, String a) =>
      '${s.pick == 'over' ? 'Over' : 'Under'} ${_ME.lineLabel(s.line)} $_period goals';
  @override
  String winCondition(MarketSpec s, String h, String a) =>
      'Total $_period goals (both teams) ${s.pick == 'over' ? 'exceed' : 'stay below'} ${_ME.lineLabel(s.line)}. Whole lines refund on exact hit; quarter lines split the stake.';
  @override
  String failCondition(MarketSpec s, String h, String a) => s.pick == 'over'
      ? 'Fewer than ${((s.line ?? 0).floor() + 1)} $_period goals are scored.'
      : '${((s.line ?? 0).floor() + 1)} or more $_period goals are scored.';

  int? _value(HistoricalMatch m) => switch (type) {
        MarketType.firstHalfGoals => m.hasHalfTime ? m.htHome! + m.htAway! : null,
        MarketType.secondHalfGoals =>
          (m.hasHalfTime && m.hasFullTime) ? m.totalGoals! - m.htHome! - m.htAway! : null,
        _ => m.totalGoals,
      };

  @override
  Settlement settle(MarketSpec s, HistoricalMatch m, Side homeAs) {
    final v = _value(m);
    if (v == null || s.line == null) return Settlement.unknown;
    return _ME.overUnder(v, s.line!, s.pick == 'over');
  }

  @override
  double? margin(MarketSpec s, HistoricalMatch m, Side homeAs) {
    final v = _value(m);
    if (v == null || s.line == null) return null;
    return s.pick == 'over' ? v - s.line! : s.line! - v;
  }

  @override
  List<StressTemplate> stressTemplates(MarketSpec s, String h, String a) {
    if (s.pick == 'under') {
      return [
        CommonStress.earlyGoal('An early goal opens the game and forces the trailing side forward.', 'Open match produces goals beyond the line.'),
        CommonStress.redCard('A sending-off creates space and one-way traffic.', 'The 11-man side scores repeatedly.'),
        CommonStress.collapse('One defence concedes in clusters.', 'Goal count exceeds the line.'),
        CommonStress.lateSurge('Late chasing leaves gaps at both ends.', 'Late goals breach the line.'),
        CommonStress.lowProb('Penalties / own goals add unplanned goals.', 'Line breached by low-quality goals.'),
      ];
    }
    return [
      CommonStress.redCard('A red card can trigger a deep defensive block.', 'Game stalls; too few goals.'),
      CommonStress.earlyGoal('An early lead may let the leader sit deep.', 'Game is managed; goal count stays low.'),
      CommonStress.injury('Losing a key attacker reduces chance creation.', 'Too few goals.'),
      CommonStress.rotation('Rotated attackers reduce goal threat.', 'Too few goals.'),
    ];
  }
}

// ---------------------------------------------------------------- BTTS -----
class BttsEvaluator extends MarketEvaluator {
  const BttsEvaluator();
  @override
  MarketType get type => MarketType.btts;
  @override
  Set<EvidenceField> requiredFields(MarketSpec s) => {EvidenceField.fullTime};
  @override
  SpecValidation validate(MarketSpec s) =>
      SpecValidation(_isYN(s.pick), _isYN(s.pick) ? [] : ['BTTS pick must be yes or no.']);
  @override
  String describe(MarketSpec s, String h, String a) => 'Both Teams To Score: ${s.pick.toUpperCase()}';
  @override
  String winCondition(MarketSpec s, String h, String a) => s.pick == 'yes'
      ? '$h and $a each score at least one goal (90 min).'
      : 'At least one of $h / $a fails to score (90 min).';
  @override
  String failCondition(MarketSpec s, String h, String a) =>
      s.pick == 'yes' ? 'Either team keeps a clean sheet.' : 'Both teams score.';
  @override
  Settlement settle(MarketSpec s, HistoricalMatch m, Side homeAs) {
    if (!m.hasFullTime) return Settlement.unknown;
    final both = m.ftHome! > 0 && m.ftAway! > 0;
    return (s.pick == 'yes') == both ? Settlement.win : Settlement.lose;
  }

  @override
  double? margin(MarketSpec s, HistoricalMatch m, Side homeAs) {
    if (!m.hasFullTime) return null;
    final mn = m.ftHome! < m.ftAway! ? m.ftHome! : m.ftAway!;
    // yes: weakest scorer's goals (0 = failure); no: goals the weaker side is from scoring.
    return s.pick == 'yes' ? mn.toDouble() - 0.5 : 0.5 - mn.toDouble();
  }

  @override
  List<StressTemplate> stressTemplates(MarketSpec s, String h, String a) => s.pick == 'no'
      ? [
          CommonStress.earlyGoal('Conceding early forces the weaker attack to commit.', 'Weaker side scores; both teams score.'),
          CommonStress.redCard('A red card can open the match.', 'Both sides score in a broken game.'),
          CommonStress.lowProb('Penalty or own goal gives a non-scoring side a goal.', 'BTTS lands by accident.'),
          CommonStress.lateSurge('Late pressure from the trailing side.', 'Consolation goal makes BTTS yes.'),
        ]
      : [
          CommonStress.redCard('A red card for one side cuts its attack.', 'Reduced side fails to score.'),
          CommonStress.injury('Losing a key striker.', 'One side fails to score.'),
          CommonStress.stronger('One defence performs above level.', 'Clean sheet.'),
          CommonStress.earlyGoal('Leader sits deep after an early goal.', 'Trailing side cannot score.'),
        ];
}

// ------------------------------------------------- Team total goals -------
class TeamTotalGoalsEvaluator extends MarketEvaluator {
  const TeamTotalGoalsEvaluator();
  @override
  MarketType get type => MarketType.teamTotalGoals;
  @override
  Set<EvidenceField> requiredFields(MarketSpec s) => {EvidenceField.fullTime};
  @override
  SpecValidation validate(MarketSpec s) {
    final p = <String>[];
    if (s.side == null) p.add('Select the team (home/away).');
    if (!_isOU(s.pick)) p.add('Pick must be over or under.');
    if (!_ME.validLine(s.line) || (s.line ?? -1) < 0) p.add('A valid goal line is required.');
    return SpecValidation(p.isEmpty, p);
  }

  @override
  String describe(MarketSpec s, String h, String a) =>
      '${_sideName(s.side, h, a)} ${s.pick == 'over' ? 'Over' : 'Under'} ${_ME.lineLabel(s.line)} goals';
  @override
  String winCondition(MarketSpec s, String h, String a) =>
      '${_sideName(s.side, h, a)} scores ${s.pick == 'over' ? 'more' : 'fewer'} than ${_ME.lineLabel(s.line)} goals (90 min).';
  @override
  String failCondition(MarketSpec s, String h, String a) => s.pick == 'over'
      ? '${_sideName(s.side, h, a)} scores ${(s.line ?? 0).floor()} or fewer goals.'
      : '${_sideName(s.side, h, a)} scores ${(s.line ?? 0).floor() + 1} or more goals.';
  @override
  Settlement settle(MarketSpec s, HistoricalMatch m, Side homeAs) {
    if (!m.hasFullTime || s.side == null || s.line == null) return Settlement.unknown;
    final g = m.goalsFor(_ME.mapSide(s.side!, homeAs))!;
    return _ME.overUnder(g, s.line!, s.pick == 'over');
  }

  @override
  double? margin(MarketSpec s, HistoricalMatch m, Side homeAs) {
    if (!m.hasFullTime || s.side == null || s.line == null) return null;
    final g = m.goalsFor(_ME.mapSide(s.side!, homeAs))!;
    return s.pick == 'over' ? g - s.line! : s.line! - g;
  }

  @override
  List<StressTemplate> stressTemplates(MarketSpec s, String h, String a) {
    final t = _sideName(s.side, h, a);
    return s.pick == 'under'
        ? [
            CommonStress.redCard('An opponent red card gives $t space.', '$t scores beyond the line.'),
            CommonStress.collapse('Opponent defence collapses.', '$t exceeds the line.'),
            CommonStress.lowProb('Penalties inflate $t goals.', 'Line breached.'),
          ]
        : [
            CommonStress.redCard('A $t red card limits its attack.', '$t falls short of the line.'),
            CommonStress.injury('A key $t attacker is lost.', '$t falls short.'),
            CommonStress.stronger('Opponent defends above its level.', '$t falls short.'),
            CommonStress.rotation('$t rotates attackers.', '$t falls short.'),
          ];
  }
}

// ------------------------------------------------------- Corners -----------
class CornersEvaluator extends MarketEvaluator {
  const CornersEvaluator(this.type);
  @override
  final MarketType type;
  bool get _team => type == MarketType.teamCorners;

  @override
  Set<EvidenceField> requiredFields(MarketSpec s) => {EvidenceField.corners};
  @override
  SpecValidation validate(MarketSpec s) {
    final p = <String>[];
    if (_team && s.side == null) p.add('Select the team (home/away).');
    if (!_isOU(s.pick)) p.add('Pick must be over or under.');
    if (!_ME.validLine(s.line) || (s.line ?? -1) < 0) p.add('A valid corner line is required.');
    return SpecValidation(p.isEmpty, p);
  }

  String _who(MarketSpec s, String h, String a) => _team ? '${_sideName(s.side, h, a)} ' : 'Total ';
  @override
  String describe(MarketSpec s, String h, String a) =>
      '${_who(s, h, a)}corners ${s.pick == 'over' ? 'Over' : 'Under'} ${_ME.lineLabel(s.line)}';
  @override
  String winCondition(MarketSpec s, String h, String a) =>
      '${_who(s, h, a)}corners (90 min) ${s.pick == 'over' ? 'exceed' : 'stay below'} ${_ME.lineLabel(s.line)}.';
  @override
  String failCondition(MarketSpec s, String h, String a) => s.pick == 'over'
      ? '${_who(s, h, a)}corners are ${(s.line ?? 0).floor()} or fewer.'
      : '${_who(s, h, a)}corners reach ${(s.line ?? 0).floor() + 1} or more.';

  int? _value(MarketSpec s, HistoricalMatch m, Side homeAs) {
    if (!m.hasCorners) return null;
    if (!_team) return m.cornersHome! + m.cornersAway!;
    if (s.side == null) return null;
    return m.cornersFor(_ME.mapSide(s.side!, homeAs));
  }

  @override
  Settlement settle(MarketSpec s, HistoricalMatch m, Side homeAs) {
    final v = _value(s, m, homeAs);
    if (v == null || s.line == null) return Settlement.unknown;
    return _ME.overUnder(v, s.line!, s.pick == 'over');
  }

  @override
  double? margin(MarketSpec s, HistoricalMatch m, Side homeAs) {
    final v = _value(s, m, homeAs);
    if (v == null || s.line == null) return null;
    return s.pick == 'over' ? v - s.line! : s.line! - v;
  }

  @override
  List<StressTemplate> stressTemplates(MarketSpec s, String h, String a) => [
        CommonStress.earlyGoal('Game state changes which side attacks wide.',
            s.pick == 'over' ? 'Leader sits deep and corner volume drops.' : 'Trailing side bombards the box, inflating corners.'),
        CommonStress.redCard('A red card produces one-way pressure.',
            s.pick == 'over' ? 'Low-tempo game with few set pieces.' : 'Sustained siege raises corner count.'),
        CommonStress.lateSurge('Late pressure generates set pieces.',
            s.pick == 'over' ? 'Not enough time to reach the line.' : 'Late corners breach the line.'),
        CommonStress.rotation('Rotated wide players change crossing volume.', 'Corner count deviates from history.'),
      ];
}

// ------------------------------------------------------ Asian handicap ----
class HandicapEvaluator extends MarketEvaluator {
  const HandicapEvaluator();
  @override
  MarketType get type => MarketType.handicap;
  @override
  Set<EvidenceField> requiredFields(MarketSpec s) => {EvidenceField.fullTime};
  @override
  SpecValidation validate(MarketSpec s) {
    final p = <String>[];
    if (s.side == null) p.add('Select the team taking the handicap.');
    if (!_ME.validLine(s.line)) p.add('Handicap line must be a multiple of 0.25 (e.g. -1.5, +0.25).');
    return SpecValidation(p.isEmpty, p);
  }

  String _l(double? l) => l == null ? '?' : (l > 0 ? '+${_ME.lineLabel(l)}' : _ME.lineLabel(l));
  @override
  String describe(MarketSpec s, String h, String a) => 'AH ${_sideName(s.side, h, a)} ${_l(s.line)}';
  @override
  String winCondition(MarketSpec s, String h, String a) =>
      '${_sideName(s.side, h, a)} goal difference plus ${_l(s.line)} is positive (90 min). Zero refunds; quarter lines split.';
  @override
  String failCondition(MarketSpec s, String h, String a) =>
      '${_sideName(s.side, h, a)} goal difference plus ${_l(s.line)} is negative.';
  @override
  Settlement settle(MarketSpec s, HistoricalMatch m, Side homeAs) {
    if (!m.hasFullTime || s.side == null || s.line == null) return Settlement.unknown;
    final side = _ME.mapSide(s.side!, homeAs);
    final diff = m.goalsFor(side)! - m.goalsFor(side.other)!;
    return _ME.overUnder(diff, -s.line!, true);
  }

  @override
  double? margin(MarketSpec s, HistoricalMatch m, Side homeAs) {
    if (!m.hasFullTime || s.side == null || s.line == null) return null;
    final side = _ME.mapSide(s.side!, homeAs);
    return m.goalsFor(side)! - m.goalsFor(side.other)! + s.line!;
  }

  @override
  List<StressTemplate> stressTemplates(MarketSpec s, String h, String a) {
    final t = _sideName(s.side, h, a);
    return [
      CommonStress.redCard('A $t red card destroys the required margin.', '$t fails to cover.'),
      CommonStress.earlyGoal('An early lead may cause $t to manage the game.', 'Win by too few goals.'),
      CommonStress.lateSurge('Late opponent goal cuts the margin.', 'Handicap not covered.'),
      CommonStress.rotation('$t rotates after taking the lead.', 'Margin shrinks.'),
      CommonStress.stronger('Opponent tougher than recent form.', 'Handicap not covered.'),
    ];
  }
}

// ------------------------------------------------------- Draw no bet ------
class DrawNoBetEvaluator extends MarketEvaluator {
  const DrawNoBetEvaluator();
  @override
  MarketType get type => MarketType.drawNoBet;
  @override
  Set<EvidenceField> requiredFields(MarketSpec s) => {EvidenceField.fullTime};
  @override
  SpecValidation validate(MarketSpec s) => SpecValidation(
      s.side != null, s.side != null ? [] : ['Select the team for Draw No Bet.']);
  @override
  String describe(MarketSpec s, String h, String a) => 'Draw No Bet: ${_sideName(s.side, h, a)}';
  @override
  String winCondition(MarketSpec s, String h, String a) =>
      '${_sideName(s.side, h, a)} wins (90 min). A draw refunds the stake.';
  @override
  String failCondition(MarketSpec s, String h, String a) =>
      '${s.side == Side.home ? a : h} wins.';
  @override
  Settlement settle(MarketSpec s, HistoricalMatch m, Side homeAs) {
    if (!m.hasFullTime || s.side == null) return Settlement.unknown;
    final side = _ME.mapSide(s.side!, homeAs);
    final d = m.goalsFor(side)! - m.goalsFor(side.other)!;
    return d > 0 ? Settlement.win : (d == 0 ? Settlement.push : Settlement.lose);
  }

  @override
  double? margin(MarketSpec s, HistoricalMatch m, Side homeAs) {
    if (!m.hasFullTime || s.side == null) return null;
    final side = _ME.mapSide(s.side!, homeAs);
    return (m.goalsFor(side)! - m.goalsFor(side.other)!).toDouble();
  }

  @override
  List<StressTemplate> stressTemplates(MarketSpec s, String h, String a) {
    final t = _sideName(s.side, h, a);
    return [
      CommonStress.redCard('A $t red card exposes it to defeat.', 'Opponent wins.'),
      CommonStress.earlyGoal('$t concedes first.', 'Opponent defends lead.'),
      CommonStress.stronger('Opponent outperforms.', 'Opponent wins.'),
    ];
  }
}

// ----------------------------------------- Goal-sequence helpers -----------
class SequenceMath {
  /// Longest run of consecutive goals by the same side, per side.
  static Map<Side, int> longestRuns(List<GoalEvent> seq) {
    final best = {Side.home: 0, Side.away: 0};
    Side? cur;
    var run = 0;
    for (final g in seq) {
      if (g.side == cur) {
        run++;
      } else {
        cur = g.side;
        run = 1;
      }
      if (run > best[g.side]!) best[g.side] = run;
    }
    return best;
  }

  /// Whether *any* team scored [n] consecutive goals.
  /// Returns null when this cannot be determined without the goal order.
  ///
  /// The final score alone is only used where it makes the answer logically
  /// certain: if neither side scored n goals it cannot have happened; if one
  /// side scored ≥ n and the other none, it necessarily happened. Otherwise
  /// the order is required and its absence yields `null` (UNKNOWN).
  static bool? anyTeamRun(HistoricalMatch m, int n) {
    if (!m.hasFullTime) return null;
    final h = m.ftHome!, a = m.ftAway!;
    if (h < n && a < n) return false;
    if ((h >= n && a == 0) || (a >= n && h == 0)) return true;
    if (!m.hasValidSequence) return null;
    final r = longestRuns(m.goalSequence!);
    return r[Side.home]! >= n || r[Side.away]! >= n;
  }

  /// Whether [side] scored [n] consecutive goals (null = undeterminable).
  static bool? teamRun(HistoricalMatch m, Side side, int n) {
    if (!m.hasFullTime) return null;
    final own = m.goalsFor(side)!, opp = m.goalsFor(side.other)!;
    if (own < n) return false;
    if (opp == 0) return true;
    if (!m.hasValidSequence) return null;
    return longestRuns(m.goalSequence!)[side]! >= n;
  }
}

// ---------------------------------------- Any team to score 3 in a row ----
class AnyTeam3InARowEvaluator extends MarketEvaluator {
  const AnyTeam3InARowEvaluator();
  @override
  MarketType get type => MarketType.anyTeam3InARow;
  @override
  Set<EvidenceField> requiredFields(MarketSpec s) => {EvidenceField.fullTime, EvidenceField.goalSequence};
  @override
  SpecValidation validate(MarketSpec s) =>
      SpecValidation(_isYN(s.pick), _isYN(s.pick) ? [] : ['Pick must be yes or no.']);
  @override
  String describe(MarketSpec s, String h, String a) => 'Any Team To Score 3 in a Row: ${s.pick.toUpperCase()}';
  @override
  String winCondition(MarketSpec s, String h, String a) => s.pick == 'no'
      ? 'Neither $h nor $a scores three consecutive goals without the opponent scoring in between (90 min).'
      : 'Either team scores three consecutive goals without the opponent scoring in between (90 min).';
  @override
  String failCondition(MarketSpec s, String h, String a) => s.pick == 'no'
      ? 'Either team scores three goals in a row (e.g. 0-1, 0-2, 0-3 or 1-1, 2-1, 3-1, 4-1).'
      : 'No team ever strings three consecutive goals together.';
  @override
  Settlement settle(MarketSpec s, HistoricalMatch m, Side homeAs) {
    final happened = SequenceMath.anyTeamRun(m, 3);
    if (happened == null) return Settlement.unknown;
    return (s.pick == 'yes') == happened ? Settlement.win : Settlement.lose;
  }

  @override
  double? margin(MarketSpec s, HistoricalMatch m, Side homeAs) {
    if (!m.hasValidSequence) return null;
    final r = SequenceMath.longestRuns(m.goalSequence!);
    final mx = r.values.reduce((x, y) => x > y ? x : y);
    return s.pick == 'no' ? (3 - mx).toDouble() - 0.5 : mx - 2.5;
  }

  @override
  List<StressTemplate> stressTemplates(MarketSpec s, String h, String a) => s.pick == 'no'
      ? [
          CommonStress.redCard('A sending-off creates one-way traffic.', 'The 11-man side scores three unanswered goals.'),
          CommonStress.collapse('A defence concedes in a cluster.', 'Three consecutive goals by one team.'),
          CommonStress.earlyGoal('Early goal followed by a chasing side over-committing.', 'Leader scores again twice on the break.'),
          CommonStress.stronger('A heavily favoured side dominates.', 'Favourite wins 3-0 or better.'),
          CommonStress.lateSurge('Late goals when a match is already decided.', 'Run extended to three.'),
        ]
      : [
          CommonStress.earlyGoal('Balanced exchange of goals.', 'Scoring alternates; no run of three.'),
          CommonStress.redCard('Red card creates a low-scoring stalemate.', 'Too few goals for a run.'),
          CommonStress.stronger('Evenly matched sides.', 'No dominant spell.'),
        ];
}

// ------------------------------------------- Team consecutive goals -------
class TeamConsecutiveGoalsEvaluator extends MarketEvaluator {
  const TeamConsecutiveGoalsEvaluator();
  @override
  MarketType get type => MarketType.teamConsecutiveGoals;
  @override
  Set<EvidenceField> requiredFields(MarketSpec s) => {EvidenceField.fullTime, EvidenceField.goalSequence};
  @override
  SpecValidation validate(MarketSpec s) {
    final p = <String>[];
    if (s.side == null) p.add('Select the team.');
    if (!_isYN(s.pick)) p.add('Pick must be yes or no.');
    return SpecValidation(p.isEmpty, p);
  }

  @override
  String describe(MarketSpec s, String h, String a) =>
      '${_sideName(s.side, h, a)} To Score Consecutive Goals: ${s.pick.toUpperCase()}';
  @override
  String winCondition(MarketSpec s, String h, String a) => s.pick == 'yes'
      ? '${_sideName(s.side, h, a)} scores two goals in a row at some point (no opponent goal between).'
      : '${_sideName(s.side, h, a)} never scores two goals in a row.';
  @override
  String failCondition(MarketSpec s, String h, String a) => s.pick == 'yes'
      ? '${_sideName(s.side, h, a)} scores fewer than two goals, or its goals are always separated by opponent goals.'
      : '${_sideName(s.side, h, a)} scores two consecutive goals.';
  @override
  Settlement settle(MarketSpec s, HistoricalMatch m, Side homeAs) {
    if (s.side == null) return Settlement.unknown;
    final happened = SequenceMath.teamRun(m, _ME.mapSide(s.side!, homeAs), 2);
    if (happened == null) return Settlement.unknown;
    return (s.pick == 'yes') == happened ? Settlement.win : Settlement.lose;
  }

  @override
  List<StressTemplate> stressTemplates(MarketSpec s, String h, String a) {
    final t = _sideName(s.side, h, a);
    return s.pick == 'yes'
        ? [
            CommonStress.redCard('A $t red card limits its attack.', '$t scores fewer than two.'),
            CommonStress.stronger('Opponent defends well.', '$t scores at most once.'),
            CommonStress.injury('A key $t attacker is lost.', '$t scoring dries up.'),
          ]
        : [
            CommonStress.redCard('An opponent red card gives $t control.', '$t scores twice in succession.'),
            CommonStress.collapse('Opponent concedes in a cluster.', '$t scores consecutive goals.'),
          ];
  }
}

// -------------------------------------------------- Custom (user) ---------
class CustomMarketEvaluator extends MarketEvaluator {
  const CustomMarketEvaluator();
  @override
  MarketType get type => MarketType.custom;
  @override
  Set<EvidenceField> requiredFields(MarketSpec s) => {EvidenceField.userSettlement};
  @override
  SpecValidation validate(MarketSpec s) {
    final p = <String>[];
    if (s.customName.trim().isEmpty) p.add('Name the custom market.');
    if (s.customWinCondition.trim().length < 10) p.add('Define exactly when the selection WINS.');
    if (s.customFailCondition.trim().length < 10) p.add('Define exactly which event makes the selection LOSE.');
    return SpecValidation(p.isEmpty, p);
  }

  @override
  String describe(MarketSpec s, String h, String a) => 'Custom: ${s.customName}';
  @override
  String winCondition(MarketSpec s, String h, String a) => s.customWinCondition;
  @override
  String failCondition(MarketSpec s, String h, String a) => s.customFailCondition;
  @override
  Settlement settle(MarketSpec s, HistoricalMatch m, Side homeAs) => switch (m.marketResultOverride) {
        'win' => Settlement.win,
        'lose' => Settlement.lose,
        'void' => Settlement.push,
        _ => Settlement.unknown,
      };
  @override
  List<StressTemplate> stressTemplates(MarketSpec s, String h, String a) => [
        CommonStress.redCard('A red card changes the match structure.', 'Describe how this defeats: ${s.customFailCondition}'),
        CommonStress.earlyGoal('An early goal changes tactics.', 'Describe how this defeats the market.'),
        CommonStress.lowProb('Unusual match state.', 'Describe how this defeats the market.'),
      ];
}

/// Registry: one evaluator per market type.
class MarketRegistry {
  static const Map<MarketType, MarketEvaluator> _all = {
    MarketType.matchResult: MatchResultEvaluator(),
    MarketType.doubleChance: DoubleChanceEvaluator(),
    MarketType.overUnderGoals: GoalsOverUnderEvaluator(MarketType.overUnderGoals),
    MarketType.firstHalfGoals: GoalsOverUnderEvaluator(MarketType.firstHalfGoals),
    MarketType.secondHalfGoals: GoalsOverUnderEvaluator(MarketType.secondHalfGoals),
    MarketType.btts: BttsEvaluator(),
    MarketType.teamTotalGoals: TeamTotalGoalsEvaluator(),
    MarketType.totalCorners: CornersEvaluator(MarketType.totalCorners),
    MarketType.teamCorners: CornersEvaluator(MarketType.teamCorners),
    MarketType.handicap: HandicapEvaluator(),
    MarketType.drawNoBet: DrawNoBetEvaluator(),
    MarketType.anyTeam3InARow: AnyTeam3InARowEvaluator(),
    MarketType.teamConsecutiveGoals: TeamConsecutiveGoalsEvaluator(),
    MarketType.custom: CustomMarketEvaluator(),
  };

  static MarketEvaluator of(MarketType t) => _all[t]!;

  /// Binary markets with unambiguous settlement (preferred by the ranker).
  static bool isBinary(MarketSpec s) {
    switch (s.type) {
      case MarketType.btts:
      case MarketType.anyTeam3InARow:
      case MarketType.teamConsecutiveGoals:
      case MarketType.doubleChance:
        return true;
      case MarketType.overUnderGoals:
      case MarketType.firstHalfGoals:
      case MarketType.secondHalfGoals:
      case MarketType.teamTotalGoals:
      case MarketType.totalCorners:
      case MarketType.teamCorners:
      case MarketType.handicap:
        final l = s.line;
        return l != null && ((l * 2).round() % 2 == 1); // half lines only
      case MarketType.matchResult:
      case MarketType.drawNoBet:
      case MarketType.custom:
        return false;
    }
  }
}
