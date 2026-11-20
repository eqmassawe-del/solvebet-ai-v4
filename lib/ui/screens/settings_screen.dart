import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../capital/capital.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/secure_store.dart';
import '../../engine/engine_config.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  AppSettings? _s;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('SETTINGS'),
        actions: [
          TextButton(
            onPressed: _s == null
                ? null
                : () async {
                    await ref.read(settingsProvider.notifier).save(_s!);
                    if (context.mounted) toast(context, 'Settings saved. Re-audit selections to apply new thresholds.');
                  },
            child: const Text('SAVE'),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorBanner('$e'),
        data: (loaded) {
          final s = _s ??= loaded;
          final e = s.engine;
          final c = s.capital;
          return ListView(padding: const EdgeInsets.all(12), children: [
            SectionCard(
              title: 'Football data provider',
              icon: Icons.cloud_outlined,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text(
                  'API-Football (api-sports.io). REQUIRES an API key; the free tier is limited to ~100 requests/day '
                  'and odds/some leagues need a paid plan. Without a key the app runs in manual mode.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 6),
                _SecretField(
                  label: 'API-Football key',
                  configured: loaded.hasFootballKey,
                  onSave: (v) => ref.read(settingsProvider.notifier).setSecret(SecretKeys.footballApiKey, v),
                ),
              ]),
            ),
            SectionCard(
              title: 'AI analysis (optional)',
              icon: Icons.psychology_alt_outlined,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text(
                  'Claude (Anthropic) explains finished audits. Requires an Anthropic API key (usage billed by Anthropic). '
                  'AI output is labelled MODEL-GENERATED, is never stored as evidence, and never changes a verdict.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 6),
                _SecretField(
                  label: 'Anthropic API key',
                  configured: loaded.hasAiKey,
                  onSave: (v) => ref.read(settingsProvider.notifier).setSecret(SecretKeys.aiApiKey, v),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  initialValue: s.aiModel,
                  decoration: const InputDecoration(labelText: 'Model ID'),
                  onChanged: (v) => _s = s.copyWith(aiModel: v.trim().isEmpty ? 'claude-opus-5-5' : v.trim()),
                ),
              ]),
            ),
            SectionCard(
              title: 'Preferences',
              icon: Icons.tune,
              child: Column(children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Include English leagues in recommendations'),
                  subtitle: const Text('Excluded by default.'),
                  value: s.includeEnglishLeagues,
                  onChanged: (v) => setState(() => _s = s.copyWith(includeEnglishLeagues: v)),
                ),
                DropdownButtonFormField<String>(
                  initialValue: s.language,
                  decoration: const InputDecoration(labelText: 'Language / Lugha'),
                  items: [for (final l in S.supported.entries) DropdownMenuItem(value: l.key, child: Text(l.value))],
                  onChanged: (v) => setState(() => _s = s.copyWith(language: v)),
                ),
              ]),
            ),
            SectionCard(
              title: 'KING\'S VISA evidence thresholds',
              icon: Icons.rule,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Thresholds tune how much evidence each gate needs. They cannot alter the decision matrix: '
                    'any FAIL rejects, any UNKNOWN is incomplete, WATCH never enters accumulators. Values are clamped to safe ranges.',
                    style: TextStyle(fontSize: 11, color: AppColors.muted)),
                _num('Recent window (matches)', e.recentWindow.toDouble(), 3, 10, 1,
                    (v) => _s = s.copyWith(engine: e.copyWith(recentWindow: v.round()))),
                _num('Broad window (matches)', e.broadWindow.toDouble(), 5, 20, 1,
                    (v) => _s = s.copyWith(engine: e.copyWith(broadWindow: v.round()))),
                _num('Min valid recent obs per team', e.minRecentValidPerTeam.toDouble(), 2, 10, 1,
                    (v) => _s = s.copyWith(engine: e.copyWith(minRecentValidPerTeam: v.round()))),
                _num('Min valid obs (combined broad)', e.minTotalValid.toDouble(), 4, 40, 1,
                    (v) => _s = s.copyWith(engine: e.copyWith(minTotalValid: v.round()))),
                _num('FAIL at failure rate ≥ (%)', e.failRateFail * 100, 10, 60, 5,
                    (v) => _s = s.copyWith(engine: e.copyWith(failRateFail: v / 100))),
                _num('WATCH above failure rate (%)', e.failRateWatch * 100, 0, 60, 5,
                    (v) => _s = s.copyWith(engine: e.copyWith(failRateWatch: v / 100))),
                _num('Max odds age (hours)', e.oddsMaxAgeHours.toDouble(), 1, 72, 1,
                    (v) => _s = s.copyWith(engine: e.copyWith(oddsMaxAgeHours: v.round()))),
                _num('Max history age (days)', e.historyMaxAgeDays.toDouble(), 7, 180, 1,
                    (v) => _s = s.copyWith(engine: e.copyWith(historyMaxAgeDays: v.round()))),
                _num('Min stress scenarios assessed', e.minScenariosAssessed.toDouble(), 2, 10, 1,
                    (v) => _s = s.copyWith(engine: e.copyWith(minScenariosAssessed: v.round()))),
                const SizedBox(height: 8),
                const Text('EVIDENCE SCORE WEIGHTS', style: TextStyle(color: AppColors.gold, fontSize: 11, fontWeight: FontWeight.w700)),
                for (final k in EngineConfig.defaultWeights.keys)
                  _num(EngineConfig.weightLabels[k]!, e.weights[k] ?? 0, 0, 50, 1,
                      (v) => _s = s.copyWith(engine: e.copyWith(weights: {...e.weights, k: v}))),
                TextButton(
                    onPressed: () => setState(() => _s = s.copyWith(engine: const EngineConfig())),
                    child: const Text('Reset engine defaults')),
              ]),
            ),
            SectionCard(
              title: 'Capital Control limits',
              icon: Icons.account_balance_outlined,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Paper trading / simulation mode'),
                  value: c.paperMode,
                  onChanged: (v) => setState(() => _s = s.copyWith(capital: c.copyWith(paperMode: v))),
                ),
                _text('Starting bankroll (TZS)', c.initialBankroll, (v) => _s = s.copyWith(capital: c.copyWith(initialBankroll: v))),
                _text('Daily income target (TZS, planning only)', c.dailyTarget, (v) => _s = s.copyWith(capital: c.copyWith(dailyTarget: v))),
                SegmentedButton<StakeMethod>(
                  segments: const [
                    ButtonSegment(value: StakeMethod.fixedPercent, label: Text('% of bankroll')),
                    ButtonSegment(value: StakeMethod.fixedAmount, label: Text('Fixed amount')),
                  ],
                  selected: {c.stakeMethod},
                  onSelectionChanged: (v) => setState(() => _s = s.copyWith(capital: c.copyWith(stakeMethod: v.first))),
                ),
                if (c.stakeMethod == StakeMethod.fixedPercent)
                  _num('Stake % of bankroll', c.stakePercent, 0.25, 10, 0.25,
                      (v) => _s = s.copyWith(capital: c.copyWith(stakePercent: v)))
                else
                  _text('Fixed stake (TZS)', c.fixedStake, (v) => _s = s.copyWith(capital: c.copyWith(fixedStake: v))),
                _num('Max stake per bet (%)', c.maxStakePercent, 0.25, 10, 0.25,
                    (v) => _s = s.copyWith(capital: c.copyWith(maxStakePercent: v))),
                _num('Max daily exposure (%)', c.maxDailyExposurePercent, 1, 30, 1,
                    (v) => _s = s.copyWith(capital: c.copyWith(maxDailyExposurePercent: v))),
                _num('Daily loss limit (% of start)', c.dailyLossLimitPercent, 1, 20, 1,
                    (v) => _s = s.copyWith(capital: c.copyWith(dailyLossLimitPercent: v))),
                _num('Max drawdown before pause (%)', c.maxDrawdownPercent, 5, 50, 1,
                    (v) => _s = s.copyWith(capital: c.copyWith(maxDrawdownPercent: v))),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Credentials are kept in Android secure storage (Keystore), never in the database.',
                  style: TextStyle(fontSize: 11, color: AppColors.muted)),
            ),
          ]);
        },
      ),
    );
  }

  Widget _num(String label, double v, double min, double max, double step, ValueChanged<double> set) => Row(children: [
        Expanded(flex: 5, child: Text(label, style: const TextStyle(fontSize: 12))),
        Expanded(
          flex: 5,
          child: Slider(
            value: v.clamp(min, max),
            min: min,
            max: max,
            divisions: ((max - min) / step).round(),
            onChanged: (x) => setState(() => set(x)),
          ),
        ),
        SizedBox(width: 44, child: Text(step < 1 ? v.toStringAsFixed(2) : v.toStringAsFixed(0), textAlign: TextAlign.end)),
      ]);

  Widget _text(String label, double v, ValueChanged<double> set) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: TextFormField(
          initialValue: v.toStringAsFixed(0),
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label),
          onChanged: (x) {
            final d = double.tryParse(x);
            if (d != null && d >= 0) set(d);
          },
        ),
      );
}

class _SecretField extends StatefulWidget {
  const _SecretField({required this.label, required this.configured, required this.onSave});
  final String label;
  final bool configured;
  final Future<void> Function(String?) onSave;
  @override
  State<_SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<_SecretField> {
  final _c = TextEditingController();

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: TextField(
            controller: _c,
            obscureText: true,
            decoration: InputDecoration(
              labelText: widget.label,
              helperText: widget.configured ? 'Configured (stored securely)' : 'Not configured',
            ),
          ),
        ),
        IconButton(
          tooltip: 'Save key',
          icon: const Icon(Icons.save_outlined, color: AppColors.gold),
          onPressed: () async {
            await widget.onSave(_c.text);
            _c.clear();
            if (context.mounted) toast(context, 'Key saved securely.');
          },
        ),
        if (widget.configured)
          IconButton(
            tooltip: 'Remove key',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await widget.onSave(null);
              if (context.mounted) toast(context, 'Key removed.');
            },
          ),
      ]);
}
