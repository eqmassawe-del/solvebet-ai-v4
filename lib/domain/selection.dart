import 'enums.dart';
import 'market.dart';
import 'match_data.dart';

/// VISA C structural factors. `mandatory` factors must be assessed with
/// written evidence before VISA C can PASS.
enum StructuralFactor {
  motivation('Team motivation', true),
  competitionImportance('Competition importance', false),
  rotation('Rotation potential', false),
  lineups('Starting line-ups (confirmed / uncertain)', true),
  injuriesSuspensions('Injuries & suspensions', true),
  tacticalMismatch('Tactical mismatch', false),
  pressingVulnerability('High press / defensive vulnerability', false),
  managerialChange('Recent managerial change', false),
  fixtureCongestion('Fixture congestion', false),
  homeAwayContext('Home/away context', false),
  redCardExposure('Red-card exposure (MANDATORY)', true),
  unusualPatterns('Unusual scoring / corner patterns', false),
  opponentThreats('Opponent-specific tactical threats', false);

  const StructuralFactor(this.title, this.mandatory);
  final String title;
  final bool mandatory;

  static StructuralFactor? tryParse(String? s) {
    for (final f in StructuralFactor.values) {
      if (f.name == s) return f;
    }
    return null;
  }
}

enum CheckStatus {
  notAssessed('NOT ASSESSED'),
  clear('CLEAR'),
  concern('CONCERN'),
  critical('CRITICAL');

  const CheckStatus(this.label);
  final String label;

  static CheckStatus parse(String? s) =>
      CheckStatus.values.firstWhere((e) => e.name == s, orElse: () => CheckStatus.notAssessed);
}

class StructuralCheck {
  const StructuralCheck({
    required this.factor,
    this.status = CheckStatus.notAssessed,
    this.evidence = '',
    this.uncertainty = '',
    this.origin = DataOrigin.userEntered,
  });

  final StructuralFactor factor;
  final CheckStatus status;
  final String evidence;
  final String uncertainty;
  final DataOrigin origin;

  StructuralCheck copyWith({
    CheckStatus? status,
    String? evidence,
    String? uncertainty,
    DataOrigin? origin,
  }) =>
      StructuralCheck(
        factor: factor,
        status: status ?? this.status,
        evidence: evidence ?? this.evidence,
        uncertainty: uncertainty ?? this.uncertainty,
        origin: origin ?? this.origin,
      );

  static List<StructuralCheck> defaults() =>
      StructuralFactor.values.map((f) => StructuralCheck(factor: f)).toList();
}

enum Severity {
  unassessed('UNASSESSED', 0),
  low('LOW', 1),
  medium('MEDIUM', 2),
  high('HIGH', 3),
  critical('CRITICAL', 4);

  const Severity(this.label, this.weight);
  final String label;
  final int weight;

  static Severity parse(String? s) =>
      Severity.values.firstWhere((e) => e.name == s, orElse: () => Severity.unassessed);
}

/// Kinds of stress scenario. Used to attach engine-derived evidence where
/// historical data allows it (e.g. how the market behaved in matches that had
/// a red card).
enum ScenarioKind {
  earlyRedCard,
  earlyGoal,
  keyPlayerInjury,
  unexpectedRotation,
  strongerOpponent,
  defensiveCollapse,
  lateSurge,
  lowProbabilityState,
  other;

  static ScenarioKind parse(String? s) =>
      ScenarioKind.values.firstWhere((e) => e.name == s, orElse: () => ScenarioKind.other);
}

class StressScenario {
  const StressScenario({
    required this.kind,
    required this.title,
    required this.description,
    required this.relevance,
    required this.pathway,
    this.evidence = '',
    this.severity = Severity.unassessed,
    this.evidenceSufficient,
    this.origin = DataOrigin.userEntered,
  });

  final ScenarioKind kind;
  final String title;
  final String description;

  /// Why the scenario matters for *this* market.
  final String relevance;

  /// How the scenario would cause the market to fail.
  final String pathway;

  /// Evidence supporting (or refuting) the plausibility of the scenario.
  final String evidence;
  final Severity severity;

  /// `null` = not stated; `false` = evidence insufficient to assess.
  final bool? evidenceSufficient;
  final DataOrigin origin;

  bool get assessed => severity != Severity.unassessed && evidenceSufficient != null;

  StressScenario copyWith({
    String? evidence,
    Severity? severity,
    bool? evidenceSufficient,
    bool clearSufficient = false,
  }) =>
      StressScenario(
        kind: kind,
        title: title,
        description: description,
        relevance: relevance,
        pathway: pathway,
        evidence: evidence ?? this.evidence,
        severity: severity ?? this.severity,
        evidenceSufficient: clearSufficient ? null : (evidenceSufficient ?? this.evidenceSufficient),
        origin: origin,
      );
}

/// A betting selection under audit.
class Selection {
  Selection({
    this.id,
    this.matchRef = '',
    required this.homeTeam,
    required this.awayTeam,
    this.league = '',
    this.country = '',
    this.kickoff,
    required this.market,
    this.odds,
    this.oddsSource = '',
    this.oddsUpdatedAt,
    this.dataUpdatedAt,
    this.origin = DataOrigin.userEntered,
    this.notes = '',
    List<HistoricalMatch>? homeHistory,
    List<HistoricalMatch>? awayHistory,
    List<StructuralCheck>? checks,
    List<StressScenario>? scenarios,
    this.actualOutcome,
    DateTime? createdAt,
  })  : homeHistory = homeHistory ?? [],
        awayHistory = awayHistory ?? [],
        checks = checks ?? StructuralCheck.defaults(),
        scenarios = scenarios ?? [],
        createdAt = createdAt ?? DateTime.now().toUtc();

  final int? id;

  /// External fixture id (provider) or empty for manual entries.
  final String matchRef;
  final String homeTeam;
  final String awayTeam;
  final String league;
  final String country;

  /// Kickoff instant (UTC). Displayed in Africa/Dar_es_Salaam time.
  final DateTime? kickoff;
  final MarketSpec market;
  final double? odds;
  final String oddsSource;
  final DateTime? oddsUpdatedAt;

  /// When the evidence (history / structural information) was last updated.
  final DateTime? dataUpdatedAt;
  final DataOrigin origin;
  final String notes;
  final List<HistoricalMatch> homeHistory;
  final List<HistoricalMatch> awayHistory;
  final List<StructuralCheck> checks;
  final List<StressScenario> scenarios;

  /// Recorded real-world settlement: 'won', 'lost', 'void' or null.
  final String? actualOutcome;
  final DateTime createdAt;

  String get matchLabel => '$homeTeam vs $awayTeam';

  String teamName(Side s) => s == Side.home ? homeTeam : awayTeam;

  StructuralCheck check(StructuralFactor f) =>
      checks.firstWhere((c) => c.factor == f, orElse: () => StructuralCheck(factor: f));

  Selection copyWith({
    int? id,
    String? matchRef,
    String? homeTeam,
    String? awayTeam,
    String? league,
    String? country,
    DateTime? kickoff,
    MarketSpec? market,
    double? odds,
    String? oddsSource,
    DateTime? oddsUpdatedAt,
    DateTime? dataUpdatedAt,
    DataOrigin? origin,
    String? notes,
    List<HistoricalMatch>? homeHistory,
    List<HistoricalMatch>? awayHistory,
    List<StructuralCheck>? checks,
    List<StressScenario>? scenarios,
    String? actualOutcome,
    bool clearOutcome = false,
  }) =>
      Selection(
        id: id ?? this.id,
        matchRef: matchRef ?? this.matchRef,
        homeTeam: homeTeam ?? this.homeTeam,
        awayTeam: awayTeam ?? this.awayTeam,
        league: league ?? this.league,
        country: country ?? this.country,
        kickoff: kickoff ?? this.kickoff,
        market: market ?? this.market,
        odds: odds ?? this.odds,
        oddsSource: oddsSource ?? this.oddsSource,
        oddsUpdatedAt: oddsUpdatedAt ?? this.oddsUpdatedAt,
        dataUpdatedAt: dataUpdatedAt ?? this.dataUpdatedAt,
        origin: origin ?? this.origin,
        notes: notes ?? this.notes,
        homeHistory: homeHistory ?? this.homeHistory,
        awayHistory: awayHistory ?? this.awayHistory,
        checks: checks ?? this.checks,
        scenarios: scenarios ?? this.scenarios,
        actualOutcome: clearOutcome ? null : (actualOutcome ?? this.actualOutcome),
        createdAt: createdAt,
      );
}
