import 'dart:convert';

/// Configurable evidence thresholds.
///
/// Thresholds tune *how much evidence* each VISA stage requires. They can
/// never change the decision matrix itself (see `decision_matrix.dart`).
class EngineConfig {
  const EngineConfig({
    this.recentWindow = 5,
    this.broadWindow = 10,
    this.emphasisWindow = 3,
    this.minRecentValidPerTeam = 3,
    this.minTotalValid = 8,
    this.maxUnknownShareRecent = 0.4,
    this.failRateFail = 0.40,
    this.failRateWatch = 0.20,
    this.watchOnEmphasisFailure = true,
    this.marginDeteriorationWatch = 0.75,
    this.minOdds = 1.01,
    this.maxOdds = 1000,
    this.oddsMaxAgeHours = 24,
    this.historyMaxAgeDays = 60,
    this.minScenariosAssessed = 3,
    this.contradictionMinSample = 3,
    this.contradictionFailRate = 0.5,
    this.weights = defaultWeights,
  });

  /// "Last 5" window (most emphasised).
  final int recentWindow;

  /// "Last 10" window (trend confirmation).
  final int broadWindow;

  /// Most-recent matches where any failure triggers WATCH.
  final int emphasisWindow;
  final int minRecentValidPerTeam;
  final int minTotalValid;
  final double maxUnknownShareRecent;

  /// Failure rate at or above which VISA B FAILS.
  final double failRateFail;

  /// Failure rate above which VISA B is WATCH.
  final double failRateWatch;
  final bool watchOnEmphasisFailure;

  /// Drop in average safety margin (recent vs broad) that triggers WATCH.
  final double marginDeteriorationWatch;
  final double minOdds;
  final double maxOdds;
  final int oddsMaxAgeHours;

  /// Most recent history record must be at most this old (relative to
  /// kickoff) for the evidence to count as current.
  final int historyMaxAgeDays;
  final int minScenariosAssessed;

  /// VISA D cross-check: if historical data shows the market failed in at
  /// least [contradictionFailRate] of ≥ [contradictionMinSample] matches with
  /// the scenario present, a LOW/MEDIUM user severity triggers WATCH.
  final int contradictionMinSample;
  final double contradictionFailRate;

  /// Evidence-score weights (normalised at use).
  final Map<String, double> weights;

  static const defaultWeights = <String, double>{
    'recentBehavior': 25,
    'evidenceQuality': 15,
    'comparability': 10,
    'marketMargin': 15,
    'structuralStability': 15,
    'stressResilience': 10,
    'dataFreshness': 10,
  };

  static const weightLabels = <String, String>{
    'recentBehavior': 'Recent market behaviour',
    'evidenceQuality': 'Quality & size of evidence',
    'comparability': 'Comparable-opponent evidence',
    'marketMargin': 'Market-specific safety margin',
    'structuralStability': 'Structural stability',
    'stressResilience': 'Stress-test resilience',
    'dataFreshness': 'Data freshness',
  };

  EngineConfig copyWith({
    int? recentWindow,
    int? broadWindow,
    int? minRecentValidPerTeam,
    int? minTotalValid,
    double? failRateFail,
    double? failRateWatch,
    int? oddsMaxAgeHours,
    int? historyMaxAgeDays,
    int? minScenariosAssessed,
    Map<String, double>? weights,
  }) =>
      EngineConfig(
        recentWindow: recentWindow ?? this.recentWindow,
        broadWindow: broadWindow ?? this.broadWindow,
        emphasisWindow: emphasisWindow,
        minRecentValidPerTeam: minRecentValidPerTeam ?? this.minRecentValidPerTeam,
        minTotalValid: minTotalValid ?? this.minTotalValid,
        maxUnknownShareRecent: maxUnknownShareRecent,
        failRateFail: failRateFail ?? this.failRateFail,
        failRateWatch: failRateWatch ?? this.failRateWatch,
        watchOnEmphasisFailure: watchOnEmphasisFailure,
        marginDeteriorationWatch: marginDeteriorationWatch,
        minOdds: minOdds,
        maxOdds: maxOdds,
        oddsMaxAgeHours: oddsMaxAgeHours ?? this.oddsMaxAgeHours,
        historyMaxAgeDays: historyMaxAgeDays ?? this.historyMaxAgeDays,
        minScenariosAssessed: minScenariosAssessed ?? this.minScenariosAssessed,
        contradictionMinSample: contradictionMinSample,
        contradictionFailRate: contradictionFailRate,
        weights: weights ?? this.weights,
      );

  /// Sanitises user-edited values so a threshold change cannot disable a
  /// gate (e.g. a failure threshold above 100% or a zero sample size).
  EngineConfig sanitized() => EngineConfig(
        recentWindow: recentWindow.clamp(3, 10),
        broadWindow: broadWindow.clamp(recentWindow.clamp(3, 10), 20),
        emphasisWindow: emphasisWindow.clamp(1, 5),
        minRecentValidPerTeam: minRecentValidPerTeam.clamp(2, 10),
        minTotalValid: minTotalValid.clamp(4, 40),
        maxUnknownShareRecent: maxUnknownShareRecent.clamp(0.0, 0.6),
        failRateFail: failRateFail.clamp(0.10, 0.60),
        failRateWatch: failRateWatch.clamp(0.0, failRateFail.clamp(0.10, 0.60)),
        watchOnEmphasisFailure: watchOnEmphasisFailure,
        marginDeteriorationWatch: marginDeteriorationWatch.clamp(0.1, 3.0),
        minOdds: minOdds.clamp(1.01, 2.0),
        maxOdds: maxOdds.clamp(1.5, 1000.0),
        oddsMaxAgeHours: oddsMaxAgeHours.clamp(1, 72),
        historyMaxAgeDays: historyMaxAgeDays.clamp(7, 180),
        minScenariosAssessed: minScenariosAssessed.clamp(2, 10),
        contradictionMinSample: contradictionMinSample.clamp(2, 10),
        contradictionFailRate: contradictionFailRate.clamp(0.2, 1.0),
        weights: {
          for (final k in defaultWeights.keys) k: (weights[k] ?? defaultWeights[k]!).clamp(0.0, 100.0),
        },
      );

  Map<String, dynamic> toJson() => {
        'recentWindow': recentWindow,
        'broadWindow': broadWindow,
        'minRecentValidPerTeam': minRecentValidPerTeam,
        'minTotalValid': minTotalValid,
        'failRateFail': failRateFail,
        'failRateWatch': failRateWatch,
        'oddsMaxAgeHours': oddsMaxAgeHours,
        'historyMaxAgeDays': historyMaxAgeDays,
        'minScenariosAssessed': minScenariosAssessed,
        'weights': weights,
      };

  factory EngineConfig.fromJson(Map<String, dynamic> j) {
    const d = EngineConfig();
    return EngineConfig(
      recentWindow: (j['recentWindow'] as num?)?.toInt() ?? d.recentWindow,
      broadWindow: (j['broadWindow'] as num?)?.toInt() ?? d.broadWindow,
      minRecentValidPerTeam: (j['minRecentValidPerTeam'] as num?)?.toInt() ?? d.minRecentValidPerTeam,
      minTotalValid: (j['minTotalValid'] as num?)?.toInt() ?? d.minTotalValid,
      failRateFail: (j['failRateFail'] as num?)?.toDouble() ?? d.failRateFail,
      failRateWatch: (j['failRateWatch'] as num?)?.toDouble() ?? d.failRateWatch,
      oddsMaxAgeHours: (j['oddsMaxAgeHours'] as num?)?.toInt() ?? d.oddsMaxAgeHours,
      historyMaxAgeDays: (j['historyMaxAgeDays'] as num?)?.toInt() ?? d.historyMaxAgeDays,
      minScenariosAssessed: (j['minScenariosAssessed'] as num?)?.toInt() ?? d.minScenariosAssessed,
      weights: j['weights'] == null
          ? defaultWeights
          : Map<String, dynamic>.from(j['weights'] as Map)
              .map((k, v) => MapEntry(k, (v as num).toDouble())),
    ).sanitized();
  }

  String encode() => jsonEncode(toJson());
  static EngineConfig decode(String? s) =>
      s == null || s.isEmpty ? const EngineConfig() : EngineConfig.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
