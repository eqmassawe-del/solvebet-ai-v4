import 'dart:math' as math;

/// Parameters for the Monte-Carlo bankroll simulation.
///
/// MODEL ASSUMPTIONS (shown to the user):
/// * Every bet has the same decimal odds and the same win frequency.
/// * Bet outcomes are independent of each other (real outcomes may be
///   correlated, which makes ruin MORE likely than modelled).
/// * The win frequency is an input assumption — the app does not know the
///   true probability.
/// * Transaction cost is a % of stake charged on every bet.
/// * Stake is either a fixed fraction of the current bankroll or a fixed
///   amount; bets stop when the bankroll cannot cover a stake.
class SimulationParams {
  const SimulationParams({
    this.startBankroll = 500000,
    this.odds = 1.5,
    this.winFrequency = 0.70,
    this.stakeFraction = 0.02,
    this.fixedStake,
    this.betsPerDay = 3,
    this.days = 60,
    this.costPercent = 0,
    this.ruinFraction = 0.5,
    this.runs = 2000,
    this.seed = 42,
  });

  final double startBankroll;
  final double odds;
  final double winFrequency;
  final double stakeFraction;
  final double? fixedStake;
  final int betsPerDay;
  final int days;
  final double costPercent;

  /// Bankroll at or below `ruinFraction × start` counts as ruin.
  final double ruinFraction;
  final int runs;
  final int seed;

  /// Expected value per unit staked under the assumptions.
  double get evPerUnit => winFrequency * odds - 1 - costPercent / 100;
  double get breakEvenFrequency => (1 + costPercent / 100) / odds;

  List<String> get assumptions => [
        'Constant odds ${odds.toStringAsFixed(2)} and assumed win frequency '
            '${(winFrequency * 100).toStringAsFixed(1)}% for every bet (an input, not a measured probability).',
        'Outcomes independent — correlated losses would make results worse than shown.',
        fixedStake != null
            ? 'Fixed stake ${fixedStake!.toStringAsFixed(0)} per bet.'
            : 'Stake = ${(stakeFraction * 100).toStringAsFixed(2)}% of current bankroll.',
        'Transaction cost ${costPercent.toStringAsFixed(1)}% of stake per bet.',
        'Ruin = bankroll at or below ${(ruinFraction * 100).toStringAsFixed(0)}% of start.',
        '$runs simulated paths of $days days × $betsPerDay bets (seed $seed).',
      ];
}

class SimulationResult {
  const SimulationResult({
    required this.params,
    required this.p5,
    required this.p25,
    required this.median,
    required this.p75,
    required this.p95,
    required this.mean,
    required this.probLoss,
    required this.probRuin,
    required this.medianMaxDrawdown,
    required this.meanDailyPnl,
    required this.samplePaths,
  });

  final SimulationParams params;
  final double p5, p25, median, p75, p95, mean;
  final double probLoss;
  final double probRuin;
  final double medianMaxDrawdown;
  final double meanDailyPnl;

  /// A few daily bankroll paths for charting.
  final List<List<double>> samplePaths;
}

class BankrollSimulator {
  static SimulationResult run(SimulationParams p) {
    final rnd = math.Random(p.seed);
    final finals = <double>[];
    final dds = <double>[];
    final paths = <List<double>>[];
    var ruined = 0;
    final ruinLevel = p.startBankroll * p.ruinFraction;
    for (var r = 0; r < p.runs; r++) {
      var bank = p.startBankroll, peak = bank, maxDd = 0.0;
      var isRuined = false;
      final path = <double>[bank];
      for (var d = 0; d < p.days; d++) {
        for (var b = 0; b < p.betsPerDay; b++) {
          final stake = p.fixedStake ?? bank * p.stakeFraction;
          if (stake <= 0 || stake > bank) break;
          final cost = stake * p.costPercent / 100;
          bank += (rnd.nextDouble() < p.winFrequency ? stake * (p.odds - 1) : -stake) - cost;
          if (bank > peak) peak = bank;
          if (peak > 0) maxDd = math.max(maxDd, (peak - bank) / peak);
          if (bank <= ruinLevel) isRuined = true;
        }
        if (r < 5) path.add(bank);
      }
      if (isRuined) ruined++;
      finals.add(bank);
      dds.add(maxDd);
      if (r < 5) paths.add(path);
    }
    finals.sort();
    dds.sort();
    double q(List<double> xs, double f) => xs[((xs.length - 1) * f).round()];
    final mean = finals.reduce((a, b) => a + b) / finals.length;
    return SimulationResult(
      params: p,
      p5: q(finals, 0.05),
      p25: q(finals, 0.25),
      median: q(finals, 0.5),
      p75: q(finals, 0.75),
      p95: q(finals, 0.95),
      mean: mean,
      probLoss: finals.where((f) => f < p.startBankroll).length / finals.length,
      probRuin: ruined / p.runs,
      medianMaxDrawdown: q(dds, 0.5),
      meanDailyPnl: (mean - p.startBankroll) / p.days,
      samplePaths: paths,
    );
  }

  /// Risk of ruin for the user's observed record, using the stated model.
  static SimulationResult riskOfRuin({
    required double bankroll,
    required double hitRate,
    required double avgOdds,
    required double stakeFraction,
    int horizonBets = 300,
    double ruinFraction = 0.5,
  }) =>
      run(SimulationParams(
        startBankroll: bankroll,
        odds: avgOdds,
        winFrequency: hitRate,
        stakeFraction: stakeFraction,
        betsPerDay: 1,
        days: horizonBets,
        ruinFraction: ruinFraction,
        runs: 2000,
      ));
}
