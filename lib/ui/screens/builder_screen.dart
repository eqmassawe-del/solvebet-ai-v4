import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../builder/accumulator_builder.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import 'visa_report_screen.dart';

/// KING'S BUILDER — best-of-available accumulator from audited selections.
class BuilderScreen extends ConsumerStatefulWidget {
  const BuilderScreen({super.key});
  @override
  ConsumerState<BuilderScreen> createState() => _BuilderScreenState();
}

class _BuilderScreenState extends ConsumerState<BuilderScreen> {
  double _target = 5;
  int _maxLegs = 5;
  double _minScore = 60;
  int _maxPerLeague = 2;
  BuilderResult? _result;
  final _custom = TextEditingController();

  void _run() {
    final all = ref.read(selectionsProvider).value ?? [];
    final settings = ref.read(settingsProvider).value ?? const AppSettings();
    final pool = all
        .where((a) => settings.includeEnglishLeagues || !isEnglishLeague(a.selection))
        .map((a) => BuilderCandidate(a.selection, a.audit))
        .toList();
    setState(() => _result = AccumulatorBuilder().build(
        pool,
        BuilderRequest(
          targetOdds: _target,
          maxLegs: _maxLegs,
          minLegScore: _minScore,
          maxPerLeague: _maxPerLeague,
        )));
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return ListView(padding: const EdgeInsets.all(12), children: [
      SectionCard(
        title: 'Target & constraints',
        icon: Icons.tune,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Target combined decimal odds', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final t in [2.0, 5.0, 10.0, 20.0, 50.0, 100.0])
              ChoiceChip(label: Text(t.toStringAsFixed(0)), selected: _target == t, onSelected: (_) => setState(() => _target = t)),
            SizedBox(
              width: 90,
              child: TextField(
                controller: _custom,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(hintText: 'Custom'),
                onChanged: (v) {
                  final x = double.tryParse(v);
                  if (x != null && x > 1) setState(() => _target = x);
                },
              ),
            ),
          ]),
          const SizedBox(height: 8),
          _slider('Max legs', _maxLegs.toDouble(), 1, 10, (v) => setState(() => _maxLegs = v.round()), '$_maxLegs'),
          _slider('Min evidence score per leg', _minScore, 0, 95, (v) => setState(() => _minScore = v.roundToDouble()),
              _minScore.toStringAsFixed(0)),
          _slider('Max legs per league', _maxPerLeague.toDouble(), 1, 5, (v) => setState(() => _maxPerLeague = v.round()),
              '$_maxPerLeague'),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(onPressed: _run, icon: const Icon(Icons.account_tree), label: const Text('BUILD STRONGEST COMBINATION')),
          ),
          const SizedBox(height: 6),
          const Text(
            'Only APPROVED selections are eligible. WATCH, INCOMPLETE and REJECTED are removed automatically. '
            'Legs are not assumed independent and no accumulator win probability is computed.',
            style: TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ]),
      ),
      if (r != null) ...[
        ErrorBanner(r.message,
            color: r.best == null ? AppColors.fail : (r.targetReached ? AppColors.pass : AppColors.watch),
            icon: r.targetReached ? Icons.check_circle_outline : Icons.warning_amber),
        if (r.best != null) _comboCard('Recommended combination', r.best!, highlight: true),
        if (r.shortlist.length > 1)
          SectionCard(
            title: 'Ranked shortlist',
            icon: Icons.format_list_numbered,
            child: Column(children: [
              for (final (i, c) in r.shortlist.indexed)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Text('#${i + 1}', style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800)),
                  title: Text('${c.legs.length} leg(s) @ ${c.combinedOdds.toStringAsFixed(2)}'),
                  subtitle: Text('quality ${c.quality.toStringAsFixed(1)} · min score ${c.minScore.toStringAsFixed(0)}'
                      '${c.warnings.isEmpty ? '' : ' · ${c.warnings.length} exposure warning(s)'}'),
                  onTap: () => showModalBottomSheet<void>(
                      context: context, isScrollControlled: true, builder: (_) => SingleChildScrollView(child: _comboCard('Shortlist #${i + 1}', c))),
                ),
            ]),
          ),
        SectionCard(
          title: 'Excluded (${r.excluded.length})',
          icon: Icons.block,
          child: r.excluded.isEmpty
              ? const Text('Nothing excluded.', style: TextStyle(color: AppColors.muted))
              : Column(children: [
                  for (final e in r.excluded)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.remove_circle_outline, size: 14, color: AppColors.fail),
                        const SizedBox(width: 6),
                        Expanded(child: Text('${e.label}\n${e.reason}', style: const TextStyle(fontSize: 12))),
                      ]),
                    ),
                ]),
        ),
      ],
    ]);
  }

  Widget _slider(String label, double v, double min, double max, ValueChanged<double> on, String shown) => Row(children: [
        SizedBox(width: 150, child: Text(label, style: const TextStyle(fontSize: 12))),
        Expanded(child: Slider(value: v, min: min, max: max, divisions: (max - min).round(), onChanged: on)),
        SizedBox(width: 30, child: Text(shown, textAlign: TextAlign.end)),
      ]);

  Widget _comboCard(String title, AccaCombo c, {bool highlight = false}) {
    final settings = ref.read(settingsProvider).value ?? const AppSettings();
    return SectionCard(
      title: title,
      icon: highlight ? Icons.workspace_premium : Icons.list_alt,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        StatGrid([
          StatTile('Combined odds', c.combinedOdds.toStringAsFixed(2), color: AppColors.gold),
          StatTile('Legs', '${c.legs.length}'),
          StatTile('Weakest leg score', c.minScore.toStringAsFixed(0)),
          StatTile('Bookmaker-implied', pct(c.bookmakerImplied), sub: '1/odds incl. margin — not our estimate'),
        ]),
        const SizedBox(height: 8),
        for (final l in c.legs)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(l.label),
            subtitle: Text('${l.selection.league} · score ${l.score.toStringAsFixed(0)}'),
            trailing: Text(l.selection.odds!.toStringAsFixed(2), style: const TextStyle(color: AppColors.gold)),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VisaReportScreen(selectionId: l.selection.id!))),
          ),
        if (c.warnings.isNotEmpty) ...[
          const Text('CORRELATION & EXPOSURE', style: TextStyle(color: AppColors.watch, fontSize: 11, fontWeight: FontWeight.w700)),
          for (final w in c.warnings) Text('• $w', style: const TextStyle(fontSize: 12)),
        ],
        const SizedBox(height: 6),
        Text('Potential capital loss: the entire stake. Every added leg is another way to lose.',
            style: TextStyle(fontSize: 11, color: AppColors.fail.withValues(alpha: 0.9))),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          icon: const Icon(Icons.add_card),
          label: Text(settings.capital.paperMode ? 'Record as paper bet' : 'Record bet'),
          onPressed: () => recordPaperBet(
            context,
            ref,
            label: 'ACCA ${c.legs.length} legs: ${c.legs.map((l) => l.selection.matchLabel).join(' + ')}',
            odds: c.combinedOdds,
            selectionIds: [for (final l in c.legs) l.selection.id!],
            verdict: c.legs.first.report?.verdict,
          ),
        ),
      ]),
    );
  }
}
