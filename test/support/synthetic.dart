// SYNTHETIC TEST DATASET — FOR AUTOMATED TESTS ONLY.
//
// Every team name is prefixed "SYN". None of this data describes real football
// matches, and it is never shipped to or displayed by the app. Records default
// to DataOrigin.userEntered only so the approval path can be exercised; a
// dedicated test asserts that DataOrigin.synthetic data is always rejected.
import 'package:mathbetai/domain/enums.dart';
import 'package:mathbetai/domain/market.dart';
import 'package:mathbetai/domain/match_data.dart';
import 'package:mathbetai/domain/selection.dart';
import 'package:mathbetai/engine/markets/markets.dart';

final testNow = DateTime.utc(2026, 11, 20, 12);
final testKickoff = DateTime.utc(2026, 11, 22, 13);

const synHome = 'SYN Alpha FC';
const synAway = 'SYN Beta United';

/// Builds a synthetic historical match `daysAgo` days before [testNow].
HistoricalMatch hm(
  int daysAgo,
  String home,
  String away,
  int? fh,
  int? fa, {
  String? seq,
  int? hh,
  int? ha,
  int? ch,
  int? ca,
  int rh = 0,
  int ra = 0,
  bool comparable = true,
  DataOrigin origin = DataOrigin.userEntered,
}) =>
    HistoricalMatch(
      date: testNow.subtract(Duration(days: daysAgo)),
      homeTeam: home,
      awayTeam: away,
      competition: 'SYN League',
      ftHome: fh,
      ftAway: fa,
      htHome: hh,
      htAway: ha,
      goalSequence: seq == null ? null : HistoricalMatch.parseSequence(seq),
      cornersHome: ch,
      cornersAway: ca,
      redCardsHome: rh,
      redCardsAway: ra,
      comparable: comparable,
      source: 'synthetic test fixture',
      origin: origin,
    );

/// Ten low-event matches for a team: no team ever scores 3 in a row and
/// totals stay ≤ 3.
List<HistoricalMatch> calmHistory(String team) {
  const opps = ['SYN Gamma', 'SYN Delta', 'SYN Epsilon', 'SYN Zeta', 'SYN Eta',
      'SYN Theta', 'SYN Iota', 'SYN Kappa', 'SYN Lambda', 'SYN Mu'];
  final scores = [
    (1, 1, '20H,70A'),
    (1, 0, '33H'),
    (2, 1, '10H,50A,80H'),
    (0, 0, '-'),
    (1, 2, '15A,40H,88A'),
    (2, 1, '5H,60A,75H'),
    (0, 1, '44A'),
    (1, 1, '12A,85H'),
    (1, 1, '30H,55A'),
    (1, 0, '67H'),
  ];
  final out = <HistoricalMatch>[];
  for (var i = 0; i < 10; i++) {
    final (h, a, s) = scores[i];
    final home = i.isEven;
    out.add(hm(
      4 + i * 7,
      home ? team : opps[i],
      home ? opps[i] : team,
      h,
      a,
      seq: s,
      ch: 5,
      ca: 4,
    ));
  }
  return out;
}

List<StructuralCheck> allClearChecks() => StructuralFactor.values
    .map((f) => StructuralCheck(
          factor: f,
          status: CheckStatus.clear,
          evidence: 'Synthetic evidence for ${f.name}',
          uncertainty: f == StructuralFactor.redCardExposure ? 'Red cards cannot be predicted reliably.' : '',
        ))
    .toList();

List<StressScenario> assessedScenarios(MarketSpec spec, {Severity severity = Severity.low}) =>
    MarketRegistry.of(spec.type)
        .stressTemplates(spec, synHome, synAway)
        .map((t) => t.toScenario().copyWith(
              severity: severity,
              evidenceSufficient: true,
              evidence: 'Synthetic plausibility evidence',
            ))
        .map((s) => StressScenario(
              kind: s.kind,
              title: s.title,
              description: s.description,
              relevance: s.relevance,
              pathway: s.pathway,
              evidence: s.evidence,
              severity: s.severity,
              evidenceSufficient: s.evidenceSufficient,
              origin: DataOrigin.userEntered,
            ))
        .toList();

const noThreeInARow = MarketSpec(type: MarketType.anyTeam3InARow, pick: 'no');

/// A selection that should pass all four VISAs.
Selection passingSelection({MarketSpec market = noThreeInARow}) => Selection(
      id: 1,
      homeTeam: synHome,
      awayTeam: synAway,
      league: 'SYN League',
      country: 'Synthland',
      kickoff: testKickoff,
      market: market,
      odds: 1.35,
      oddsSource: 'synthetic',
      oddsUpdatedAt: testNow.subtract(const Duration(hours: 1)),
      homeHistory: calmHistory(synHome),
      awayHistory: calmHistory(synAway),
      checks: allClearChecks(),
      scenarios: assessedScenarios(market),
    );
