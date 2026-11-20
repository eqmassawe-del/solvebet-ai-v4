import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../capital/capital.dart';
import '../../capital/simulation.dart';
import '../../core/theme.dart';
import '../../core/time.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import 'visa_report_screen.dart';

/// CAPITAL CONTROL — bankroll analytics, ledger and simulation.
class CapitalScreen extends ConsumerWidget {
  const CapitalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => const DefaultTabController(
        length: 3,
        child: Column(children: [
          TabBar(tabs: [Tab(text: 'OVERVIEW'), Tab(text: 'LEDGER'), Tab(text: 'SIMULATOR')]),
          Expanded(child: TabBarView(children: [_Overview(), _Ledger(), _Simulator()])),
        ]),
      );
}

class _Overview extends ConsumerWidget {
  const _Overview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(metricsProvider);
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    if (m == null) return const Center(child: CircularProgressIndicator());
    final cfg = settings.capital;
    final cur = cfg.currency;
    final advice = CapitalEngine.recommendStake(cfg, m);
    final target = CapitalEngine.assessTarget(cfg, m);
    SimulationResult? ror;
    if (m.settledCount >= 20 && m.avgOdds > 1) {
      ror = BankrollSimulator.riskOfRuin(
          bankroll: m.current, hitRate: m.hitRate!, avgOdds: m.avgOdds, stakeFraction: cfg.stakePercent / 100);
    }
    return ListView(padding: const EdgeInsets.all(12), children: [
      ErrorBanner(
        cfg.paperMode
            ? 'PAPER TRADING / SIMULATION mode. No real money is involved.'
            : 'REAL-MONEY LEDGER mode. The app records bets; it never places them.',
        color: cfg.paperMode ? AppColors.pass : AppColors.watch,
        icon: Icons.shield_outlined,
      ),
      SectionCard(
        title: 'Bankroll',
        icon: Icons.account_balance_wallet_outlined,
        child: Column(children: [
          StatGrid([
            StatTile('Current bankroll', money(m.current, cur), color: m.current >= m.initial ? AppColors.pass : AppColors.fail,
                sub: 'start ${money(m.initial, cur)}'),
            StatTile('Realised P/L', money(m.realizedPnl, cur), color: m.realizedPnl >= 0 ? AppColors.pass : AppColors.fail),
            StatTile('ROI (on start)', '${m.roiPct.toStringAsFixed(2)}%'),
            StatTile('Yield (on turnover)', m.yieldPct == null ? 'n/a' : '${m.yieldPct!.toStringAsFixed(2)}%',
                sub: 'turnover ${money(m.turnover, cur)}'),
            StatTile('Record', '${m.wins}W ${m.losses}L ${m.voids}V', sub: 'hit rate ${pct(m.hitRate)}'),
            StatTile('Open exposure', money(m.pendingExposure, cur), sub: '${m.pendingCount} pending'),
            StatTile('Drawdown', pct(m.currentDrawdown), sub: 'max ${pct(m.maxDrawdown)} · limit ${cfg.maxDrawdownPercent}%',
                color: m.currentDrawdown * 100 >= cfg.maxDrawdownPercent ? AppColors.fail : null),
            StatTile('Streaks', m.currentStreak >= 0 ? '${m.currentStreak} W' : '${-m.currentStreak} L',
                sub: 'longest ${m.longestWinStreak}W / ${m.longestLossStreak}L'),
            StatTile("Today's P/L", money(m.todayPnl, cur),
                sub: 'loss limit ${money(-cfg.initialBankroll * cfg.dailyLossLimitPercent / 100, cur)}'),
            StatTile('Staked today', money(m.todayStaked, cur), sub: 'cap ${cfg.maxDailyExposurePercent}% of bankroll'),
          ]),
          const SizedBox(height: 10),
          if (m.equityCurve.length > 1) LineChart([m.equityCurve], baseline: m.initial),
        ]),
      ),
      SectionCard(
        title: 'Stake sizing',
        icon: Icons.straighten,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(advice.blocked ? 'NO STAKE PERMITTED' : 'Advised stake: ${money(advice.stake, cur)}',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: advice.blocked ? AppColors.fail : AppColors.gold)),
          for (final r in advice.reasons) Text('• $r', style: const TextStyle(fontSize: 12)),
        ]),
      ),
      SectionCard(
        title: 'Daily income target (planning only)',
        icon: Icons.flag_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(switch (target.verdict) {
            TargetVerdict.insufficientData => 'INSUFFICIENT DATA',
            TargetVerdict.supported => 'SUPPORTED BY OBSERVED RESULTS',
            TargetVerdict.contradicted => 'CONTRADICTED BY OBSERVED RESULTS',
            TargetVerdict.notYetSupported => 'NOT YET SUPPORTED',
          },
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: switch (target.verdict) {
                    TargetVerdict.supported => AppColors.pass,
                    TargetVerdict.contradicted => AppColors.fail,
                    _ => AppColors.watch,
                  })),
          for (final l in target.lines) Padding(padding: const EdgeInsets.only(top: 4), child: Text(l, style: const TextStyle(fontSize: 12))),
        ]),
      ),
      SectionCard(
        title: 'Risk of ruin (model estimate)',
        icon: Icons.warning_amber,
        child: ror == null
            ? const Text('Needs at least 20 settled bets to parameterise the model from your own record.',
                style: TextStyle(color: AppColors.muted, fontSize: 12))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('P(bankroll falls to ≤50% within 300 bets) ≈ ${pct(ror.probRuin)}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                for (final a in ror.params.assumptions) Text('• $a', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              ]),
      ),
    ]);
  }
}

class _Ledger extends ConsumerWidget {
  const _Ledger();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bets = ref.watch(betsProvider);
    final cur = (ref.watch(settingsProvider).value ?? const AppSettings()).capital.currency;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => recordPaperBet(context, ref, label: 'Manual bet'),
        icon: const Icon(Icons.add),
        label: const Text('Bet'),
      ),
      body: bets.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorBanner('$e'),
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No bets recorded',
                message: 'Record paper bets from a VISA report or the Builder to track performance.')
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final b = list[i];
                  final c = switch (b.status) {
                    BetStatus.won => AppColors.pass,
                    BetStatus.lost => AppColors.fail,
                    BetStatus.voided => AppColors.muted,
                    BetStatus.pending => AppColors.gold,
                  };
                  return Card(
                    child: ListTile(
                      title: Text(b.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${EatTime.format(b.createdAt, pattern: 'd MMM HH:mm')} · ${money(b.stake, cur)} @ ${b.odds.toStringAsFixed(2)}'
                          '${b.paper ? ' · PAPER' : ''}${b.settled ? ' · P/L ${money(b.pnl, cur)}' : ''}'),
                      trailing: Text(b.status.label, style: TextStyle(color: c, fontWeight: FontWeight.w800)),
                      onTap: () async {
                        final st = await showDialog<String>(
                          context: context,
                          builder: (_) => SimpleDialog(title: const Text('Settle bet'), children: [
                            for (final s in BetStatus.values)
                              SimpleDialogOption(onPressed: () => Navigator.pop(context, s.name), child: Text(s.label)),
                            SimpleDialogOption(
                                onPressed: () => Navigator.pop(context, 'delete'),
                                child: const Text('Delete', style: TextStyle(color: AppColors.fail))),
                          ]),
                        );
                        if (st == null) return;
                        final ctl = ref.read(betsProvider.notifier);
                        if (st == 'delete') {
                          await ctl.delete(b.id!);
                        } else {
                          final ns = BetStatus.parse(st);
                          await ctl.save(b.copyWith(status: ns, settledAt: ns == BetStatus.pending ? null : DateTime.now().toUtc()));
                        }
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _Simulator extends ConsumerStatefulWidget {
  const _Simulator();
  @override
  ConsumerState<_Simulator> createState() => _SimulatorState();
}

class _SimulatorState extends ConsumerState<_Simulator> {
  double _odds = 1.5, _freq = 0.70, _stakePct = 2, _cost = 0;
  int _betsPerDay = 3, _days = 60;
  SimulationResult? _r;

  @override
  Widget build(BuildContext context) {
    final cfg = (ref.watch(settingsProvider).value ?? const AppSettings()).capital;
    final m = ref.watch(metricsProvider);
    final p = SimulationParams(
      startBankroll: m?.current ?? cfg.initialBankroll,
      odds: _odds,
      winFrequency: _freq,
      stakeFraction: _stakePct / 100,
      betsPerDay: _betsPerDay,
      days: _days,
      costPercent: _cost,
    );
    return ListView(padding: const EdgeInsets.all(12), children: [
      SectionCard(
        title: 'Assumptions (you choose them)',
        icon: Icons.science_outlined,
        child: Column(children: [
          _s('Decimal odds', _odds, 1.05, 5, 0.05, (v) => _odds = v, _odds.toStringAsFixed(2)),
          _s('Win frequency', _freq, 0.05, 0.99, 0.01, (v) => _freq = v, pct(_freq, digits: 0)),
          _s('Stake % of bankroll', _stakePct, 0.25, 10, 0.25, (v) => _stakePct = v, '${_stakePct.toStringAsFixed(2)}%'),
          _s('Bets per day', _betsPerDay.toDouble(), 1, 10, 1, (v) => _betsPerDay = v.round(), '$_betsPerDay'),
          _s('Days', _days.toDouble(), 7, 365, 1, (v) => _days = v.round(), '$_days'),
          _s('Transaction cost %', _cost, 0, 20, 0.5, (v) => _cost = v, '${_cost.toStringAsFixed(1)}%'),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              child: Text('EV per 1 staked: ${p.evPerUnit.toStringAsFixed(3)} · break-even win frequency ${pct(p.breakEvenFrequency)}',
                  style: TextStyle(fontSize: 12, color: p.evPerUnit > 0 ? AppColors.pass : AppColors.fail)),
            ),
            FilledButton(onPressed: () => setState(() => _r = BankrollSimulator.run(p)), child: const Text('RUN')),
          ]),
          if (_stakePct > cfg.maxStakePercent)
            ErrorBanner('Simulated stake exceeds your ${cfg.maxStakePercent}% max-stake limit — for exploration only.',
                color: AppColors.watch),
        ]),
      ),
      if (_r != null) _results(_r!, cfg),
    ]);
  }

  Widget _results(SimulationResult r, CapitalSettings cfg) => SectionCard(
        title: 'Simulation results',
        icon: Icons.insights,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          StatGrid([
            StatTile('Median final', money(r.median, cfg.currency)),
            StatTile('5th – 95th pct', '${money(r.p5, '')} – ${money(r.p95, '')}'),
            StatTile('P(end below start)', pct(r.probLoss), color: r.probLoss > 0.5 ? AppColors.fail : null),
            StatTile('P(ruin ≤50%)', pct(r.probRuin), color: r.probRuin > 0.05 ? AppColors.fail : null),
            StatTile('Median max drawdown', pct(r.medianMaxDrawdown)),
            StatTile('Mean daily P/L', money(r.meanDailyPnl, cfg.currency),
                sub: 'vs plan ${money(cfg.dailyTarget, cfg.currency)}',
                color: r.meanDailyPnl >= cfg.dailyTarget ? AppColors.pass : AppColors.watch),
          ]),
          const SizedBox(height: 8),
          LineChart(r.samplePaths, baseline: r.params.startBankroll),
          const Text('Five sample paths (daily).', style: TextStyle(fontSize: 11, color: AppColors.muted)),
          const SizedBox(height: 8),
          const Text('MODEL ASSUMPTIONS', style: TextStyle(color: AppColors.gold, fontSize: 11, fontWeight: FontWeight.w700)),
          for (final a in r.params.assumptions) Text('• $a', style: const TextStyle(fontSize: 11)),
        ]),
      );

  Widget _s(String label, double v, double min, double max, double step, ValueChanged<double> set, String shown) => Row(children: [
        SizedBox(width: 130, child: Text(label, style: const TextStyle(fontSize: 12))),
        Expanded(
          child: Slider(
            value: v.clamp(min, max),
            min: min,
            max: max,
            divisions: ((max - min) / step).round(),
            onChanged: (x) => setState(() => set(x)),
          ),
        ),
        SizedBox(width: 56, child: Text(shown, textAlign: TextAlign.end, style: const TextStyle(fontSize: 12))),
      ]);
}
