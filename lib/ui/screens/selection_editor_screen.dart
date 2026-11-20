import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme.dart';
import '../../core/time.dart';
import '../../data/import/importer.dart';
import '../../domain/enums.dart';
import '../../domain/market.dart';
import '../../domain/match_data.dart';
import '../../domain/selection.dart';
import '../../engine/markets/markets.dart';
import '../../engine/visa_b.dart';
import '../../engine/visa_d.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import 'visa_report_screen.dart';

/// Manual-entry editor for every input the KING'S VISA engine uses.
class SelectionEditorScreen extends ConsumerStatefulWidget {
  const SelectionEditorScreen({super.key, this.initial});
  final Selection? initial;

  @override
  ConsumerState<SelectionEditorScreen> createState() => _EditorState();
}

class _EditorState extends ConsumerState<SelectionEditorScreen> {
  late final _home = TextEditingController(text: widget.initial?.homeTeam ?? '');
  late final _away = TextEditingController(text: widget.initial?.awayTeam ?? '');
  late final _league = TextEditingController(text: widget.initial?.league ?? '');
  late final _country = TextEditingController(text: widget.initial?.country ?? '');
  late final _odds = TextEditingController(text: widget.initial?.odds?.toString() ?? '');
  late final _oddsSource = TextEditingController(text: widget.initial?.oddsSource ?? '');
  late final _notes = TextEditingController(text: widget.initial?.notes ?? '');
  late final _line = TextEditingController(text: widget.initial?.market.line?.toString() ?? '');
  late final _cName = TextEditingController(text: widget.initial?.market.customName ?? '');
  late final _cWin = TextEditingController(text: widget.initial?.market.customWinCondition ?? '');
  late final _cFail = TextEditingController(text: widget.initial?.market.customFailCondition ?? '');

  late DateTime? _kickoff = widget.initial?.kickoff;
  late MarketType _type = widget.initial?.market.type ?? MarketType.overUnderGoals;
  late String _pick = widget.initial?.market.pick ?? '';
  late Side? _side = widget.initial?.market.side;
  late final DateTime? _oddsAt = widget.initial?.oddsUpdatedAt;
  bool _confirmOddsNow = false;
  late List<HistoricalMatch> _homeHist = [...?widget.initial?.homeHistory];
  late List<HistoricalMatch> _awayHist = [...?widget.initial?.awayHistory];
  late final List<StructuralCheck> _checks = [...(widget.initial?.checks ?? StructuralCheck.defaults())];
  late List<StressScenario> _scenarios = [...?widget.initial?.scenarios];
  bool _saving = false;

  bool get _isEdit => widget.initial?.id != null;

  MarketSpec get _spec => MarketSpec(
        type: _type,
        pick: _pick,
        side: _side,
        line: double.tryParse(_line.text.trim()),
        customName: _cName.text,
        customWinCondition: _cWin.text,
        customFailCondition: _cFail.text,
      );

  Selection _build() {
    final odds = double.tryParse(_odds.text.trim().replaceAll(',', '.'));
    return Selection(
      id: widget.initial?.id,
      matchRef: widget.initial?.matchRef ?? '',
      homeTeam: _home.text.trim(),
      awayTeam: _away.text.trim(),
      league: _league.text.trim(),
      country: _country.text.trim(),
      kickoff: _kickoff,
      market: _spec,
      odds: odds,
      oddsSource: _oddsSource.text.trim(),
      oddsUpdatedAt: _confirmOddsNow ? DateTime.now().toUtc() : _oddsAt,
      origin: widget.initial?.origin ?? DataOrigin.userEntered,
      notes: _notes.text,
      homeHistory: _homeHist,
      awayHistory: _awayHist,
      checks: _checks,
      scenarios: _scenarios,
      actualOutcome: widget.initial?.actualOutcome,
      createdAt: widget.initial?.createdAt,
    );
  }

  List<String> get _pickOptions => switch (_type) {
        MarketType.matchResult => ['home', 'draw', 'away'],
        MarketType.doubleChance => ['1X', 'X2', '12'],
        MarketType.btts || MarketType.anyTeam3InARow || MarketType.teamConsecutiveGoals => ['yes', 'no'],
        MarketType.handicap || MarketType.drawNoBet || MarketType.custom => [],
        _ => ['over', 'under'],
      };

  bool get _needsSide => const {
        MarketType.teamTotalGoals,
        MarketType.teamCorners,
        MarketType.handicap,
        MarketType.drawNoBet,
        MarketType.teamConsecutiveGoals,
      }.contains(_type);

  bool get _needsLine => const {
        MarketType.overUnderGoals,
        MarketType.firstHalfGoals,
        MarketType.secondHalfGoals,
        MarketType.teamTotalGoals,
        MarketType.totalCorners,
        MarketType.teamCorners,
        MarketType.handicap,
      }.contains(_type);

  Future<void> _save({bool audit = true}) async {
    final s = _build();
    if (s.homeTeam.isEmpty || s.awayTeam.isEmpty) {
      toast(context, 'Enter both team names (missing identity cannot be audited).');
      return;
    }
    setState(() => _saving = true);
    try {
      final ctl = ref.read(selectionsProvider.notifier);
      final id = await ctl.save(s);
      if (audit) await ctl.audit(id);
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => VisaReportScreen(selectionId: id)));
    } catch (e) {
      if (mounted) toast(context, 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEdit ? 'EDIT SELECTION' : 'NEW SELECTION'),
          bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(text: 'A · MATCH & MARKET'),
            Tab(text: 'B · EVIDENCE'),
            Tab(text: 'C · STRUCTURE'),
            Tab(text: 'D · STRESS'),
          ]),
        ),
        body: TabBarView(children: [_identityTab(), _evidenceTab(), _structureTab(), _stressTab()]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(onPressed: _saving ? null : () => _save(audit: false), child: const Text('Save draft')),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.verified_outlined),
                  label: const Text("SAVE & RUN KING'S VISA"),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- VISA A tab
  Widget _identityTab() {
    final ev = MarketRegistry.of(_type);
    final v = ev.validate(_spec);
    final h = _home.text.isEmpty ? 'Home' : _home.text, a = _away.text.isEmpty ? 'Away' : _away.text;
    return ListView(padding: const EdgeInsets.all(12), children: [
      SectionCard(
        title: 'Match identity',
        icon: Icons.sports_soccer,
        child: Column(children: [
          _tf(_home, 'Home team *', onChanged: (_) => setState(() {})),
          _tf(_away, 'Away team *', onChanged: (_) => setState(() {})),
          Row(children: [
            Expanded(child: _tf(_league, 'League / competition *')),
            const SizedBox(width: 8),
            Expanded(child: _tf(_country, 'Country')),
          ]),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: Text(_kickoff == null ? 'Set kickoff (EAT) *' : EatTime.format(_kickoff)),
            subtitle: const Text('Entered in Africa/Dar_es_Salaam time'),
            onTap: _pickKickoff,
          ),
        ]),
      ),
      SectionCard(
        title: 'Market definition',
        icon: Icons.rule,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DropdownButtonFormField<MarketType>(
            initialValue: _type,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Market'),
            items: [
              for (final t in MarketType.values) DropdownMenuItem(value: t, child: Text('${t.title}  ·  ${t.group}')),
            ],
            onChanged: (t) => setState(() {
              _type = t!;
              _pick = _pickOptions.isEmpty ? '' : (_pickOptions.contains(_pick) ? _pick : '');
              if (!_needsSide) _side = null;
            }),
          ),
          const SizedBox(height: 8),
          if (_pickOptions.isNotEmpty)
            Wrap(spacing: 6, children: [
              for (final p in _pickOptions)
                ChoiceChip(label: Text(p.toUpperCase()), selected: _pick == p, onSelected: (_) => setState(() => _pick = p)),
            ]),
          if (_needsSide) ...[
            const SizedBox(height: 8),
            SegmentedButton<Side>(
              segments: [
                ButtonSegment(value: Side.home, label: Text(h, overflow: TextOverflow.ellipsis)),
                ButtonSegment(value: Side.away, label: Text(a, overflow: TextOverflow.ellipsis)),
              ],
              emptySelectionAllowed: true,
              selected: {?_side},
              onSelectionChanged: (s) => setState(() => _side = s.isEmpty ? null : s.first),
            ),
          ],
          if (_needsLine) ...[
            const SizedBox(height: 8),
            _tf(_line, _type == MarketType.handicap ? 'Handicap line (e.g. -1.5, +0.25)' : 'Line (e.g. 2.5)',
                keyboard: const TextInputType.numberWithOptions(decimal: true, signed: true), onChanged: (_) => setState(() {})),
          ],
          if (_type == MarketType.custom) ...[
            const SizedBox(height: 8),
            const ErrorBanner('Unfamiliar market: define exactly when it wins and which event makes it lose. '
                'In Evidence, record WIN/LOSE for each past match yourself.', color: AppColors.watch, icon: Icons.help_outline),
            _tf(_cName, 'Market name *', onChanged: (_) => setState(() {})),
            _tf(_cWin, 'Exact WIN condition *', lines: 2, onChanged: (_) => setState(() {})),
            _tf(_cFail, 'Exact FAILURE event *', lines: 2, onChanged: (_) => setState(() {})),
          ],
          const SizedBox(height: 10),
          if (!v.ok)
            ErrorBanner(v.problems.join('\n'), color: AppColors.unknown, icon: Icons.help_outline)
          else ...[
            KV('Selection', ev.describe(_spec, h, a)),
            KV('Wins when', ev.winCondition(_spec, h, a)),
            KV('FAILS when', ev.failCondition(_spec, h, a), valueColor: AppColors.fail),
            KV('Binary market', MarketRegistry.isBinary(_spec) ? 'Yes — clear settlement' : 'No (push / split possible)'),
          ],
        ]),
      ),
      SectionCard(
        title: 'Price',
        icon: Icons.price_change_outlined,
        child: Column(children: [
          Row(children: [
            Expanded(child: _tf(_odds, 'Decimal odds *', keyboard: const TextInputType.numberWithOptions(decimal: true))),
            const SizedBox(width: 8),
            Expanded(child: _tf(_oddsSource, 'Bookmaker / source')),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _confirmOddsNow,
            onChanged: (v) => setState(() => _confirmOddsNow = v),
            title: const Text('I confirm these odds are the current price'),
            subtitle: Text('Odds timestamp: ${_confirmOddsNow ? 'now (on save)' : EatTime.format(_oddsAt)}'),
          ),
        ]),
      ),
      SectionCard(title: 'Notes', child: _tf(_notes, 'Notes (not used as evidence)', lines: 3)),
    ]);
  }

  Future<void> _pickKickoff() async {
    final base = _kickoff == null ? EatTime.toEat(DateTime.now().toUtc()) : EatTime.toEat(_kickoff!);
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(base.year, base.month, base.day),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: base.hour, minute: base.minute));
    if (t == null) return;
    setState(() => _kickoff = EatTime.fromEatWallClock(d.year, d.month, d.day, t.hour, t.minute));
  }

  // ------------------------------------------------------------- VISA B tab
  Widget _evidenceTab() {
    final s = _build();
    return ListView(padding: const EdgeInsets.all(12), children: [
      const ErrorBanner(
        'Enter each team\'s most recent completed matches (aim for 10). Leave a field blank when unknown — '
        'blank is recorded as UNKNOWN, never assumed. Goal order: e.g. 12H,40A,77H (H/A = home/away side of THAT match); "-" for 0-0.',
        color: AppColors.muted,
        icon: Icons.info_outline,
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(onPressed: _importHistoryCsv, icon: const Icon(Icons.upload_file), label: const Text('Import history CSV')),
      ),
      for (final side in Side.values) _historySection(s, side),
    ]);
  }

  Widget _historySection(Selection s, Side side) {
    final team = side == Side.home ? _home.text : _away.text;
    final list = side == Side.home ? _homeHist : _awayHist;
    final sorted = [...list]..sort((a, b) => b.date.compareTo(a.date));
    return SectionCard(
      title: '${team.isEmpty ? side.name : team} — recent matches (${list.length})',
      icon: Icons.history,
      trailing: IconButton(
        icon: const Icon(Icons.add, color: AppColors.gold),
        onPressed: team.isEmpty ? () => toast(context, 'Enter the team names first.') : () => _editMatch(side, null),
      ),
      child: sorted.isEmpty
          ? const Text('No matches recorded → VISA B will be UNKNOWN.', style: TextStyle(color: AppColors.muted))
          : Column(children: [
              for (final m in sorted)
                Builder(builder: (_) {
                  final st = settleOne(s, side, m);
                  final c = st == null
                      ? AppColors.fail
                      : st.isFailure
                          ? AppColors.fail
                          : st == Settlement.unknown
                              ? AppColors.unknown
                              : AppColors.pass;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.circle, size: 12, color: c),
                    title: Text('${m.homeTeam} ${m.scoreLabel} ${m.awayTeam}'),
                    subtitle: Text(
                        '${EatTime.formatDate(m.date)} · ${st == null ? 'TEAM NOT IN RECORD' : st.name.toUpperCase()}'
                        '${m.comparable ? '' : ' · non-comparable'}${m.goalSequence == null ? ' · order unknown' : ''}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      OriginBadge(m.origin),
                      IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => setState(() => list.remove(m))),
                    ]),
                    onTap: () => _editMatch(side, m),
                  );
                }),
            ]),
    );
  }

  Future<void> _importHistoryCsv() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['csv']);
    if (files.isEmpty) return;
    final r = Importer.historyFromCsv(await files.first.xFile.readAsString());
    setState(() {
      _homeHist = [..._homeHist, ...r.home];
      _awayHist = [..._awayHist, ...r.away];
    });
    if (mounted) {
      toast(context, 'Imported ${r.home.length + r.away.length} match(es)${r.errors.isEmpty ? '' : ', ${r.errors.length} error(s): ${r.errors.first}'}');
    }
  }

  Future<void> _editMatch(Side side, HistoricalMatch? m) async {
    final team = side == Side.home ? _home.text.trim() : _away.text.trim();
    final res = await showDialog<HistoricalMatch>(
      context: context,
      builder: (_) => _MatchDialog(team: team, initial: m, custom: _type == MarketType.custom),
    );
    if (res == null) return;
    setState(() {
      final list = side == Side.home ? _homeHist : _awayHist;
      if (m != null) list.remove(m);
      list.add(res);
    });
  }

  // ------------------------------------------------------------- VISA C tab
  Widget _structureTab() {
    final hist = [..._homeHist, ..._awayHist].where((m) => m.hasRedCardData).toList();
    final reds = hist.where((m) => m.hadRedCard).length;
    return ListView(padding: const EdgeInsets.all(12), children: [
      const ErrorBanner(
        'Mandatory: motivation, line-ups, injuries/suspensions and RED-CARD exposure. Red cards cannot be predicted '
        'reliably — document the evidence AND the uncertainty, and whether a sending-off would open a failure pathway.',
        color: AppColors.watch,
        icon: Icons.gpp_maybe_outlined,
      ),
      for (var i = 0; i < _checks.length; i++)
        _CheckCard(
          key: ValueKey(_checks[i].factor),
          check: _checks[i],
          context2: _checks[i].factor == StructuralFactor.redCardExposure
              ? 'History: $reds of ${hist.length} recorded matches with card data had a red card.'
              : null,
          onChanged: (c) => _checks[i] = c,
          onStatus: (c) => setState(() => _checks[i] = c),
        ),
    ]);
  }

  // ------------------------------------------------------------- VISA D tab
  Widget _stressTab() {
    final s = _build();
    return ListView(padding: const EdgeInsets.all(12), children: [
      const ErrorBanner(
        'Try to DEFEAT the selection. For each scenario record the plausibility evidence, severity and whether the '
        'evidence suffices. No numeric probabilities are assigned. CRITICAL = plausible scenario that defeats the bet → REJECTED.',
        color: AppColors.muted,
        icon: Icons.bolt_outlined,
      ),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('Generate market scenarios'),
            onPressed: () {
              final templates = MarketRegistry.of(_type).stressTemplates(_spec, _home.text, _away.text);
              setState(() {
                final existing = {for (final x in _scenarios) x.title};
                _scenarios = [
                  ..._scenarios,
                  for (final t in templates)
                    if (!existing.contains(t.title)) t.toScenario(),
                ];
              });
            },
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Add custom scenario',
          icon: const Icon(Icons.add_circle_outline, color: AppColors.gold),
          onPressed: _addCustomScenario,
        ),
      ]),
      if (_scenarios.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('No scenarios yet → VISA D will be UNKNOWN.', style: TextStyle(color: AppColors.muted)),
        ),
      for (var i = 0; i < _scenarios.length; i++)
        _ScenarioCard(
          key: ObjectKey(_scenarios[i].title + i.toString()),
          scenario: _scenarios[i],
          sample: stressSample(s, _scenarios[i].kind),
          onChanged: (x) => _scenarios[i] = x,
          onRebuild: (x) => setState(() => _scenarios[i] = x),
          onDelete: () => setState(() => _scenarios.removeAt(i)),
        ),
    ]);
  }

  Future<void> _addCustomScenario() async {
    final title = TextEditingController(), path = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Custom adverse scenario'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Scenario')),
          const SizedBox(height: 8),
          TextField(controller: path, decoration: const InputDecoration(labelText: 'Failure pathway'), maxLines: 2),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok == true && title.text.trim().isNotEmpty) {
      setState(() => _scenarios.add(StressScenario(
            kind: ScenarioKind.other,
            title: title.text.trim(),
            description: title.text.trim(),
            relevance: 'User-defined scenario for this market.',
            pathway: path.text.trim(),
          )));
    }
  }

  Widget _tf(TextEditingController c, String label,
          {int lines = 1, TextInputType? keyboard, ValueChanged<String>? onChanged}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: TextField(
          controller: c,
          maxLines: lines,
          keyboardType: keyboard,
          onChanged: onChanged,
          decoration: InputDecoration(labelText: label),
        ),
      );
}

class _CheckCard extends StatelessWidget {
  const _CheckCard({super.key, required this.check, required this.onChanged, required this.onStatus, this.context2});
  final StructuralCheck check;
  final ValueChanged<StructuralCheck> onChanged;
  final ValueChanged<StructuralCheck> onStatus;
  final String? context2;

  @override
  Widget build(BuildContext context) {
    final f = check.factor;
    final c = switch (check.status) {
      CheckStatus.clear => AppColors.pass,
      CheckStatus.concern => AppColors.watch,
      CheckStatus.critical => AppColors.fail,
      CheckStatus.notAssessed => AppColors.unknown,
    };
    var current = check;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(f.title, style: const TextStyle(fontWeight: FontWeight.w700))),
            if (f.mandatory)
              const Text('MANDATORY', style: TextStyle(color: AppColors.gold, fontSize: 10, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 4, children: [
            for (final st in CheckStatus.values)
              ChoiceChip(
                label: Text(st.label, style: const TextStyle(fontSize: 11)),
                selected: check.status == st,
                selectedColor: c.withValues(alpha: 0.3),
                onSelected: (_) => onStatus(current.copyWith(status: st, origin: DataOrigin.userEntered)),
              ),
          ]),
          if (context2 != null) Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(context2!, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          ),
          const SizedBox(height: 6),
          TextFormField(
            initialValue: check.evidence,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Evidence (source, what you verified)'),
            onChanged: (v) {
              current = current.copyWith(evidence: v, origin: DataOrigin.userEntered);
              onChanged(current);
            },
          ),
          if (f == StructuralFactor.redCardExposure) ...[
            const SizedBox(height: 6),
            TextFormField(
              initialValue: check.uncertainty,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Uncertainty statement (required)'),
              onChanged: (v) {
                current = current.copyWith(uncertainty: v);
                onChanged(current);
              },
            ),
          ],
          if (check.origin != DataOrigin.userEntered) Padding(padding: const EdgeInsets.only(top: 4), child: OriginBadge(check.origin)),
        ]),
      ),
    );
  }
}

class _ScenarioCard extends StatelessWidget {
  const _ScenarioCard({
    super.key,
    required this.scenario,
    required this.sample,
    required this.onChanged,
    required this.onRebuild,
    required this.onDelete,
  });
  final StressScenario scenario;
  final StressSample? sample;
  final ValueChanged<StressScenario> onChanged;
  final ValueChanged<StressScenario> onRebuild;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final sc = scenario;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(sc.title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.goldSoft))),
            if (sc.kind == ScenarioKind.earlyRedCard)
              const Text('REQUIRED', style: TextStyle(color: AppColors.gold, fontSize: 10, fontWeight: FontWeight.w800))
            else
              IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onDelete),
          ]),
          KV('Scenario', sc.description),
          KV('Relevance', sc.relevance),
          KV('Failure pathway', sc.pathway, valueColor: AppColors.fail),
          if (sample != null) KV('History (engine)', sample!.summary),
          const SizedBox(height: 6),
          TextFormField(
            initialValue: sc.evidence,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Evidence supporting / refuting plausibility'),
            onChanged: (v) => onChanged(sc.copyWith(evidence: v)),
          ),
          const SizedBox(height: 6),
          const Text('Severity', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          Wrap(spacing: 4, children: [
            for (final sv in Severity.values.where((x) => x != Severity.unassessed))
              ChoiceChip(
                label: Text(sv.label, style: const TextStyle(fontSize: 11)),
                selected: sc.severity == sv,
                onSelected: (_) => onRebuild(sc.copyWith(severity: sv)),
              ),
          ]),
          const SizedBox(height: 4),
          const Text('Is the evidence sufficient to assess this?', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          Wrap(spacing: 4, children: [
            ChoiceChip(label: const Text('YES'), selected: sc.evidenceSufficient == true, onSelected: (_) => onRebuild(sc.copyWith(evidenceSufficient: true))),
            ChoiceChip(label: const Text('NO'), selected: sc.evidenceSufficient == false, onSelected: (_) => onRebuild(sc.copyWith(evidenceSufficient: false))),
          ]),
        ]),
      ),
    );
  }
}

class _MatchDialog extends StatefulWidget {
  const _MatchDialog({required this.team, this.initial, required this.custom});
  final String team;
  final HistoricalMatch? initial;
  final bool custom;
  @override
  State<_MatchDialog> createState() => _MatchDialogState();
}

class _MatchDialogState extends State<_MatchDialog> {
  late DateTime _date = widget.initial?.date ?? DateTime.now().toUtc().subtract(const Duration(days: 7));
  late bool _teamHome = widget.initial == null ? true : widget.initial!.homeTeam.toLowerCase() == widget.team.toLowerCase();
  late final _opp = TextEditingController(
      text: widget.initial == null ? '' : (_teamHome ? widget.initial!.awayTeam : widget.initial!.homeTeam));
  late final _comp = TextEditingController(text: widget.initial?.competition ?? '');
  late final _ft = TextEditingController(text: _pair(widget.initial?.ftHome, widget.initial?.ftAway));
  late final _ht = TextEditingController(text: _pair(widget.initial?.htHome, widget.initial?.htAway));
  late final _seq = TextEditingController(text: HistoricalMatch.formatSequence(widget.initial?.goalSequence));
  late final _corners = TextEditingController(text: _pair(widget.initial?.cornersHome, widget.initial?.cornersAway));
  late final _reds = TextEditingController(text: _pair(widget.initial?.redCardsHome, widget.initial?.redCardsAway));
  late final _source = TextEditingController(text: widget.initial?.source ?? '');
  late bool _comparable = widget.initial?.comparable ?? true;
  late String? _result = widget.initial?.marketResultOverride;
  String? _error;

  static String _pair(int? a, int? b) => a == null || b == null ? '' : '$a-$b';
  static (int?, int?) _parse(String s) {
    final m = RegExp(r'^\s*(\d+)\s*[-:]\s*(\d+)\s*$').firstMatch(s);
    if (s.trim().isEmpty) return (null, null);
    if (m == null) throw FormatException('"$s" must look like 2-1');
    return (int.parse(m.group(1)!), int.parse(m.group(2)!));
  }

  void _submit() {
    try {
      if (_opp.text.trim().isEmpty) throw const FormatException('Opponent is required.');
      final ft = _parse(_ft.text), ht = _parse(_ht.text), co = _parse(_corners.text), rd = _parse(_reds.text);
      final seq = HistoricalMatch.parseSequence(_seq.text);
      final m = HistoricalMatch(
        date: _date,
        homeTeam: _teamHome ? widget.team : _opp.text.trim(),
        awayTeam: _teamHome ? _opp.text.trim() : widget.team,
        competition: _comp.text.trim(),
        ftHome: ft.$1,
        ftAway: ft.$2,
        htHome: ht.$1,
        htAway: ht.$2,
        goalSequence: seq,
        cornersHome: co.$1,
        cornersAway: co.$2,
        redCardsHome: rd.$1,
        redCardsAway: rd.$2,
        comparable: _comparable,
        source: _source.text.trim(),
        origin: DataOrigin.userEntered,
        marketResultOverride: _result,
      );
      // A record keeps its provider provenance only if nothing was changed.
      final init = widget.initial;
      if (init != null) {
        Map<String, dynamic> cmp(HistoricalMatch x) => x.toMap()..remove('id')..remove('origin');
        final a = cmp(init), b = cmp(m);
        if (a.keys.every((k) => '${a[k]}' == '${b[k]}')) {
          Navigator.pop(context, init);
          return;
        }
      }
      if (seq != null && !m.hasValidSequence) {
        throw const FormatException('Goal sequence does not match the full-time score.');
      }
      Navigator.pop(context, m);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('${widget.team} match'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(EatTime.formatDate(_date)),
              leading: const Icon(Icons.event),
              onTap: () async {
                final eat = EatTime.toEat(_date);
                final d = await showDatePicker(
                    context: context, initialDate: DateTime(eat.year, eat.month, eat.day), firstDate: DateTime(2015), lastDate: DateTime(2035));
                if (d != null) setState(() => _date = EatTime.fromEatWallClock(d.year, d.month, d.day, 12));
              },
            ),
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: true, label: Text('Played HOME')), ButtonSegment(value: false, label: Text('Played AWAY'))],
              selected: {_teamHome},
              onSelectionChanged: (s) => setState(() => _teamHome = s.first),
            ),
            _f(_opp, 'Opponent *'),
            _f(_comp, 'Competition'),
            _f(_ft, 'Full-time score (home-away)'),
            _f(_ht, 'Half-time score'),
            _f(_seq, 'Goal order, e.g. 12H,40A,77H'),
            _f(_corners, 'Corners (home-away)'),
            _f(_reds, 'Red cards (home-away)'),
            _f(_source, 'Source (where you verified this)'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _comparable,
              title: const Text('Comparable opponent / context'),
              onChanged: (v) => setState(() => _comparable = v),
            ),
            if (widget.custom)
              DropdownButtonFormField<String?>(
                initialValue: _result,
                decoration: const InputDecoration(labelText: 'Custom market result in this match'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('UNKNOWN')),
                  DropdownMenuItem(value: 'win', child: Text('WIN')),
                  DropdownMenuItem(value: 'lose', child: Text('LOSE')),
                  DropdownMenuItem(value: 'void', child: Text('VOID')),
                ],
                onChanged: (v) => setState(() => _result = v),
              ),
            if (_error != null) ErrorBanner(_error!),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _submit, child: const Text('OK')),
        ],
      );

  Widget _f(TextEditingController c, String l) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: TextField(controller: c, decoration: InputDecoration(labelText: l)),
      );
}
