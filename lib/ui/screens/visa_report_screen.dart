import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../capital/capital.dart';
import '../../core/theme.dart';
import '../../core/time.dart';
import '../../domain/audit.dart';
import '../../domain/enums.dart';
import '../../domain/market.dart';
import '../../engine/engine_config.dart';
import '../../engine/markets/markets.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import 'selection_editor_screen.dart';

/// KING'S VISA REPORT — detailed four-stage audit of one selection.
class VisaReportScreen extends ConsumerStatefulWidget {
  const VisaReportScreen({super.key, required this.selectionId});
  final int selectionId;
  @override
  ConsumerState<VisaReportScreen> createState() => _VisaReportScreenState();
}

class _VisaReportScreenState extends ConsumerState<VisaReportScreen> {
  String? _ai;
  String? _aiError;
  bool _aiBusy = false;

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(selectionsProvider);
    return list.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: ErrorBanner('$e'))),
      data: (all) {
        final item = all.where((a) => a.selection.id == widget.selectionId).firstOrNull;
        if (item == null) {
          return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.search_off, title: 'Not found', message: 'This selection was deleted.'));
        }
        return _scaffold(item);
      },
    );
  }

  Widget _scaffold(AuditedSelection item) {
    final s = item.selection;
    final r = item.audit;
    final ev = MarketRegistry.of(s.market.type);
    final market = ev.describe(s.market, s.homeTeam, s.awayTeam);
    return Scaffold(
      appBar: AppBar(
        title: const Text("KING'S VISA REPORT"),
        actions: [
          IconButton(
            tooltip: 'Edit evidence',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SelectionEditorScreen(initial: s))),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => _menu(v, item),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'audit', child: Text('Re-run audit')),
              PopupMenuItem(value: 'bet', child: Text('Record paper bet')),
              PopupMenuItem(value: 'outcome', child: Text('Record actual result')),
              PopupMenuItem(value: 'history', child: Text('Audit history')),
              PopupMenuItem(value: 'delete', child: Text('Delete selection')),
            ],
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        // Required summary block.
        Card(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14), side: BorderSide(color: AppColors.verdict(r?.verdict), width: 1.2)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(s.matchLabel, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                VerdictChip(r?.verdict),
              ]),
              const SizedBox(height: 8),
              KV('MATCH', '${s.homeTeam} vs ${s.awayTeam}'),
              KV('COMPETITION', '${s.league}${s.country.isEmpty ? '' : ' · ${s.country}'}'),
              KV('KICKOFF', EatTime.format(s.kickoff)),
              KV('MARKET', market),
              KV('ODDS', '${s.odds?.toStringAsFixed(2) ?? '—'}${s.oddsSource.isEmpty ? '' : ' (${s.oddsSource})'} · ${EatTime.ago(s.oddsUpdatedAt)}'),
              KV("KING'S VISA", r?.verdict.label ?? 'NOT AUDITED', valueColor: AppColors.verdict(r?.verdict)),
              KV('EVIDENCE SCORE', r?.score == null ? 'Not computable (gates not passed)' : '${r!.score!.total.toStringAsFixed(1)} / 100 — evidence strength, NOT a win probability'),
              if (r != null) ...[
                KV('FAILS IF', r.failureCondition, valueColor: AppColors.fail),
                KV('FAILURE EVIDENCE', r.failureEvidence),
                KV('PRIMARY RISK', r.primaryRisk),
                KV('FINAL REASONING', r.reasoning),
                KV('AUDITED', '${EatTime.format(r.createdAt)} · ${r.engineVersion}'),
              ],
              Row(children: [
                const Text('Data origin: ', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                OriginBadge(s.origin),
                const SizedBox(width: 6),
                Text('updated ${EatTime.ago(s.dataUpdatedAt)}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              ]),
            ]),
          ),
        ),
        if (r == null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: () => _menu('audit', item),
              icon: const Icon(Icons.verified_outlined),
              label: const Text("RUN KING'S VISA"),
            ),
          )
        else ...[
          for (final st in r.stages) _StageCard(st),
          if (r.score != null) _scoreCard(r.score!),
          _aiCard(item),
        ],
      ]),
    );
  }

  Widget _scoreCard(EvidenceScore sc) => SectionCard(
        title: 'Evidence score breakdown',
        icon: Icons.stacked_bar_chart,
        child: Column(children: [
          for (final e in sc.components.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(flex: 5, child: Text(EngineConfig.weightLabels[e.key] ?? e.key, style: const TextStyle(fontSize: 12))),
                Expanded(
                  flex: 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                        value: e.value, minHeight: 8, backgroundColor: AppColors.graphite2, color: AppColors.gold),
                  ),
                ),
                SizedBox(
                  width: 70,
                  child: Text(' ${(e.value * 100).toStringAsFixed(0)} × w${(sc.weights[e.key] ?? 0).toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                ),
              ]),
            ),
          const Divider(),
          const Text('Score = Σ(component × weight) / Σweights × 100. Weights are configurable in Settings. '
              'Computed only after the VISA gates; it can never override them.',
              style: TextStyle(fontSize: 11, color: AppColors.muted)),
        ]),
      );

  Widget _aiCard(AuditedSelection item) {
    final ai = ref.watch(aiExplainerProvider).value;
    return SectionCard(
      title: 'AI explanation (optional)',
      icon: Icons.psychology_alt_outlined,
      trailing: const OriginBadge(DataOrigin.modelGenerated),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Model-generated commentary. It is not evidence, is never stored as a statistic, and cannot change '
            'the deterministic verdict.', style: TextStyle(fontSize: 11, color: AppColors.muted)),
        const SizedBox(height: 8),
        if (ai == null)
          const Text('No AI provider key configured (Settings → AI analysis).', style: TextStyle(fontSize: 12))
        else if (_ai != null)
          SelectableText(_ai!, style: const TextStyle(fontSize: 13))
        else
          OutlinedButton.icon(
            onPressed: _aiBusy
                ? null
                : () async {
                    setState(() {
                      _aiBusy = true;
                      _aiError = null;
                    });
                    try {
                      final t = await ai.explain(item.selection, item.audit!);
                      setState(() => _ai = t);
                    } catch (e) {
                      setState(() => _aiError = '$e');
                    } finally {
                      if (mounted) setState(() => _aiBusy = false);
                    }
                  },
            icon: _aiBusy
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
            label: const Text('Explain this audit'),
          ),
        if (_aiError != null) ErrorBanner(_aiError!),
      ]),
    );
  }

  Future<void> _menu(String v, AuditedSelection item) async {
    final s = item.selection;
    final ctl = ref.read(selectionsProvider.notifier);
    switch (v) {
      case 'audit':
        await ctl.audit(s.id!);
        if (mounted) toast(context, 'Audit complete.');
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete selection?'),
            content: const Text('Its evidence and audit history will be removed.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
            ],
          ),
        );
        if (ok == true) {
          await ctl.delete(s.id!);
          if (mounted) Navigator.pop(context);
        }
      case 'outcome':
        final o = await showDialog<String>(
          context: context,
          builder: (_) => SimpleDialog(title: const Text('Actual result of this market'), children: [
            for (final x in ['won', 'lost', 'void'])
              SimpleDialogOption(onPressed: () => Navigator.pop(context, x), child: Text(x.toUpperCase())),
            SimpleDialogOption(onPressed: () => Navigator.pop(context, 'clear'), child: const Text('Clear')),
          ]),
        );
        if (o != null) await ctl.setOutcome(s.id!, o == 'clear' ? null : o);
      case 'bet':
        await recordPaperBet(context, ref, label: '${s.matchLabel} — ${MarketRegistry.of(s.market.type).describe(s.market, s.homeTeam, s.awayTeam)}',
            odds: s.odds, selectionIds: [s.id!], verdict: item.verdict);
      case 'history':
        final hist = await ref.read(databaseProvider).auditHistory(s.id!);
        if (!mounted) return;
        showModalBottomSheet<void>(
          context: context,
          builder: (_) => ListView(children: [
            const ListTile(title: Text('AUDIT HISTORY (immutable snapshots)')),
            for (final h in hist)
              ListTile(
                title: Text(EatTime.format(h.createdAt)),
                subtitle: Text(h.stages.map((x) => '${x.stage}:${x.outcome.label}').join('  ')),
                trailing: VerdictChip(h.verdict, dense: true),
              ),
          ]),
        );
    }
  }
}

/// Records a bet in the CAPITAL CONTROL ledger with the stake advice applied.
Future<void> recordPaperBet(BuildContext context, WidgetRef ref,
    {required String label, double? odds, List<int> selectionIds = const [], FinalVerdict? verdict}) async {
  final settings = ref.read(settingsProvider).value ?? const AppSettings();
  final m = ref.read(metricsProvider) ?? CapitalEngine.compute(const [], settings.capital);
  final advice = CapitalEngine.recommendStake(settings.capital, m);
  final stakeC = TextEditingController(text: advice.stake.toStringAsFixed(0));
  final oddsC = TextEditingController(text: odds?.toStringAsFixed(2) ?? '');
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(settings.capital.paperMode ? 'Record PAPER bet' : 'Record bet (real-money ledger)'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (verdict != FinalVerdict.approved)
            ErrorBanner('This selection is ${verdict?.label ?? 'NOT AUDITED'}, not APPROVED.', color: AppColors.watch),
          const SizedBox(height: 8),
          TextField(controller: oddsC, decoration: const InputDecoration(labelText: 'Decimal odds'), keyboardType: TextInputType.number),
          const SizedBox(height: 8),
          TextField(controller: stakeC, decoration: InputDecoration(labelText: 'Stake (${settings.capital.currency})'), keyboardType: TextInputType.number),
          const SizedBox(height: 6),
          Text('Advised stake ${money(advice.stake, settings.capital.currency)}: ${advice.reasons.join(' ')}',
              style: const TextStyle(fontSize: 11, color: AppColors.muted)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: advice.blocked ? null : () => Navigator.pop(context, true), child: const Text('Record')),
      ],
    ),
  );
  if (ok != true) return;
  final stake = double.tryParse(stakeC.text) ?? 0;
  final o = double.tryParse(oddsC.text) ?? 0;
  if (stake <= 0 || o <= 1) {
    if (context.mounted) toast(context, 'Invalid stake or odds.');
    return;
  }
  // Never allow more than the user-defined maximum stake.
  final maxStake = m.current * settings.capital.maxStakePercent / 100;
  if (stake > maxStake + 0.5) {
    if (context.mounted) toast(context, 'Stake exceeds your ${settings.capital.maxStakePercent}% max-stake limit (${money(maxStake)}).');
    return;
  }
  await ref.read(betsProvider.notifier).save(Bet(
        createdAt: DateTime.now().toUtc(),
        label: label,
        odds: o,
        stake: stake,
        paper: settings.capital.paperMode,
        selectionIds: selectionIds,
      ));
  if (context.mounted) toast(context, 'Bet recorded in Capital Control.');
}

class _StageCard extends StatelessWidget {
  const _StageCard(this.st);
  final VisaStageResult st;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.outcome(st.outcome);
    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: st.outcome != VisaOutcome.pass,
          leading: CircleAvatar(
            backgroundColor: c.withValues(alpha: 0.2),
            child: Text(st.stage, style: TextStyle(color: c, fontWeight: FontWeight.w900)),
          ),
          title: Text('VISA ${st.stage} — ${st.title}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          subtitle: Text(st.outcome.label, style: TextStyle(color: c, fontWeight: FontWeight.w800)),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final f in st.findings) _finding(f),
            if (st.stats.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('FAILURE RATES (failures / valid comparable observations)',
                  style: TextStyle(color: AppColors.gold, fontSize: 11, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 30,
                  dataRowMinHeight: 28,
                  dataRowMaxHeight: 32,
                  columnSpacing: 14,
                  columns: const [
                    DataColumn(label: Text('Window')),
                    DataColumn(label: Text('Fail'), numeric: true),
                    DataColumn(label: Text('Valid'), numeric: true),
                    DataColumn(label: Text('Rate'), numeric: true),
                    DataColumn(label: Text('Unknown'), numeric: true),
                    DataColumn(label: Text('Void'), numeric: true),
                    DataColumn(label: Text('Excl.'), numeric: true),
                  ],
                  rows: [
                    for (final s in st.stats)
                      DataRow(cells: [
                        DataCell(Text(s.label, style: const TextStyle(fontSize: 12))),
                        DataCell(Text('${s.failures}')),
                        DataCell(Text('${s.valid}')),
                        DataCell(Text(pct(s.failureRate, digits: 0))),
                        DataCell(Text('${s.unknown}')),
                        DataCell(Text('${s.pushes}')),
                        DataCell(Text('${s.nonComparable}')),
                      ]),
                  ],
                ),
              ),
            ],
            for (final e in st.records.entries) ...[
              const SizedBox(height: 8),
              Text('SOURCE RECORDS — ${e.key.toUpperCase()}',
                  style: const TextStyle(color: AppColors.gold, fontSize: 11, fontWeight: FontWeight.w700)),
              for (final rec in e.value)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Icon(Icons.circle,
                        size: 9,
                        color: rec.settlement.isFailure
                            ? AppColors.fail
                            : rec.settlement == Settlement.unknown
                                ? AppColors.unknown
                                : AppColors.pass),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${EatTime.formatDate(rec.date)}  ${rec.label}  → ${rec.settlement.name.toUpperCase()}'
                        '${rec.margin == null ? '' : ' (margin ${rec.margin!.toStringAsFixed(1)})'}'
                        '${rec.comparable ? '' : ' · excluded'}${rec.note.isEmpty ? '' : ' · ${rec.note}'}',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                    OriginBadge(rec.origin),
                  ]),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _finding(Finding f) {
    final (icon, color) = switch (f.level) {
      FindingLevel.ok => (Icons.check_circle_outline, AppColors.pass),
      FindingLevel.watch => (Icons.visibility_outlined, AppColors.watch),
      FindingLevel.fail => (Icons.cancel_outlined, AppColors.fail),
      FindingLevel.unknown => (Icons.help_outline, AppColors.unknown),
      FindingLevel.info => (Icons.info_outline, AppColors.muted),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(f.text, style: const TextStyle(fontSize: 12.5))),
      ]),
    );
  }
}
