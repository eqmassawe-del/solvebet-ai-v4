import 'dart:convert';

import 'package:csv/csv.dart';

import '../../core/time.dart';
import '../../domain/enums.dart';
import '../../domain/market.dart';
import '../../domain/match_data.dart';
import '../../domain/selection.dart';

class ImportResult {
  const ImportResult(this.selections, this.errors);
  final List<Selection> selections;
  final List<String> errors;
}

/// CSV / JSON import. Imported rows are USER-ENTERED data (the user is the
/// source) unless the file explicitly marks them as synthetic.
///
/// Date/time strings without an offset are interpreted as Africa/Dar_es_Salaam
/// (EAT, UTC+3) wall-clock time.
class Importer {
  static DateTime? parseEatDateTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final s = raw.trim();
    final hasZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(s);
    final d = DateTime.tryParse(hasZone ? s : s.replaceFirst(' ', 'T'));
    if (d == null) return null;
    if (hasZone) return d.toUtc();
    return EatTime.fromEatWallClock(d.year, d.month, d.day, d.hour, d.minute);
  }

  static (int?, int?) _pair(Object? v) {
    if (v == null) return (null, null);
    final m = RegExp(r'^\s*(\d+)\s*[-:]\s*(\d+)\s*$').firstMatch('$v');
    if (m == null) return (null, null);
    return (int.parse(m.group(1)!), int.parse(m.group(2)!));
  }

  static double? _dbl(Object? v) => v == null || '$v'.trim().isEmpty ? null : double.tryParse('$v'.trim());

  static DataOrigin _origin(Object? v) => '$v'.toLowerCase() == 'synthetic' ? DataOrigin.synthetic : DataOrigin.userEntered;

  static HistoricalMatch historyFromJson(Map<String, dynamic> j) {
    final date = parseEatDateTime(j['date'] as String?);
    if (date == null) throw const FormatException('History record needs a valid "date".');
    final home = (j['home'] as String?)?.trim() ?? '';
    final away = (j['away'] as String?)?.trim() ?? '';
    if (home.isEmpty || away.isEmpty) throw const FormatException('History record needs "home" and "away".');
    final ft = _pair(j['ft']);
    final ht = _pair(j['ht']);
    final corners = _pair(j['corners']);
    final reds = _pair(j['reds']);
    final seqRaw = j['goals'];
    return HistoricalMatch(
      date: date,
      homeTeam: home,
      awayTeam: away,
      competition: (j['competition'] as String?) ?? '',
      ftHome: ft.$1,
      ftAway: ft.$2,
      htHome: ht.$1,
      htAway: ht.$2,
      goalSequence: seqRaw == null ? null : HistoricalMatch.parseSequence('$seqRaw'),
      cornersHome: corners.$1,
      cornersAway: corners.$2,
      redCardsHome: reds.$1,
      redCardsAway: reds.$2,
      comparable: j['comparable'] != false,
      source: (j['source'] as String?) ?? 'Imported file',
      origin: _origin(j['origin']),
      marketResultOverride: j['market_result'] as String?,
    );
  }

  static MarketSpec marketFromJson(Map<String, dynamic> j) => MarketSpec(
        type: MarketType.parse(j['type'] as String?),
        pick: (j['pick'] as String?) ?? '',
        side: j['side'] == null ? null : Side.parse(j['side'] as String?),
        line: _dbl(j['line']),
        customName: (j['name'] as String?) ?? '',
        customWinCondition: (j['win_condition'] as String?) ?? '',
        customFailCondition: (j['fail_condition'] as String?) ?? '',
      );

  /// JSON: either a list of selections or {"selections": [...]}. See README.
  static ImportResult fromJson(String text) {
    final errors = <String>[];
    final out = <Selection>[];
    dynamic data;
    try {
      data = jsonDecode(text);
    } catch (e) {
      return ImportResult(const [], ['Invalid JSON: $e']);
    }
    final list = data is Map ? data['selections'] : data;
    if (list is! List) return const ImportResult([], ['Expected a list of selections.']);
    for (var i = 0; i < list.length; i++) {
      try {
        final j = Map<String, dynamic>.from(list[i] as Map);
        List<HistoricalMatch> hist(String k) => ((j[k] as List?) ?? [])
            .map((e) => historyFromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        final odds = _dbl(j['odds']);
        out.add(Selection(
          matchRef: (j['match_ref'] as String?) ?? '',
          homeTeam: (j['home'] as String?)?.trim() ?? '',
          awayTeam: (j['away'] as String?)?.trim() ?? '',
          league: (j['league'] as String?) ?? '',
          country: (j['country'] as String?) ?? '',
          kickoff: parseEatDateTime(j['kickoff'] as String?),
          market: marketFromJson(Map<String, dynamic>.from((j['market'] as Map?) ?? {})),
          odds: odds,
          oddsSource: (j['odds_source'] as String?) ?? 'Imported file',
          oddsUpdatedAt: parseEatDateTime(j['odds_updated_at'] as String?),
          origin: _origin(j['origin']),
          homeHistory: hist('home_history'),
          awayHistory: hist('away_history'),
          notes: (j['notes'] as String?) ?? '',
          dataUpdatedAt: DateTime.now().toUtc(),
        ));
      } catch (e) {
        errors.add('Selection #${i + 1}: $e');
      }
    }
    return ImportResult(out, errors);
  }

  static List<Map<String, String>> _csvRows(String text) {
    final rows = Csv().decode(text.trim());
    if (rows.isEmpty) return [];
    final header = rows.first.map((e) => '$e'.trim().toLowerCase()).toList();
    return [
      for (final r in rows.skip(1))
        if (r.any((c) => '$c'.trim().isNotEmpty))
          {for (var i = 0; i < header.length; i++) header[i]: i < r.length ? '${r[i]}'.trim() : ''},
    ];
  }

  /// Selections CSV columns:
  /// home,away,league,country,kickoff,market_type,pick,side,line,odds,odds_source,odds_updated_at
  static ImportResult selectionsFromCsv(String text) {
    final errors = <String>[];
    final out = <Selection>[];
    final rows = _csvRows(text);
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      if ((r['home'] ?? '').isEmpty || (r['away'] ?? '').isEmpty) {
        errors.add('Row ${i + 2}: home and away are required.');
        continue;
      }
      out.add(Selection(
        homeTeam: r['home']!,
        awayTeam: r['away']!,
        league: r['league'] ?? '',
        country: r['country'] ?? '',
        kickoff: parseEatDateTime(r['kickoff']),
        market: MarketSpec(
          type: MarketType.parse(r['market_type']),
          pick: r['pick'] ?? '',
          side: (r['side'] ?? '').isEmpty ? null : Side.parse(r['side']),
          line: _dbl(r['line']),
        ),
        odds: _dbl(r['odds']),
        oddsSource: (r['odds_source'] ?? '').isEmpty ? 'Imported CSV' : r['odds_source']!,
        oddsUpdatedAt: parseEatDateTime(r['odds_updated_at']),
        origin: _origin(r['origin']),
      ));
    }
    return ImportResult(out, errors);
  }

  /// History CSV columns:
  /// team_role(home|away),date,home,away,competition,ft,ht,goals,corners,reds,comparable,source
  static ({List<HistoricalMatch> home, List<HistoricalMatch> away, List<String> errors}) historyFromCsv(String text) {
    final home = <HistoricalMatch>[], away = <HistoricalMatch>[], errors = <String>[];
    final rows = _csvRows(text);
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      try {
        final m = historyFromJson({
          'date': r['date'],
          'home': r['home'],
          'away': r['away'],
          'competition': r['competition'],
          'ft': (r['ft'] ?? '').isEmpty ? null : r['ft'],
          'ht': (r['ht'] ?? '').isEmpty ? null : r['ht'],
          'goals': (r['goals'] ?? '').isEmpty ? null : r['goals'],
          'corners': (r['corners'] ?? '').isEmpty ? null : r['corners'],
          'reds': (r['reds'] ?? '').isEmpty ? null : r['reds'],
          'comparable': (r['comparable'] ?? '').toLowerCase() != 'false' && r['comparable'] != '0',
          'source': (r['source'] ?? '').isEmpty ? 'Imported CSV' : r['source'],
          'origin': r['origin'],
        });
        (r['team_role'] == 'away' ? away : home).add(m);
      } catch (e) {
        errors.add('Row ${i + 2}: $e');
      }
    }
    return (home: home, away: away, errors: errors);
  }
}
