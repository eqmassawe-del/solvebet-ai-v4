import 'enums.dart';

/// Supported football markets. Each has its own evaluator in
/// `lib/engine/markets/`.
enum MarketType {
  matchResult('1X2', 'Core'),
  doubleChance('Double Chance', 'Core'),
  overUnderGoals('Over/Under Goals', 'Core'),
  btts('Both Teams To Score', 'Core'),
  teamTotalGoals('Team Total Goals', 'Core'),
  totalCorners('Total Corners', 'Core'),
  teamCorners('Team Corners', 'Core'),
  handicap('Asian Handicap', 'Core'),
  anyTeam3InARow('Any Team To Score 3 in a Row', 'Special'),
  teamConsecutiveGoals('Team To Score Consecutive Goals', 'Special'),
  firstHalfGoals('First Half Goals O/U', 'Special'),
  secondHalfGoals('Second Half Goals O/U', 'Special'),
  drawNoBet('Draw No Bet', 'Special'),
  custom('User-Defined Market', 'Custom');

  const MarketType(this.title, this.group);
  final String title;
  final String group;

  static MarketType parse(String? s) =>
      MarketType.values.firstWhere((e) => e.name == s, orElse: () => MarketType.custom);
}

/// Precise market definition for a selection.
///
/// * `pick` holds the chosen outcome: `home`/`draw`/`away` (1X2),
///   `1X`/`X2`/`12` (double chance), `over`/`under`, or `yes`/`no`.
/// * `side` is the team the market refers to (fixture home or away) for
///   team-based markets (team totals, team corners, handicap, DNB,
///   consecutive goals).
/// * `line` is the goal/corner line or handicap.
class MarketSpec {
  const MarketSpec({
    required this.type,
    this.pick = '',
    this.side,
    this.line,
    this.customName = '',
    this.customWinCondition = '',
    this.customFailCondition = '',
  });

  final MarketType type;
  final String pick;
  final Side? side;
  final double? line;
  final String customName;
  final String customWinCondition;
  final String customFailCondition;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'pick': pick,
        'side': side?.name,
        'line': line,
        'customName': customName,
        'customWin': customWinCondition,
        'customFail': customFailCondition,
      };

  factory MarketSpec.fromJson(Map<String, dynamic> j) => MarketSpec(
        type: MarketType.parse(j['type'] as String?),
        pick: (j['pick'] as String?) ?? '',
        side: j['side'] == null ? null : Side.parse(j['side'] as String?),
        line: (j['line'] as num?)?.toDouble(),
        customName: (j['customName'] as String?) ?? '',
        customWinCondition: (j['customWin'] as String?) ?? '',
        customFailCondition: (j['customFail'] as String?) ?? '',
      );

  MarketSpec copyWith({
    MarketType? type,
    String? pick,
    Side? side,
    bool clearSide = false,
    double? line,
    bool clearLine = false,
    String? customName,
    String? customWinCondition,
    String? customFailCondition,
  }) =>
      MarketSpec(
        type: type ?? this.type,
        pick: pick ?? this.pick,
        side: clearSide ? null : (side ?? this.side),
        line: clearLine ? null : (line ?? this.line),
        customName: customName ?? this.customName,
        customWinCondition: customWinCondition ?? this.customWinCondition,
        customFailCondition: customFailCondition ?? this.customFailCondition,
      );
}

/// Settlement of a market in one historical observation.
enum Settlement {
  win,
  halfWin,
  push,
  halfLoss,
  lose,
  unknown;

  bool get isFailure => this == Settlement.lose || this == Settlement.halfLoss;
  bool get isValid => this != Settlement.unknown && this != Settlement.push;
}
