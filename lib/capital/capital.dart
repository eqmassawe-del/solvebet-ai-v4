import 'dart:convert';
import 'dart:math' as math;

import '../core/time.dart';

enum BetStatus {
  pending,
  won,
  lost,
  voided;

  String get label => switch (this) {
        BetStatus.pending => 'PENDING',
        BetStatus.won => 'WON',
        BetStatus.lost => 'LOST',
        BetStatus.voided => 'VOID',
      };

  static BetStatus parse(String? s) =>
      BetStatus.values.firstWhere((e) => e.name == s, orElse: () => BetStatus.pending);
}

/// A placed (paper or real) bet.
class Bet {
  Bet({
    this.id,
    required this.createdAt,
    required this.label,
    required this.odds,
    required this.stake,
    this.status = BetStatus.pending,
    this.settledAt,
    this.paper = true,
    this.selectionIds = const [],
    this.notes = '',
    this.cost = 0,
  });

  final int? id;
  final DateTime createdAt;
  final String label;
  final double odds;
  final double stake;
  final BetStatus status;
  final DateTime? settledAt;
  final bool paper;
  final List<int> selectionIds;
  final String notes;

  /// Transaction cost / tax deducted from returns (absolute, TZS).
  final double cost;

  bool get settled => status != BetStatus.pending;

  /// Profit/loss realised by this bet (0 while pending).
  double get pnl => switch (status) {
        BetStatus.won => stake * (odds - 1) - cost,
        BetStatus.lost => -stake - cost,
        BetStatus.voided => -cost,
        BetStatus.pending => 0,
      };

  Bet copyWith({BetStatus? status, DateTime? settledAt}) => Bet(
        id: id,
        createdAt: createdAt,
        label: label,
        odds: odds,
        stake: stake,
        status: status ?? this.status,
        settledAt: settledAt ?? this.settledAt,
        paper: paper,
        selectionIds: selectionIds,
        notes: notes,
        cost: cost,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'created_at': createdAt.millisecondsSinceEpoch,
        'label': label,
        'odds': odds,
        'stake': stake,
        'status': status.name,
        'settled_at': settledAt?.millisecondsSinceEpoch,
        'paper': paper ? 1 : 0,
        'selection_ids': jsonEncode(selectionIds),
        'notes': notes,
        'cost': cost,
      };

  factory Bet.fromMap(Map<String, dynamic> m) => Bet(
        id: m['id'] as int?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int, isUtc: true),
        label: m['label'] as String,
        odds: (m['odds'] as num).toDouble(),
        stake: (m['stake'] as num).toDouble(),
        status: BetStatus.parse(m['status'] as String?),
        settledAt: m['settled_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['settled_at'] as int, isUtc: true),
        paper: (m['paper'] as int? ?? 1) == 1,
        selectionIds: ((jsonDecode((m['selection_ids'] as String?) ?? '[]') as List).cast<num>())
            .map((e) => e.toInt())
            .toList(),
        notes: (m['notes'] as String?) ?? '',
        cost: (m['cost'] as num?)?.toDouble() ?? 0,
      );
}

enum StakeMethod { fixedPercent, fixedAmount }

class CapitalSettings {
  const CapitalSettings({
    this.initialBankroll = 500000,
    this.currency = 'TZS',
    this.paperMode = true,
    this.stakeMethod = StakeMethod.fixedPercent,
    this.stakePercent = 1.0,
    this.fixedStake = 5000,
    this.maxStakePercent = 2.0,
    this.maxDailyExposurePercent = 6.0,
    this.dailyLossLimitPercent = 5.0,
    this.maxDrawdownPercent = 20.0,
    this.dailyTarget = 30000,
  });

  final double initialBankroll;
  final String currency;
  final bool paperMode;
  final StakeMethod stakeMethod;
  final double stakePercent;
  final double fixedStake;
  final double maxStakePercent;
  final double maxDailyExposurePercent;
  final double dailyLossLimitPercent;
  final double maxDrawdownPercent;

  /// Planning target only — never an expected or guaranteed outcome.
  final double dailyTarget;

  CapitalSettings copyWith({
    double? initialBankroll,
    bool? paperMode,
    StakeMethod? stakeMethod,
    double? stakePercent,
    double? fixedStake,
    double? maxStakePercent,
    double? maxDailyExposurePercent,
    double? dailyLossLimitPercent,
    double? maxDrawdownPercent,
    double? dailyTarget,
  }) =>
      CapitalSettings(
        initialBankroll: initialBankroll ?? this.initialBankroll,
        currency: currency,
        paperMode: paperMode ?? this.paperMode,
        stakeMethod: stakeMethod ?? this.stakeMethod,
        stakePercent: stakePercent ?? this.stakePercent,
        fixedStake: fixedStake ?? this.fixedStake,
        maxStakePercent: maxStakePercent ?? this.maxStakePercent,
        maxDailyExposurePercent: maxDailyExposurePercent ?? this.maxDailyExposurePercent,
        dailyLossLimitPercent: dailyLossLimitPercent ?? this.dailyLossLimitPercent,
        maxDrawdownPercent: maxDrawdownPercent ?? this.maxDrawdownPercent,
        dailyTarget: dailyTarget ?? this.dailyTarget,
      );

  Map<String, dynamic> toJson() => {
        'initialBankroll': initialBankroll,
        'paperMode': paperMode,
        'stakeMethod': stakeMethod.name,
        'stakePercent': stakePercent,
        'fixedStake': fixedStake,
        'maxStakePercent': maxStakePercent,
        'maxDailyExposurePercent': maxDailyExposurePercent,
        'dailyLossLimitPercent': dailyLossLimitPercent,
        'maxDrawdownPercent': maxDrawdownPercent,
        'dailyTarget': dailyTarget,
      };

  factory CapitalSettings.fromJson(Map<String, dynamic> j) {
    const d = CapitalSettings();
    double n(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    return CapitalSettings(
      initialBankroll: n('initialBankroll', d.initialBankroll),
      paperMode: j['paperMode'] as bool? ?? true,
      stakeMethod: j['stakeMethod'] == 'fixedAmount' ? StakeMethod.fixedAmount : StakeMethod.fixedPercent,
      stakePercent: n('stakePercent', d.stakePercent),
      fixedStake: n('fixedStake', d.fixedStake),
      maxStakePercent: n('maxStakePercent', d.maxStakePercent),
      maxDailyExposurePercent: n('maxDailyExposurePercent', d.maxDailyExposurePercent),
      dailyLossLimitPercent: n('dailyLossLimitPercent', d.dailyLossLimitPercent),
      maxDrawdownPercent: n('maxDrawdownPercent', d.maxDrawdownPercent),
      dailyTarget: n('dailyTarget', d.dailyTarget),
    );
  }
}

class StakeAdvice {
  const StakeAdvice(this.stake, this.reasons, {this.blocked = false});
  final double stake;
  final List<String> reasons;
  final bool blocked;
}

enum TargetVerdict { insufficientData, supported, contradicted, notYetSupported }

class TargetAssessment {
  const TargetAssessment(this.verdict, this.lines);
  final TargetVerdict verdict;
  final List<String> lines;
}

class BankrollMetrics {
  BankrollMetrics({
    required this.initial,
    required this.current,
    required this.realizedPnl,
    required this.turnover,
    required this.wins,
    required this.losses,
    required this.voids,
    required this.pendingExposure,
    required this.pendingCount,
    required this.peak,
    required this.maxDrawdown,
    required this.currentDrawdown,
    required this.longestWinStreak,
    required this.longestLossStreak,
    required this.currentStreak,
    required this.equityCurve,
    required this.dailyPnl,
    required this.todayPnl,
    required this.todayStaked,
    required this.avgOdds,
  });

  final double initial;
  final double current;
  final double realizedPnl;
  final double turnover;
  final int wins;
  final int losses;
  final int voids;
  final double pendingExposure;
  final int pendingCount;
  final double peak;

  /// Fractions (0.2 = 20%).
  final double maxDrawdown;
  final double currentDrawdown;
  final int longestWinStreak;
  final int longestLossStreak;

  /// Positive = current win streak, negative = loss streak.
  final int currentStreak;
  final List<double> equityCurve;

  /// EAT date (yyyy-MM-dd) → realised P/L.
  final Map<String, double> dailyPnl;
  final double todayPnl;
  final double todayStaked;
  final double avgOdds;

  int get settledCount => wins + losses;

  /// Yield = profit / turnover.
  double? get yieldPct => turnover == 0 ? null : realizedPnl / turnover * 100;

  /// ROI on starting bankroll = profit / initial bankroll.
  double get roiPct => initial == 0 ? 0 : realizedPnl / initial * 100;
  double? get hitRate => settledCount == 0 ? null : wins / settledCount;
  double get available => current - pendingExposure;
  double? get avgDailyPnl =>
      dailyPnl.isEmpty ? null : dailyPnl.values.reduce((a, b) => a + b) / dailyPnl.length;
}

class CapitalEngine {
  static BankrollMetrics compute(List<Bet> bets, CapitalSettings cfg, {DateTime? nowUtc}) {
    final now = nowUtc ?? DateTime.now().toUtc();
    final settled = bets.where((b) => b.settled).toList()
      ..sort((a, b) => (a.settledAt ?? a.createdAt).compareTo(b.settledAt ?? b.createdAt));
    var bank = cfg.initialBankroll, peak = bank, maxDd = 0.0;
    var wins = 0, losses = 0, voids = 0, turnover = 0.0, pnl = 0.0, oddsSum = 0.0;
    var streak = 0, longestW = 0, longestL = 0;
    final curve = <double>[bank];
    final daily = <String, double>{};
    for (final b in settled) {
      bank += b.pnl;
      pnl += b.pnl;
      if (b.status != BetStatus.voided) {
        turnover += b.stake;
        oddsSum += b.odds;
      }
      final day = EatTime.dateKey(b.settledAt ?? b.createdAt);
      daily[day] = (daily[day] ?? 0) + b.pnl;
      switch (b.status) {
        case BetStatus.won:
          wins++;
          streak = streak >= 0 ? streak + 1 : 1;
        case BetStatus.lost:
          losses++;
          streak = streak <= 0 ? streak - 1 : -1;
        case BetStatus.voided:
          voids++;
        case BetStatus.pending:
          break;
      }
      longestW = math.max(longestW, streak);
      longestL = math.max(longestL, -streak);
      peak = math.max(peak, bank);
      if (peak > 0) maxDd = math.max(maxDd, (peak - bank) / peak);
      curve.add(bank);
    }
    final pending = bets.where((b) => !b.settled);
    final today = EatTime.dateKey(now);
    final todayStaked = bets
        .where((b) => EatTime.dateKey(b.createdAt) == today && b.status != BetStatus.voided)
        .fold<double>(0, (s, b) => s + b.stake);
    return BankrollMetrics(
      initial: cfg.initialBankroll,
      current: bank,
      realizedPnl: pnl,
      turnover: turnover,
      wins: wins,
      losses: losses,
      voids: voids,
      pendingExposure: pending.fold(0, (s, b) => s + b.stake),
      pendingCount: pending.length,
      peak: peak,
      maxDrawdown: maxDd,
      currentDrawdown: peak == 0 ? 0 : (peak - bank) / peak,
      longestWinStreak: longestW,
      longestLossStreak: longestL,
      currentStreak: streak,
      equityCurve: curve,
      dailyPnl: daily,
      todayPnl: daily[today] ?? 0,
      todayStaked: todayStaked,
      avgOdds: (wins + losses) == 0 ? 0 : oddsSum / (wins + losses),
    );
  }

  /// Stake sizing that never exceeds the user-defined limits.
  static StakeAdvice recommendStake(CapitalSettings cfg, BankrollMetrics m) {
    final reasons = <String>[];
    if (m.current <= 0) return const StakeAdvice(0, ['Bankroll exhausted.'], blocked: true);
    final dailyLossLimit = cfg.initialBankroll * cfg.dailyLossLimitPercent / 100;
    if (-m.todayPnl >= dailyLossLimit) {
      return StakeAdvice(0, ['Daily loss limit reached (${cfg.dailyLossLimitPercent}% of starting bankroll). Stop for today.'],
          blocked: true);
    }
    if (m.currentDrawdown * 100 >= cfg.maxDrawdownPercent) {
      return StakeAdvice(0, ['Drawdown ${(m.currentDrawdown * 100).toStringAsFixed(1)}% exceeds the '
          '${cfg.maxDrawdownPercent}% limit. Pause and review the strategy.'], blocked: true);
    }
    var stake = cfg.stakeMethod == StakeMethod.fixedPercent
        ? m.current * cfg.stakePercent / 100
        : cfg.fixedStake;
    reasons.add(cfg.stakeMethod == StakeMethod.fixedPercent
        ? 'Base: ${cfg.stakePercent}% of current bankroll.'
        : 'Base: fixed stake.');
    final maxStake = m.current * cfg.maxStakePercent / 100;
    if (stake > maxStake) {
      stake = maxStake;
      reasons.add('Capped at max stake ${cfg.maxStakePercent}% of bankroll.');
    }
    final dailyRoom = m.current * cfg.maxDailyExposurePercent / 100 - m.todayStaked;
    if (stake > dailyRoom) {
      stake = math.max(0, dailyRoom);
      reasons.add('Limited by remaining daily exposure (${cfg.maxDailyExposurePercent}% of bankroll).');
    }
    if (stake > m.available) {
      stake = math.max(0, m.available);
      reasons.add('Limited by funds not tied up in pending bets.');
    }
    final blocked = stake <= 0;
    if (blocked) reasons.add('No stake permitted under current limits.');
    return StakeAdvice((stake / 100).floorToDouble() * 100, reasons, blocked: blocked);
  }

  /// Compares the planning target with observed results. The target is never
  /// presented as expected or guaranteed.
  static TargetAssessment assessTarget(CapitalSettings cfg, BankrollMetrics m) {
    final lines = <String>[
      'Planning target: ${cfg.currency} ${cfg.dailyTarget.toStringAsFixed(0)} per day. '
          'This is a planning figure, not an expected or guaranteed outcome.',
    ];
    final days = m.dailyPnl.length;
    if (m.settledCount < 30 || days < 14) {
      lines.add('Insufficient data: ${m.settledCount} settled bets over $days active day(s). '
          'At least 30 bets across 14 days are needed before judging the target.');
      return TargetAssessment(TargetVerdict.insufficientData, lines);
    }
    final vals = m.dailyPnl.values.toList();
    final mean = vals.reduce((a, b) => a + b) / vals.length;
    final sd = math.sqrt(vals.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
        math.max(1, vals.length - 1));
    final se = sd / math.sqrt(vals.length);
    final lo = mean - 1.96 * se, hi = mean + 1.96 * se;
    lines.add('Observed average daily P/L: ${mean.toStringAsFixed(0)} '
        '(approx. 95% interval ${lo.toStringAsFixed(0)} to ${hi.toStringAsFixed(0)}, normal approximation, $days days).');
    final avgStake = m.turnover / math.max(1, m.settledCount);
    final betsPerDay = m.settledCount / days;
    if (m.avgOdds > 1 && avgStake > 0) {
      final req = (cfg.dailyTarget / (betsPerDay * avgStake) + 1) / m.avgOdds;
      lines.add('At ${betsPerDay.toStringAsFixed(1)} bets/day, average stake ${avgStake.toStringAsFixed(0)} and '
          'average odds ${m.avgOdds.toStringAsFixed(2)}, the target requires a hit rate of '
          '${(req * 100).toStringAsFixed(1)}% (break-even ${(100 / m.avgOdds).toStringAsFixed(1)}%). '
          'Observed: ${((m.hitRate ?? 0) * 100).toStringAsFixed(1)}%.');
    }
    if (lo >= cfg.dailyTarget) {
      lines.add('Observed results SUPPORT the target (lower bound above target).');
      return TargetAssessment(TargetVerdict.supported, lines);
    }
    if (hi < cfg.dailyTarget) {
      lines.add('Observed results CONTRADICT the target (upper bound below target).');
      return TargetAssessment(TargetVerdict.contradicted, lines);
    }
    lines.add('Results are inconclusive — the target is NOT yet supported by evidence.');
    return TargetAssessment(TargetVerdict.notYetSupported, lines);
  }
}
