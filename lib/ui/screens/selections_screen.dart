import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme.dart';
import '../../core/time.dart';
import '../../domain/enums.dart';
import '../../engine/markets/markets.dart';
import '../../state/providers.dart';
import '../import_actions.dart';
import '../widgets/common.dart';
import 'selection_editor_screen.dart';
import 'visa_report_screen.dart';

class SelectionsScreen extends ConsumerStatefulWidget {
  const SelectionsScreen({super.key});
  @override
  ConsumerState<SelectionsScreen> createState() => _SelectionsScreenState();
}

class _SelectionsScreenState extends ConsumerState<SelectionsScreen> {
  String _q = '';
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(selectionsProvider);
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final s = ref.watch(stringsProvider);

    return DefaultTabController(
      length: 6,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search team, league, market'),
                onChanged: (v) => setState(() => _q = v.toLowerCase()),
              ),
            ),
            const SizedBox(width: 6),
            PopupMenuButton<String>(
              icon: const Icon(Icons.add_circle, color: AppColors.gold, size: 30),
              onSelected: (v) async {
                switch (v) {
                  case 'new':
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const SelectionEditorScreen()));
                  case 'import':
                    await importSelectionsFile(context, ref);
                  case 'slip':
                    await importSlipScreenshot(context, ref);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'new', child: Text(s.t('new_selection'))),
                PopupMenuItem(value: 'import', child: Text(s.t('import'))),
                PopupMenuItem(value: 'slip', child: Text(s.t('import_slip'))),
              ],
            ),
          ]),
        ),
        Row(children: [
          const Expanded(
            child: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
              Tab(text: 'APPROVED · RANKED'),
              Tab(text: 'WATCH'),
              Tab(text: 'INCOMPLETE'),
              Tab(text: 'REJECTED'),
              Tab(text: 'NOT AUDITED'),
              Tab(text: 'ALL'),
            ]),
          ),
          IconButton(
            tooltip: 'Re-audit all',
            icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    final n = await ref.read(selectionsProvider.notifier).auditAll();
                    if (mounted) {
                      setState(() => _busy = false);
                      toast(this.context, 'Re-audited $n selection(s) with current thresholds.');
                    }
                  },
          ),
        ]),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: ErrorBanner('Database error: $e')),
            data: (all) {
              final filtered = all.where((a) {
                if (_q.isEmpty) return true;
                final x = a.selection;
                return '${x.homeTeam} ${x.awayTeam} ${x.league} ${x.market.type.title}'.toLowerCase().contains(_q);
              }).toList();
              final approved = filtered.where((a) => a.verdict == FinalVerdict.approved).toList()
                ..sort((a, b) => (b.score ?? 0).compareTo(a.score ?? 0));
              final ranked = settings.includeEnglishLeagues
                  ? approved
                  : approved.where((a) => !isEnglishLeague(a.selection)).toList();
              final hiddenEnglish = approved.length - ranked.length;
              List<AuditedSelection> by(FinalVerdict v) => filtered.where((a) => a.verdict == v).toList();
              return TabBarView(children: [
                _list(ranked, ranked: true,
                    header: hiddenEnglish > 0
                        ? ErrorBanner('$hiddenEnglish approved English-league selection(s) hidden from recommendations. Enable in Settings.',
                            color: AppColors.muted, icon: Icons.info_outline)
                        : null,
                    empty: 'No approved selections. The engine only approves when all four VISAs pass on recorded evidence.'),
                _list(by(FinalVerdict.watch), empty: 'No WATCH selections.',
                    header: const ErrorBanner('WATCH selections are excluded from accumulator construction.',
                        color: AppColors.watch, icon: Icons.visibility_outlined)),
                _list(by(FinalVerdict.incomplete), empty: 'No incomplete audits.'),
                _list(by(FinalVerdict.rejected), empty: 'No rejected selections.'),
                _list(filtered.where((a) => a.audit == null).toList(), empty: 'Every selection has been audited.'),
                _list(filtered, empty: 'No selections yet. Add one manually, import a file, or use the scanner.'),
              ]);
            },
          ),
        ),
      ]),
    );
  }

  Widget _list(List<AuditedSelection> items, {required String empty, bool ranked = false, Widget? header}) {
    if (items.isEmpty) {
      return ListView(children: [
        ?header,
        EmptyState(icon: Icons.inbox_outlined, title: 'Nothing here', message: empty),
      ]);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
      itemCount: items.length + (header == null ? 0 : 1),
      itemBuilder: (_, i) {
        if (header != null && i == 0) return header;
        final idx = i - (header == null ? 0 : 1);
        return SelectionCard(items[idx], rank: ranked ? idx + 1 : null);
      },
    );
  }
}

class SelectionCard extends ConsumerWidget {
  const SelectionCard(this.item, {super.key, this.rank});
  final AuditedSelection item;
  final int? rank;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = item.selection;
    final a = item.audit;
    final market = MarketRegistry.of(s.market.type).describe(s.market, s.homeTeam, s.awayTeam);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VisaReportScreen(selectionId: s.id!))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (rank != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: CircleAvatar(
                      radius: 12,
                      backgroundColor: AppColors.gold,
                      child: Text('$rank', style: const TextStyle(color: AppColors.black, fontSize: 12, fontWeight: FontWeight.w800))),
                ),
              Expanded(child: Text(s.matchLabel, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
              VerdictChip(item.verdict, dense: true),
            ]),
            const SizedBox(height: 4),
            Text(market, style: const TextStyle(color: AppColors.goldSoft)),
            const SizedBox(height: 2),
            Text(
              '${s.league.isEmpty ? 'League ?' : s.league} · ${EatTime.format(s.kickoff, pattern: 'd MMM HH:mm')} · '
              'Odds ${s.odds?.toStringAsFixed(2) ?? '?'}',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            if (a != null) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 4, runSpacing: 4, children: [
                for (final st in a.stages) OutcomeChip(st.stage, st.outcome),
                if (a.score != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(border: Border.all(color: AppColors.gold), borderRadius: BorderRadius.circular(6)),
                    child: Text('EVIDENCE ${a.score!.total.toStringAsFixed(0)}/100',
                        style: const TextStyle(color: AppColors.gold, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
              ]),
              const SizedBox(height: 6),
              Text('Primary risk: ${a.primaryRisk}', maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12)),
            ],
            if (s.actualOutcome != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Recorded result: ${s.actualOutcome!.toUpperCase()}',
                    style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              ),
          ]),
        ),
      ),
    );
  }
}
