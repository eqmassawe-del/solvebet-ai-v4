import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme.dart';
import '../../core/time.dart';
import '../../domain/enums.dart';
import '../../engine/markets/markets.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import 'visa_report_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key, required this.onNavigate});
  final void Function(int) onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sels = ref.watch(selectionsProvider);
    final m = ref.watch(metricsProvider);
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final s = ref.watch(stringsProvider);
    final cur = settings.capital.currency;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(selectionsProvider);
        ref.invalidate(betsProvider);
      },
      child: ListView(padding: const EdgeInsets.all(12), children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.graphite2, AppColors.black]),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.verified_user_outlined, color: AppColors.gold),
              const SizedBox(width: 8),
              Text("KING'S VISA ENGINE", style: TextStyle(color: AppColors.gold.withValues(alpha: 0.95), fontWeight: FontWeight.w800, letterSpacing: 1.5)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: (settings.capital.paperMode ? AppColors.pass : AppColors.watch).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(settings.capital.paperMode ? 'PAPER TRADING' : 'REAL-MONEY LEDGER',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: settings.capital.paperMode ? AppColors.pass : AppColors.watch)),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              settings.hasFootballKey ? 'Live data provider configured (API-Football).' : '${s.t('manual_mode')} — no data provider key configured.',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            Text('Timezone: ${EatTime.zoneName} (EAT, UTC+3) · ${EatTime.format(DateTime.now().toUtc())}',
                style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          ]),
        ),
        const SizedBox(height: 8),
        sels.when(
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => ErrorBanner('Could not load selections: $e'),
          data: (list) {
            int count(FinalVerdict v) => list.where((x) => x.verdict == v).length;
            final pendingExposure = m?.pendingExposure ?? 0;
            final approved = list.where((x) => x.verdict == FinalVerdict.approved).toList()
              ..sort((a, b) => (b.score ?? 0).compareTo(a.score ?? 0));
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SectionCard(
                title: 'Audit overview',
                icon: Icons.analytics_outlined,
                child: StatGrid([
                  StatTile('Matches analysed', '${list.map((x) => x.selection.matchLabel).toSet().length}', sub: '${list.length} selections'),
                  StatTile('Not yet audited', '${list.where((x) => x.audit == null).length}'),
                  StatTile(s.t('approved'), '${count(FinalVerdict.approved)}', color: AppColors.pass),
                  StatTile(s.t('watch'), '${count(FinalVerdict.watch)}', color: AppColors.watch),
                  StatTile(s.t('rejected'), '${count(FinalVerdict.rejected)}', color: AppColors.fail),
                  StatTile(s.t('incomplete'), '${count(FinalVerdict.incomplete)}', color: AppColors.unknown),
                ]),
              ),
              if (m != null)
                SectionCard(
                  title: 'Capital & exposure',
                  icon: Icons.account_balance_outlined,
                  trailing: TextButton(onPressed: () => onNavigate(4), child: const Text('Open')),
                  child: StatGrid([
                    StatTile('Bankroll', money(m.current, cur),
                        color: m.current >= m.initial ? AppColors.pass : AppColors.fail),
                    StatTile('Realised P/L', money(m.realizedPnl, cur),
                        color: m.realizedPnl >= 0 ? AppColors.pass : AppColors.fail),
                    StatTile('Open exposure', money(pendingExposure, cur), sub: '${m.pendingCount} pending bet(s)'),
                    StatTile('Drawdown', pct(m.currentDrawdown), sub: 'max ${pct(m.maxDrawdown)}'),
                    StatTile('Yield', pct(m.yieldPct == null ? null : m.yieldPct! / 100)),
                    StatTile('Daily target (plan)', money(settings.capital.dailyTarget, cur), sub: 'planning figure, not expected'),
                  ]),
                ),
              SectionCard(
                title: 'Top approved (ranked by evidence score)',
                icon: Icons.emoji_events_outlined,
                trailing: TextButton(onPressed: () => onNavigate(2), child: const Text('All')),
                child: approved.isEmpty
                    ? const Text('No APPROVED selections. That is an acceptable outcome — the engine will not '
                        'approve without full evidence.', style: TextStyle(color: AppColors.muted))
                    : Column(children: [
                        for (final a in approved.take(5))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(a.selection.matchLabel),
                            subtitle: Text(
                                '${MarketRegistry.of(a.selection.market.type).describe(a.selection.market, a.selection.homeTeam, a.selection.awayTeam)} @ ${a.selection.odds?.toStringAsFixed(2) ?? '?'}'),
                            trailing: Text(a.score?.toStringAsFixed(0) ?? '-',
                                style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800, fontSize: 18)),
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => VisaReportScreen(selectionId: a.selection.id!))),
                          ),
                      ]),
              ),
            ]);
          },
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(s.t('disclaimer'), style: const TextStyle(color: AppColors.muted, fontSize: 11)),
        ),
      ]),
    );
  }
}
