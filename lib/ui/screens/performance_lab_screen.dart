import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme.dart';
import '../../domain/enums.dart';
import '../../domain/selection.dart';
import '../../engine/kings_visa_engine.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';

class _Bucket {
  int won = 0, lost = 0, voids = 0;
  double impliedSum = 0;
  int impliedN = 0;
  int get n => won + lost;
  double? get hit => n == 0 ? null : won / n;
  double? get implied => impliedN == 0 ? null : impliedSum / impliedN;
  void add(Selection s) {
    switch (s.actualOutcome) {
      case 'won':
        won++;
      case 'lost':
        lost++;
      case 'void':
        voids++;
    }
    if (s.odds != null && s.odds! > 1 && s.actualOutcome != 'void') {
      impliedSum += 1 / s.odds!;
      impliedN++;
    }
  }
}

/// PERFORMANCE LAB — historical results, calibration checks and backtests.
class PerformanceLabScreen extends ConsumerStatefulWidget {
  const PerformanceLabScreen({super.key});
  @override
  ConsumerState<PerformanceLabScreen> createState() => _LabState();
}

class _LabState extends ConsumerState<PerformanceLabScreen> {
  Map<FinalVerdict, _Bucket>? _backtest;

  @override
  Widget build(BuildContext context) {
    final sels = ref.watch(selectionsProvider).value ?? [];
    final m = ref.watch(metricsProvider);
    final settled = sels.where((a) => a.selection.actualOutcome != null).toList();

    final byVerdict = <String, _Bucket>{};
    final byMarket = <String, _Bucket>{};
    final byScore = <String, _Bucket>{};
    for (final a in settled) {
      byVerdict.putIfAbsent(a.verdict?.label ?? 'NOT AUDITED', _Bucket.new).add(a.selection);
      byMarket.putIfAbsent(a.selection.market.type.title, _Bucket.new).add(a.selection);
      if (a.score != null) {
        final lo = (a.score! ~/ 10) * 10;
        byScore.putIfAbsent('$lo–${lo + 10}', _Bucket.new).add(a.selection);
      }
    }
    final scoreKeys = byScore.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(title: const Text('PERFORMANCE LAB')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        const ErrorBanner(
          'Record the actual result of audited selections (VISA report → menu → Record actual result) — including '
          'REJECTED and WATCH ones — so the engine\'s gates can be validated against reality.',
          color: AppColors.muted,
          icon: Icons.info_outline,
        ),
        SectionCard(
          title: 'Results by KING\'S VISA verdict',
          icon: Icons.fact_check_outlined,
          child: settled.isEmpty ? _none() : _table(byVerdict),
        ),
        SectionCard(
          title: 'Results by market',
          icon: Icons.category_outlined,
          child: settled.isEmpty ? _none() : _table(byMarket),
        ),
        SectionCard(
          title: 'Calibration check — evidence score bands',
          icon: Icons.tune,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('The evidence score is NOT a probability. This check only asks whether higher bands '
                'historically held up better, and compares with bookmaker-implied probability (1/odds).',
                style: TextStyle(fontSize: 11, color: AppColors.muted)),
            const SizedBox(height: 6),
            if (scoreKeys.isEmpty) _none() else _table({for (final k in scoreKeys) k: byScore[k]!}),
            if (byScore.values.fold<int>(0, (s, b) => s + b.n) < 50)
              const Text('Fewer than 50 settled observations — calibration conclusions are not reliable yet.',
                  style: TextStyle(fontSize: 11, color: AppColors.watch)),
          ]),
        ),
        SectionCard(
          title: 'Backtest current thresholds',
          icon: Icons.history_toggle_off,
          trailing: TextButton(
            onPressed: settled.isEmpty ? null : () => _runBacktest(settled.map((a) => a.selection).toList()),
            child: const Text('RUN'),
          ),
          child: _backtest == null
              ? const Text('Re-audits every settled selection with the CURRENT engine settings as of 1 hour before its '
                  'kickoff, then compares verdicts with the recorded results.', style: TextStyle(fontSize: 12, color: AppColors.muted))
              : _table({for (final e in _backtest!.entries) e.key.label: e.value}),
        ),
        if (m != null)
          SectionCard(
            title: 'Strategy validation (ledger)',
            icon: Icons.insights,
            child: StatGrid([
              StatTile('Settled bets', '${m.settledCount}'),
              StatTile('Hit rate', pct(m.hitRate)),
              StatTile('Average odds', m.avgOdds == 0 ? 'n/a' : m.avgOdds.toStringAsFixed(2),
                  sub: m.avgOdds > 1 ? 'break-even ${pct(1 / m.avgOdds)}' : null),
              StatTile('Yield', m.yieldPct == null ? 'n/a' : '${m.yieldPct!.toStringAsFixed(2)}%',
                  color: (m.yieldPct ?? 0) >= 0 ? AppColors.pass : AppColors.fail),
              StatTile('Max drawdown', pct(m.maxDrawdown)),
              StatTile('Sample adequacy', m.settledCount >= 100 ? 'Moderate' : 'Low', sub: '${m.settledCount} / 100+ bets'),
            ]),
          ),
      ]),
    );
  }

  void _runBacktest(List<Selection> list) {
    final cfg = (ref.read(settingsProvider).value ?? const AppSettings()).engine;
    final out = <FinalVerdict, _Bucket>{};
    for (final s in list) {
      final at = (s.kickoff ?? s.createdAt).subtract(const Duration(hours: 1));
      final v = KingsVisaEngine(config: cfg, clock: () => at).audit(s).verdict;
      out.putIfAbsent(v, _Bucket.new).add(s);
    }
    setState(() => _backtest = out);
  }

  Widget _none() => const Text('No settled selections yet.', style: TextStyle(color: AppColors.muted));

  Widget _table(Map<String, _Bucket> rows) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 30,
          dataRowMinHeight: 28,
          dataRowMaxHeight: 34,
          columnSpacing: 16,
          columns: const [
            DataColumn(label: Text('Group')),
            DataColumn(label: Text('Won'), numeric: true),
            DataColumn(label: Text('Lost'), numeric: true),
            DataColumn(label: Text('Void'), numeric: true),
            DataColumn(label: Text('Hit rate'), numeric: true),
            DataColumn(label: Text('Implied'), numeric: true),
          ],
          rows: [
            for (final e in rows.entries)
              DataRow(cells: [
                DataCell(Text(e.key, style: const TextStyle(fontSize: 12))),
                DataCell(Text('${e.value.won}')),
                DataCell(Text('${e.value.lost}')),
                DataCell(Text('${e.value.voids}')),
                DataCell(Text(pct(e.value.hit))),
                DataCell(Text(pct(e.value.implied))),
              ]),
          ],
        ),
      );
}
