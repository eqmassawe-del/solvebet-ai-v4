import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../core/time.dart';
import '../../domain/enums.dart';
import '../../domain/market.dart';
import '../../domain/match_data.dart';
import 'api_errors.dart';
import 'football_provider.dart';

/// API-Football v3 (api-sports.io) implementation.
///
/// REQUIRES an API-Football key (free tier: ~100 requests/day; odds and
/// some leagues need a paid plan). Nothing here fabricates data: any field
/// the provider omits stays null and becomes UNKNOWN downstream.
class ApiFootballProvider implements FootballDataProvider {
  ApiFootballProvider({
    required this.apiKey,
    http.Client? client,
    this.baseUrl = 'https://v3.football.api-sports.io',
    this.timeout = const Duration(seconds: 20),
    DateTime Function()? clock,
  })  : _client = client ?? http.Client(),
        _clock = clock ?? (() => DateTime.now().toUtc());

  final String apiKey;
  final String baseUrl;
  final Duration timeout;
  final http.Client _client;
  final DateTime Function() _clock;

  @override
  String get name => 'API-Football';

  Future<List<dynamic>> _get(String path, Map<String, String> q) async {
    if (apiKey.trim().isEmpty) throw const ApiNotConfigured();
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: q);
    http.Response res;
    try {
      res = await _client.get(uri, headers: {'x-apisports-key': apiKey}).timeout(timeout);
    } on TimeoutException {
      throw const ApiNetworkException('Data provider timed out.');
    } on SocketException catch (e) {
      throw ApiNetworkException('Network unavailable: ${e.message}');
    } on http.ClientException catch (e) {
      throw ApiNetworkException('Network error: ${e.message}');
    }
    if (res.statusCode == 401 || res.statusCode == 403) throw const ApiAuthException();
    if (res.statusCode == 429) {
      final ra = int.tryParse(res.headers['retry-after'] ?? '');
      throw ApiRateLimitException(ra == null ? null : Duration(seconds: ra));
    }
    if (res.statusCode >= 400) {
      throw ApiHttpException(res.statusCode, 'Data provider returned HTTP ${res.statusCode}.');
    }
    Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw const ApiDataException('Malformed response from data provider.');
    }
    final errors = body['errors'];
    final hasErrors = (errors is Map && errors.isNotEmpty) || (errors is List && errors.isNotEmpty);
    if (hasErrors) {
      final text = errors.toString().toLowerCase();
      if (text.contains('request') && (text.contains('limit') || text.contains('reached'))) {
        throw const ApiRateLimitException();
      }
      if (text.contains('token') || text.contains('key') || text.contains('subscription')) {
        throw ApiAuthException('Provider rejected the request: $errors');
      }
      throw ApiDataException('Provider error: $errors');
    }
    final r = body['response'];
    if (r is! List) throw const ApiDataException('Provider response missing "response" list.');
    return r;
  }

  @override
  Future<List<ProviderFixture>> fixturesOn(DateTime eatDate) async {
    final date = DateFormat('yyyy-MM-dd').format(eatDate);
    final list = await _get('/fixtures', {'date': date, 'timezone': EatTime.zoneName});
    final fetched = _clock();
    final out = <ProviderFixture>[];
    for (final raw in list) {
      try {
        final m = raw as Map<String, dynamic>;
        final fx = m['fixture'] as Map<String, dynamic>;
        final teams = m['teams'] as Map<String, dynamic>;
        final league = m['league'] as Map<String, dynamic>;
        final ts = fx['timestamp'] as int?;
        final home = teams['home'] as Map<String, dynamic>, away = teams['away'] as Map<String, dynamic>;
        if (ts == null || home['name'] == null || away['name'] == null) continue; // incomplete record
        out.add(ProviderFixture(
          id: '${fx['id']}',
          kickoff: DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true),
          homeTeam: home['name'] as String,
          awayTeam: away['name'] as String,
          homeTeamId: home['id'] as int,
          awayTeamId: away['id'] as int,
          league: (league['name'] as String?) ?? '',
          country: (league['country'] as String?) ?? '',
          status: ((fx['status'] as Map?)?['short'] as String?) ?? '',
          fetchedAt: fetched,
          provider: name,
        ));
      } catch (_) {
        // Skip malformed records rather than guessing missing values.
      }
    }
    out.sort((a, b) => a.kickoff.compareTo(b.kickoff));
    return out;
  }

  @override
  Future<List<HistoricalMatch>> teamHistory(int teamId, {int last = 10}) async {
    final list = await _get('/fixtures', {'team': '$teamId', 'last': '$last'});
    final ids = <String>[];
    for (final raw in list) {
      final fx = (raw as Map)['fixture'] as Map?;
      final st = ((fx?['status'] as Map?)?['short'] as String?) ?? '';
      if (fx != null && {'FT', 'AET', 'PEN'}.contains(st)) ids.add('${fx['id']}');
    }
    if (ids.isEmpty) return [];
    // One call returns events + statistics for up to 20 fixtures.
    final detailed = await _get('/fixtures', {'ids': ids.take(20).join('-')});
    return detailed.map((e) => parseHistorical(e as Map<String, dynamic>, source: name)).whereType<HistoricalMatch>().toList();
  }

  /// Parses an API-Football fixture (with events/statistics) into a
  /// [HistoricalMatch]. Public for testing.
  static HistoricalMatch? parseHistorical(Map<String, dynamic> m, {String source = 'API-Football'}) {
    try {
      final fx = m['fixture'] as Map<String, dynamic>;
      final teams = m['teams'] as Map<String, dynamic>;
      final home = teams['home'] as Map<String, dynamic>, away = teams['away'] as Map<String, dynamic>;
      final homeId = home['id'];
      final status = ((fx['status'] as Map?)?['short'] as String?) ?? '';
      final score = (m['score'] as Map?) ?? {};
      final ft = (score['fulltime'] as Map?) ?? (m['goals'] as Map?) ?? {};
      final ht = (score['halftime'] as Map?) ?? {};
      final ftH = ft['home'] as int?, ftA = ft['away'] as int?;
      final events = m['events'] as List?;

      List<GoalEvent>? seq;
      int? redH, redA;
      if (events != null && events.isNotEmpty) {
        final goals = <(GoalEvent, bool)>[];
        var rh = 0, ra = 0;
        for (final e in events.cast<Map>()) {
          final type = e['type'] as String?;
          final detail = (e['detail'] as String?) ?? '';
          final elapsed = ((e['time'] as Map?)?['elapsed'] as int?) ?? 0;
          final isHome = ((e['team'] as Map?)?['id']) == homeId;
          if (type == 'Goal' && detail != 'Missed Penalty') {
            if (status != 'FT' && elapsed > 90) continue; // extra time is outside 90-min markets
            goals.add((GoalEvent(minute: elapsed, side: isHome ? Side.home : Side.away), detail == 'Own Goal'));
          }
          if (type == 'Card' && (detail == 'Red Card' || detail == 'Second Yellow card')) {
            if (isHome) {
              rh++;
            } else {
              ra++;
            }
          }
        }
        redH = rh;
        redA = ra;
        bool consistent(List<GoalEvent> s) =>
            ftH != null &&
            ftA != null &&
            s.where((g) => g.side == Side.home).length == ftH &&
            s.where((g) => g.side == Side.away).length == ftA;
        final asIs = goals.map((g) => g.$1).toList();
        final flipped = goals.map((g) => g.$2 ? GoalEvent(minute: g.$1.minute, side: g.$1.side.other) : g.$1).toList();
        if (consistent(asIs)) {
          seq = asIs;
        } else if (consistent(flipped)) {
          seq = flipped;
        } // otherwise: sequence stays UNKNOWN
      } else if (ftH == 0 && ftA == 0) {
        seq = const [];
      }

      int? cornersH, cornersA;
      final stats = m['statistics'] as List?;
      if (stats != null) {
        for (final t in stats.cast<Map>()) {
          final isHome = ((t['team'] as Map?)?['id']) == homeId;
          for (final s in ((t['statistics'] as List?) ?? []).cast<Map>()) {
            if (s['type'] == 'Corner Kicks') {
              final v = s['value'];
              final n = v is int ? v : (v == null ? 0 : int.tryParse('$v'));
              if (isHome) {
                cornersH = n;
              } else {
                cornersA = n;
              }
            }
          }
        }
      }

      final league = (m['league'] as Map?) ?? {};
      return HistoricalMatch(
        date: DateTime.fromMillisecondsSinceEpoch((fx['timestamp'] as int) * 1000, isUtc: true),
        homeTeam: home['name'] as String,
        awayTeam: away['name'] as String,
        competition: (league['name'] as String?) ?? '',
        ftHome: ftH,
        ftAway: ftA,
        htHome: ht['home'] as int?,
        htAway: ht['away'] as int?,
        goalSequence: seq,
        cornersHome: cornersH,
        cornersAway: cornersA,
        redCardsHome: redH,
        redCardsAway: redA,
        source: '$source fixture ${fx['id']}',
        origin: DataOrigin.verifiedApi,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<ProviderOdd>> odds(ProviderFixture f) async {
    final list = await _get('/odds', {'fixture': f.id});
    if (list.isEmpty) return [];
    final first = list.first as Map<String, dynamic>;
    final updated = DateTime.tryParse((first['update'] as String?) ?? '')?.toUtc();
    final books = (first['bookmakers'] as List?) ?? [];
    if (books.isEmpty) return [];
    final book = books.first as Map<String, dynamic>;
    final out = <ProviderOdd>[];
    for (final bet in ((book['bets'] as List?) ?? []).cast<Map>()) {
      final betName = (bet['name'] as String?) ?? '';
      for (final v in ((bet['values'] as List?) ?? []).cast<Map>()) {
        final label = '${v['value']}';
        final odd = double.tryParse('${v['odd']}');
        final spec = mapMarket(betName, label);
        if (spec == null || odd == null) continue;
        out.add(ProviderOdd(
          spec: spec,
          odds: odd,
          bookmaker: (book['name'] as String?) ?? name,
          rawLabel: '$betName: $label',
          updatedAt: updated,
        ));
      }
    }
    return out;
  }

  /// Maps provider market names to internal market specs. Unmapped markets
  /// are ignored rather than approximated.
  static MarketSpec? mapMarket(String bet, String value) {
    final v = value.trim();
    (String, double)? ou() {
      final m = RegExp(r'^(Over|Under)\s+([0-9.]+)$').firstMatch(v);
      if (m == null) return null;
      return (m.group(1)!.toLowerCase(), double.parse(m.group(2)!));
    }

    switch (bet) {
      case 'Match Winner':
        final p = {'Home': 'home', 'Draw': 'draw', 'Away': 'away'}[v];
        return p == null ? null : MarketSpec(type: MarketType.matchResult, pick: p);
      case 'Double Chance':
        final p = {'Home/Draw': '1X', 'Draw/Away': 'X2', 'Home/Away': '12'}[v];
        return p == null ? null : MarketSpec(type: MarketType.doubleChance, pick: p);
      case 'Goals Over/Under':
        final o = ou();
        return o == null ? null : MarketSpec(type: MarketType.overUnderGoals, pick: o.$1, line: o.$2);
      case 'Goals Over/Under First Half':
        final o = ou();
        return o == null ? null : MarketSpec(type: MarketType.firstHalfGoals, pick: o.$1, line: o.$2);
      case 'Goals Over/Under - Second Half':
        final o = ou();
        return o == null ? null : MarketSpec(type: MarketType.secondHalfGoals, pick: o.$1, line: o.$2);
      case 'Both Teams Score':
        final p = {'Yes': 'yes', 'No': 'no'}[v];
        return p == null ? null : MarketSpec(type: MarketType.btts, pick: p);
      case 'Total - Home':
      case 'Total - Away':
        final o = ou();
        return o == null
            ? null
            : MarketSpec(
                type: MarketType.teamTotalGoals,
                pick: o.$1,
                line: o.$2,
                side: bet.endsWith('Home') ? Side.home : Side.away);
      case 'Corners Over Under':
        final o = ou();
        return o == null ? null : MarketSpec(type: MarketType.totalCorners, pick: o.$1, line: o.$2);
      case 'Asian Handicap':
        final m = RegExp(r'^(Home|Away)\s*([+-]?[0-9.]+)$').firstMatch(v);
        if (m == null) return null;
        return MarketSpec(
            type: MarketType.handicap,
            side: m.group(1) == 'Home' ? Side.home : Side.away,
            line: double.parse(m.group(2)!));
      case 'Draw No Bet':
        final s = {'Home': Side.home, 'Away': Side.away}[v];
        return s == null ? null : MarketSpec(type: MarketType.drawNoBet, side: s);
    }
    return null;
  }

  @override
  Future<List<ProviderInjury>> injuries(String fixtureId) async {
    final list = await _get('/injuries', {'fixture': fixtureId});
    return [
      for (final r in list.cast<Map>())
        ProviderInjury(
          ((r['team'] as Map?)?['name'] as String?) ?? '?',
          ((r['player'] as Map?)?['name'] as String?) ?? '?',
          ((r['player'] as Map?)?['reason'] as String?) ?? '',
        ),
    ];
  }
}
