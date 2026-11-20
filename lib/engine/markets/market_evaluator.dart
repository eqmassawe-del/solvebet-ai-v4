import '../../domain/enums.dart';
import '../../domain/market.dart';
import '../../domain/match_data.dart';
import '../../domain/selection.dart';

/// Data fields a market needs in each historical observation.
enum EvidenceField { fullTime, halfTime, goalSequence, corners, userSettlement }

/// Template for a market-specific stress scenario (VISA D).
class StressTemplate {
  const StressTemplate(this.kind, this.title, this.description, this.relevance, this.pathway);
  final ScenarioKind kind;
  final String title;
  final String description;
  final String relevance;
  final String pathway;

  StressScenario toScenario() => StressScenario(
        kind: kind,
        title: title,
        description: description,
        relevance: relevance,
        pathway: pathway,
        origin: DataOrigin.engineDerived,
      );
}

/// Result of validating a market specification (used by VISA A).
class SpecValidation {
  const SpecValidation(this.ok, this.problems);
  final bool ok;
  final List<String> problems;
}

/// Base class for all market evaluators.
///
/// Historical observations are settled with a `homeAs` mapping: in a past
/// match, `homeAs` is the side that stands in for the audited fixture's HOME
/// team. For the home team's own history that is simply the side the home team
/// played on. For the away team's history it is the side of the away team's
/// *opponent* – so a "Home win" selection fails in the away team's history
/// whenever the away team avoided defeat.
abstract class MarketEvaluator {
  const MarketEvaluator();

  MarketType get type;

  Set<EvidenceField> requiredFields(MarketSpec s);

  SpecValidation validate(MarketSpec s);

  /// Human readable selection label, e.g. "Over 2.5 goals".
  String describe(MarketSpec s, String home, String away);

  /// Exact settlement rule.
  String winCondition(MarketSpec s, String home, String away);

  /// The specific event that would cause the selection to fail.
  String failCondition(MarketSpec s, String home, String away);

  /// Settles the market in a historical observation.
  Settlement settle(MarketSpec s, HistoricalMatch m, Side homeAs);

  /// Safety margin (positive = cushion before failure). `null` when the
  /// market has no meaningful margin or the data is missing.
  double? margin(MarketSpec s, HistoricalMatch m, Side homeAs) => null;

  List<StressTemplate> stressTemplates(MarketSpec s, String home, String away);

  // ---- helpers ----
  static Side mapSide(Side fixtureSide, Side homeAs) =>
      fixtureSide == Side.home ? homeAs : homeAs.other;

  static String lineLabel(double? l) {
    if (l == null) return '?';
    return l == l.roundToDouble() ? l.toStringAsFixed(0) : l.toString();
  }

  /// Over/under settlement for a value against a line, including Asian
  /// quarter lines (e.g. 2.25 → half on 2.0, half on 2.5).
  static Settlement overUnder(num value, double line, bool over) {
    final frac = (line * 4).round() % 2 == 1; // quarter line
    if (frac) {
      final a = overUnder(value, line - 0.25, over);
      final b = overUnder(value, line + 0.25, over);
      return combineHalves(a, b);
    }
    final diff = over ? value - line : line - value;
    if (diff > 0) return Settlement.win;
    if (diff == 0) return Settlement.push;
    return Settlement.lose;
  }

  static Settlement combineHalves(Settlement a, Settlement b) {
    if (a == b) return a;
    final set = {a, b};
    if (set.contains(Settlement.win) && set.contains(Settlement.push)) return Settlement.halfWin;
    if (set.contains(Settlement.lose) && set.contains(Settlement.push)) return Settlement.halfLoss;
    // win + lose cannot happen for adjacent half lines; be conservative.
    return Settlement.halfLoss;
  }

  static bool validLine(double? l, {bool allowQuarter = true}) {
    if (l == null) return false;
    final q = l * 4;
    if ((q - q.round()).abs() > 1e-9) return false;
    if (!allowQuarter && q.round() % 2 == 1) return false;
    return true;
  }
}

/// Common stress templates reused by several markets.
class CommonStress {
  static StressTemplate redCard(String relevance, String pathway) => StressTemplate(
        ScenarioKind.earlyRedCard,
        'Early red card',
        'A player is sent off in the first 30 minutes.',
        relevance,
        pathway,
      );

  static StressTemplate earlyGoal(String relevance, String pathway) => StressTemplate(
        ScenarioKind.earlyGoal,
        'Early goal changes tactics',
        'A goal inside the first 15 minutes forces one side to open up or sit deep.',
        relevance,
        pathway,
      );

  static StressTemplate injury(String relevance, String pathway) => StressTemplate(
        ScenarioKind.keyPlayerInjury,
        'First-half injury to a key player',
        'A key attacker or defender is forced off before half-time.',
        relevance,
        pathway,
      );

  static StressTemplate rotation(String relevance, String pathway) => StressTemplate(
        ScenarioKind.unexpectedRotation,
        'Unexpected rotation',
        'The announced XI differs materially from the expected first-choice XI.',
        relevance,
        pathway,
      );

  static StressTemplate stronger(String relevance, String pathway) => StressTemplate(
        ScenarioKind.strongerOpponent,
        'Stronger-than-expected opponent',
        'The opponent performs well above its recent level.',
        relevance,
        pathway,
      );

  static StressTemplate collapse(String relevance, String pathway) => StressTemplate(
        ScenarioKind.defensiveCollapse,
        'Defensive collapse',
        'One defence concedes repeatedly in a short spell.',
        relevance,
        pathway,
      );

  static StressTemplate lateSurge(String relevance, String pathway) => StressTemplate(
        ScenarioKind.lateSurge,
        'Late attacking surge',
        'A trailing side commits bodies forward after 75 minutes.',
        relevance,
        pathway,
      );

  static StressTemplate lowProb(String relevance, String pathway) => StressTemplate(
        ScenarioKind.lowProbabilityState,
        'Low-probability damaging match state',
        'An unusual but realistic sequence of events (e.g. own goal + penalty).',
        relevance,
        pathway,
      );
}
