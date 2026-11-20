import 'package:material_ui/material_ui.dart';

import '../../core/theme.dart';
import '../../domain/enums.dart';

class VerdictChip extends StatelessWidget {
  const VerdictChip(this.verdict, {super.key, this.dense = false});
  final FinalVerdict? verdict;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.verdict(verdict);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 10, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c),
      ),
      child: Text(
        verdict?.label ?? 'NOT AUDITED',
        style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: dense ? 10 : 12, letterSpacing: 0.8),
      ),
    );
  }
}

class OutcomeChip extends StatelessWidget {
  const OutcomeChip(this.stage, this.outcome, {super.key});
  final String stage;
  final VisaOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.outcome(outcome);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
      child: Text('$stage ${outcome.label}', style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class OriginBadge extends StatelessWidget {
  const OriginBadge(this.origin, {super.key});
  final DataOrigin origin;

  @override
  Widget build(BuildContext context) {
    final c = switch (origin) {
      DataOrigin.verifiedApi => AppColors.pass,
      DataOrigin.userEntered => AppColors.goldSoft,
      DataOrigin.modelGenerated => const Color(0xFFB48EF0),
      DataOrigin.engineDerived => AppColors.muted,
      DataOrigin.synthetic => AppColors.fail,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(border: Border.all(color: c, width: 0.7), borderRadius: BorderRadius.circular(4)),
      child: Text(origin.label, style: TextStyle(color: c, fontSize: 9, fontWeight: FontWeight.w600)),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.trailing, this.icon});
  final String title;
  final Widget child;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                if (icon != null) ...[Icon(icon, size: 18, color: AppColors.gold), const SizedBox(width: 8)],
                Expanded(
                  child: Text(title.toUpperCase(),
                      style: const TextStyle(
                          color: AppColors.gold, fontWeight: FontWeight.w700, letterSpacing: 1.1, fontSize: 12)),
                ),
                ?trailing,
              ]),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      );
}

class StatTile extends StatelessWidget {
  const StatTile(this.label, this.value, {super.key, this.color, this.sub});
  final String label;
  final String value;
  final String? sub;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.graphite2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.outline, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: TextStyle(color: color ?? AppColors.white, fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            if (sub != null) Text(sub!, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
          ],
        ),
      );
}

class StatGrid extends StatelessWidget {
  const StatGrid(this.tiles, {super.key, this.columns = 2});
  final List<Widget> tiles;
  final int columns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        const gap = 8.0;
        final w = (c.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final t in tiles) SizedBox(width: w, child: t)],
        );
      });
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 48, color: AppColors.gold.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(message, style: const TextStyle(color: AppColors.muted), textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key, this.color = AppColors.fail, this.icon = Icons.error_outline});
  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 12.5))),
        ]),
      );
}

class KV extends StatelessWidget {
  const KV(this.k, this.v, {super.key, this.valueColor});
  final String k;
  final String v;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 128,
              child: Text(k, style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600))),
          Expanded(child: Text(v, style: TextStyle(fontSize: 13, color: valueColor))),
        ]),
      );
}

/// Minimal line chart (no external chart dependency).
class LineChart extends StatelessWidget {
  const LineChart(this.series, {super.key, this.height = 150, this.baseline});
  final List<List<double>> series;
  final double height;
  final double? baseline;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _LinePainter(series, baseline)),
      );
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.series, this.baseline);
  final List<List<double>> series;
  final double? baseline;
  static const colors = [AppColors.gold, AppColors.pass, AppColors.watch, AppColors.goldSoft, AppColors.muted];

  @override
  void paint(Canvas canvas, Size size) {
    final all = [for (final s in series) ...s, ?baseline];
    if (all.length < 2) return;
    var lo = all.reduce((a, b) => a < b ? a : b), hi = all.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 1e-9) {
      hi += 1;
      lo -= 1;
    }
    double y(double v) => size.height - (v - lo) / (hi - lo) * (size.height - 8) - 4;
    final grid = Paint()
      ..color = AppColors.outline
      ..strokeWidth = 0.5;
    for (var i = 0; i <= 4; i++) {
      final gy = size.height * i / 4;
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), grid);
    }
    if (baseline != null) {
      canvas.drawLine(Offset(0, y(baseline!)), Offset(size.width, y(baseline!)),
          Paint()
            ..color = AppColors.muted
            ..strokeWidth = 1);
    }
    for (var si = 0; si < series.length; si++) {
      final s = series[si];
      if (s.length < 2) continue;
      final p = Path();
      for (var i = 0; i < s.length; i++) {
        final x = size.width * i / (s.length - 1);
        i == 0 ? p.moveTo(x, y(s[i])) : p.lineTo(x, y(s[i]));
      }
      canvas.drawPath(
          p,
          Paint()
            ..color = colors[si % colors.length]
            ..style = PaintingStyle.stroke
            ..strokeWidth = si == 0 ? 2 : 1.2);
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => old.series != series;
}

String money(num v, [String cur = 'TZS']) {
  final neg = v < 0;
  final s = v.abs().round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '${neg ? '-' : ''}$cur $s';
}

String pct(double? v, {int digits = 1}) => v == null ? 'n/a' : '${(v * 100).toStringAsFixed(digits)}%';

void toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
