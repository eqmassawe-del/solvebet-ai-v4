import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme.dart';
import '../../core/time.dart';
import '../../data/api/api_errors.dart';
import '../../data/api/football_provider.dart';
import '../../domain/enums.dart';
import '../../domain/selection.dart';
import '../../engine/markets/markets.dart';
import '../../state/providers.dart';
import '../import_actions.dart';
import '../widgets/common.dart';
import 'selection_editor_screen.dart';
import 'visa_report_screen.dart';

/// KING'S SCANNER — fixtures from a licensed provider, or manual mode.
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});
  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  int _dayOffset = 0;
  List<ProviderFixture>? _fixtures;
  String? _error;
  bool _loading = false;
  String _q = '';
  DateTime? _fetchedAt;

  Future<void> _load(FootballDataProvider p) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final eat = EatTime.toEat(DateTime.now().toUtc()).add(Duration(days: _dayOffset));
      final list = await p.fixturesOn(eat);
      setState(() {
        _fixtures = list;
        _fetchedAt = DateTime.now().toUtc();
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provAsync = ref.watch(footballDataProvider);
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    return provAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: ErrorBanner('$e')),
      data: (p) => p == null ? _manual(context) : _live(p, settings),
    );
  }

  Widget _manual(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return ListView(padding: const EdgeInsets.all(12), children: [
      SectionCard(
        title: s.t('manual_mode'),
        icon: Icons.edit_note,
        child: const Text(
          'No licensed data provider is configured, so no fixtures are shown. MathBetAI never displays invented '
          'matches. Enter selections manually, import CSV/JSON, or import a betting-slip screenshot (you confirm '
          'every extracted field). To enable live fixtures, add an API-Football key in Settings (paid tiers needed for odds '
          'on many leagues).',
          style: TextStyle(fontSize: 13),
        ),
      ),
      const SizedBox(height: 8),
      _action(Icons.add_task, s.t('new_selection'), 'Define match, market, odds and evidence by hand.',
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SelectionEditorScreen()))),
      _action(Icons.upload_file, s.t('import'), 'Bulk import selections with histories (format in README).',
          () => importSelectionsFile(context, ref)),
      _action(Icons.document_scanner_outlined, s.t('import_slip'), 'On-device OCR → drafts you must confirm.',
          () => importSlipScreenshot(context, ref)),
    ]);
  }

  Widget _action(IconData i, String t, String sub, VoidCallback onTap) => Card(
        child: ListTile(
          leading: Icon(i, color: AppColors.gold),
          title: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(sub),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );

  Widget _live(FootballDataProvider p, AppSettings settings) {
    final list = (_fixtures ?? [])
        .where((f) => _q.isEmpty || '${f.homeTeam} ${f.awayTeam} ${f.league} ${f.country}'.toLowerCase().contains(_q))
        .where((f) => settings.includeEnglishLeagues || f.country.toLowerCase() != 'england')
        .toList();
    final hiddenEnglish = (_fixtures ?? []).where((f) => f.country.toLowerCase() == 'england').length;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(children: [
          for (final d in [0, 1, 2])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(d == 0 ? 'Today' : (d == 1 ? 'Tomorrow' : '+2 days')),
                selected: _dayOffset == d,
                onSelected: (_) {
                  setState(() => _dayOffset = d);
                  _load(p);
                },
              ),
            ),
          const Spacer(),
          IconButton.filled(
            onPressed: _loading ? null : () => _load(p),
            icon: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.radar),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search fixtures'),
          onChanged: (v) => setState(() => _q = v.toLowerCase()),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          'Source: ${p.name} · last update ${_fetchedAt == null ? 'never' : EatTime.format(_fetchedAt)}'
          '${!settings.includeEnglishLeagues && hiddenEnglish > 0 ? ' · $hiddenEnglish English fixtures hidden' : ''}',
          style: const TextStyle(color: AppColors.muted, fontSize: 11),
        ),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: ErrorBanner(_error!)),
      Expanded(
        child: _fixtures == null
            ? EmptyState(
                icon: Icons.radar,
                title: 'Scan fixtures',
                message: 'Tap the radar to retrieve fixtures from ${p.name}. Each request counts against your API quota.',
              )
            : list.isEmpty
                ? const EmptyState(icon: Icons.event_busy, title: 'No fixtures', message: 'The provider returned no matching fixtures.')
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 40),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final f = list[i];
                      return Card(
                        child: ListTile(
                          title: Text('${f.homeTeam} vs ${f.awayTeam}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${f.league} · ${f.country}\n${EatTime.format(f.kickoff, pattern: 'EEE HH:mm')} · ${f.status}'),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => _FixtureSheet(fixture: f, provider: p),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }
}

class _FixtureSheet extends ConsumerStatefulWidget {
  const _FixtureSheet({required this.fixture, required this.provider});
  final ProviderFixture fixture;
  final FootballDataProvider provider;
  @override
  ConsumerState<_FixtureSheet> createState() => _FixtureSheetState();
}

class _FixtureSheetState extends ConsumerState<_FixtureSheet> {
  List<ProviderOdd>? _odds;
  String? _error;
  bool _busy = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _loadOdds();
  }

  Future<void> _loadOdds() async {
    setState(() => _busy = true);
    try {
      final o = await widget.provider.odds(widget.fixture);
      setState(() => _odds = o);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _audit(ProviderOdd o) async {
    final f = widget.fixture;
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Retrieving ${f.homeTeam} history…';
    });
    try {
      final home = await widget.provider.teamHistory(f.homeTeamId);
      setState(() => _status = 'Retrieving ${f.awayTeam} history…');
      final away = await widget.provider.teamHistory(f.awayTeamId);
      setState(() => _status = 'Retrieving injuries…');
      var injuriesText = '';
      try {
        final inj = await widget.provider.injuries(f.id);
        injuriesText = inj.isEmpty
            ? 'Provider lists no injuries/suspensions for this fixture (absence of a report is not proof of fitness).'
            : inj.map((x) => '${x.team}: ${x.player} (${x.reason})').join('; ');
      } on ApiException catch (_) {
        injuriesText = '';
      }
      final checks = StructuralCheck.defaults()
          .map((c) => c.factor == StructuralFactor.injuriesSuspensions && injuriesText.isNotEmpty
              ? c.copyWith(evidence: '[${widget.provider.name}] $injuriesText', origin: DataOrigin.verifiedApi)
              : c)
          .toList();
      final sel = Selection(
        matchRef: '${widget.provider.name}:${f.id}',
        homeTeam: f.homeTeam,
        awayTeam: f.awayTeam,
        league: f.league,
        country: f.country,
        kickoff: f.kickoff,
        market: o.spec,
        odds: o.odds,
        oddsSource: o.bookmaker,
        oddsUpdatedAt: o.updatedAt ?? f.fetchedAt,
        origin: DataOrigin.verifiedApi,
        homeHistory: home,
        awayHistory: away,
        checks: checks,
        scenarios: MarketRegistry.of(o.spec.type)
            .stressTemplates(o.spec, f.homeTeam, f.awayTeam)
            .map((t) => t.toScenario())
            .toList(),
      );
      setState(() => _status = 'Auditing…');
      final ctl = ref.read(selectionsProvider.notifier);
      final id = await ctl.save(sel);
      await ctl.audit(id);
      if (!mounted) return;
      Navigator.pop(context);
      Navigator.push(context, MaterialPageRoute(builder: (_) => VisaReportScreen(selectionId: id)));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.fixture;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      builder: (_, controller) => ListView(controller: controller, padding: const EdgeInsets.all(16), children: [
        Text('${f.homeTeam} vs ${f.awayTeam}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        Text('${f.league} · ${EatTime.format(f.kickoff)}', style: const TextStyle(color: AppColors.muted)),
        Text('Fixture ${f.id} · fetched ${EatTime.ago(f.fetchedAt)} from ${f.provider}',
            style: const TextStyle(color: AppColors.muted, fontSize: 11)),
        const SizedBox(height: 8),
        const ErrorBanner(
          'Selecting a market fetches both teams\' last 10 matches (≈4 API requests) and runs VISA A–B automatically. '
          'VISA C and D need your structural and stress assessment — until then the verdict is INCOMPLETE.',
          color: AppColors.muted,
          icon: Icons.info_outline,
        ),
        if (_busy) ...[const LinearProgressIndicator(), Text(_status, style: const TextStyle(fontSize: 12))],
        if (_error != null) ErrorBanner(_error!),
        if (_odds != null && _odds!.isEmpty)
          const ErrorBanner('No supported priced markets returned for this fixture (odds may require a paid plan).',
              color: AppColors.watch),
        for (final o in _odds ?? <ProviderOdd>[])
          ListTile(
            dense: true,
            title: Text(MarketRegistry.of(o.spec.type).describe(o.spec, f.homeTeam, f.awayTeam)),
            subtitle: Text('${o.bookmaker} · ${o.rawLabel} · updated ${EatTime.ago(o.updatedAt)}'),
            trailing: Text(o.odds.toStringAsFixed(2), style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800)),
            onTap: _busy ? null : () => _audit(o),
          ),
      ]),
    );
  }
}
