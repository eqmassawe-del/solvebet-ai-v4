import 'package:intl/intl.dart';

/// Africa/Dar_es_Salaam is UTC+3 all year (no daylight saving), so a fixed
/// offset is exact for this zone.
class EatTime {
  static const zoneName = 'Africa/Dar_es_Salaam';
  static const offset = Duration(hours: 3);

  /// Converts a UTC instant to a "wall clock" DateTime in EAT (returned as a
  /// UTC-flagged value whose fields read as EAT time).
  static DateTime toEat(DateTime utc) => utc.toUtc().add(offset);

  /// Interprets wall-clock fields (y/m/d h:m) as EAT and returns the UTC instant.
  static DateTime fromEatWallClock(int y, int m, int d, [int h = 0, int min = 0]) =>
      DateTime.utc(y, m, d, h, min).subtract(offset);

  static String dateKey(DateTime utc) => DateFormat('yyyy-MM-dd').format(toEat(utc));

  static String format(DateTime? utc, {String pattern = 'EEE d MMM yyyy, HH:mm'}) =>
      utc == null ? '—' : '${DateFormat(pattern).format(toEat(utc))} EAT';

  static String formatDate(DateTime? utc) =>
      utc == null ? '—' : DateFormat('d MMM yyyy').format(toEat(utc));

  static String ago(DateTime? utc, {DateTime? now}) {
    if (utc == null) return 'never';
    final d = (now ?? DateTime.now().toUtc()).difference(utc);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 48) return '${d.inHours} h ago';
    return '${d.inDays} days ago';
  }
}
