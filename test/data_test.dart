import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mathbetai/capital/capital.dart';
import 'package:mathbetai/data/ai/ai_explainer.dart';
import 'package:mathbetai/data/api/api_errors.dart';
import 'package:mathbetai/data/api/api_football_provider.dart';
import 'package:mathbetai/data/db/app_database.dart';
import 'package:mathbetai/data/import/importer.dart';
import 'package:mathbetai/data/import/slip_parser.dart';
import 'package:mathbetai/domain/enums.dart';
import 'package:mathbetai/domain/market.dart';
import 'package:mathbetai/domain/selection.dart';
import 'package:mathbetai/engine/kings_visa_engine.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/synthetic.dart';

void main() {
  sqfliteFfiInit();

  group('API failures & offline mode', () {
    ApiFootballProvider provider(int status, String body, {Map<String, String> headers = const {}}) =>
        ApiFootballProvider(apiKey: 'k', client: MockClient((_) async => http.Response(body, status, headers: headers)));

    test('no key → manual mode (ApiNotConfigured), no fabricated fixtures', () async {
      final p = ApiFootballProvider(apiKey: '', client: MockClient((_) async => fail('must not call network')));
      expect(() => p.fixturesOn(testNow), throwsA(isA<ApiNotConfigured>()));
    });
    test('401 → auth error', () {
      expect(() => provider(401, '{}').fixturesOn(testNow), throwsA(isA<ApiAuthException>()));
    });
    test('429 → rate limit with retry-after', () async {
      try {
        await provider(429, '{}', headers: {'retry-after': '30'}).fixturesOn(testNow);
        fail('expected exception');
      } on ApiRateLimitException catch (e) {
        expect(e.retryAfter, const Duration(seconds: 30));
      }
    });
    test('500 → HTTP error', () {
      expect(() => provider(500, 'oops').fixturesOn(testNow), throwsA(isA<ApiHttpException>()));
    });
    test('quota error inside a 200 body → rate limit', () {
      final body = jsonEncode({'errors': {'requests': 'You have reached the request limit for the day'}, 'response': []});
      expect(() => provider(200, body).fixturesOn(testNow), throwsA(isA<ApiRateLimitException>()));
    });
    test('malformed JSON → data error', () {
      expect(() => provider(200, 'not json').fixturesOn(testNow), throwsA(isA<ApiDataException>()));
    });
    test('records with missing fields are skipped, not guessed', () async {
      final body = jsonEncode({
        'errors': [],
        'response': [
          {
            'fixture': {'id': 1, 'timestamp': 1795000000, 'status': {'short': 'NS'}},
            'league': {'name': 'SYN League', 'country': 'Synthland'},
            'teams': {'home': {'id': 1, 'name': 'SYN A'}, 'away': {'id': 2, 'name': 'SYN B'}},
          },
          {
            'fixture': {'id': 2, 'status': {'short': 'NS'}}, // no timestamp
            'league': {'name': 'SYN League'},
            'teams': {'home': {'id': 3, 'name': 'SYN C'}, 'away': {'id': 4, 'name': 'SYN D'}},
          },
        ],
      });
      final list = await provider(200, body).fixturesOn(testNow);
      expect(list.length, 1);
      expect(list.single.homeTeam, 'SYN A');
    });
    test('historical parse builds goal order from events and keeps own goals consistent', () {
      final m = ApiFootballProvider.parseHistorical({
        'fixture': {'id': 9, 'timestamp': 1790000000, 'status': {'short': 'FT'}},
        'league': {'name': 'SYN League'},
        'teams': {'home': {'id': 1, 'name': 'SYN A'}, 'away': {'id': 2, 'name': 'SYN B'}},
        'goals': {'home': 2, 'away': 1},
        'score': {'halftime': {'home': 1, 'away': 0}, 'fulltime': {'home': 2, 'away': 1}},
        'events': [
          {'time': {'elapsed': 10}, 'team': {'id': 1}, 'type': 'Goal', 'detail': 'Normal Goal'},
          {'time': {'elapsed': 30}, 'team': {'id': 2}, 'type': 'Goal', 'detail': 'Missed Penalty'},
          {'time': {'elapsed': 55}, 'team': {'id': 1}, 'type': 'Goal', 'detail': 'Own Goal'},
          {'time': {'elapsed': 60}, 'team': {'id': 2}, 'type': 'Card', 'detail': 'Red Card'},
          {'time': {'elapsed': 70}, 'team': {'id': 1}, 'type': 'Goal', 'detail': 'Penalty'},
        ],
        'statistics': [
          {'team': {'id': 1}, 'statistics': [{'type': 'Corner Kicks', 'value': 7}]},
          {'team': {'id': 2}, 'statistics': [{'type': 'Corner Kicks', 'value': null}]},
        ],
      })!;
      expect(m.origin, DataOrigin.verifiedApi);
      expect(m.hasValidSequence, isTrue);
      expect(m.goalSequence!.map((g) => g.side), [Side.home, Side.away, Side.home]);
      expect(m.redCardsAway, 1);
      expect(m.cornersHome, 7);
    });
    test('provider market names map to exact specs', () {
      final s = ApiFootballProvider.mapMarket('Goals Over/Under', 'Under 2.5')!;
      expect((s.type, s.pick, s.line), (MarketType.overUnderGoals, 'under', 2.5));
      expect(ApiFootballProvider.mapMarket('Unknown market', 'x'), isNull);
    });
    test('AI explainer without key is not called', () {
      final ai = AiExplainer(apiKey: '', client: MockClient((_) async => fail('no call')));
      final s = passingSelection();
      expect(() => ai.explain(s, KingsVisaEngine(clock: () => testNow).audit(s)), throwsA(isA<ApiNotConfigured>()));
    });
  });

  group('Import', () {
    test('JSON import with EAT kickoff interpretation', () {
      final r = Importer.fromJson(jsonEncode([
        {
          'home': 'SYN A',
          'away': 'SYN B',
          'league': 'SYN League',
          'kickoff': '2026-11-22 16:00',
          'market': {'type': 'btts', 'pick': 'no'},
          'odds': '1.80',
          'home_history': [
            {'date': '2026-11-10', 'home': 'SYN A', 'away': 'SYN X', 'ft': '1-0', 'goals': '12H'},
          ],
        },
        {'home': 'SYN C'},
      ]));
      expect(r.selections.length, 2);
      final s = r.selections.first;
      expect(s.kickoff, DateTime.utc(2026, 11, 22, 13));
      expect(s.odds, 1.8);
      expect(s.homeHistory.single.goalSequence!.length, 1);
      expect(s.origin, DataOrigin.userEntered);
    });
    test('CSV history import', () {
      const csv = 'team_role,date,home,away,ft,goals,corners,reds\n'
          'home,2026-11-01,SYN A,SYN B,2-1,10H;50A;80H,5-4,0-1\n'
          'away,2026-11-02,SYN C,SYN D,0-0,-,3-3,0-0\n';
      final r = Importer.historyFromCsv(csv);
      expect(r.errors, isEmpty);
      expect(r.home.single.redCardsAway, 1);
      expect(r.away.single.goalSequence, isEmpty);
    });
    test('slip OCR text becomes drafts only', () {
      final d = SlipParser.parse('SYN Alpha vs SYN Beta\nOver 2.5 Goals 1.85\nSYN Gamma - SYN Delta 2.10');
      expect(d.length, 2);
      expect(d.first.odds, 1.85);
      expect(d.first.marketText, 'Over 2.5 Goals');
      expect(d.last.away, 'SYN Delta');
    });
  });

  group('Persistent database', () {
    late AppDatabase db;
    setUp(() async {
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    });
    tearDown(() => db.close());

    test('selection round-trip with history, checks and scenarios', () async {
      final s = passingSelection();
      final id = await db.saveSelection(Selection(
        homeTeam: s.homeTeam,
        awayTeam: s.awayTeam,
        league: s.league,
        kickoff: s.kickoff,
        market: s.market,
        odds: s.odds,
        oddsUpdatedAt: s.oddsUpdatedAt,
        homeHistory: s.homeHistory,
        awayHistory: s.awayHistory,
        checks: s.checks,
        scenarios: s.scenarios,
      ));
      final back = (await db.getSelection(id))!;
      expect(back.homeHistory.length, 10);
      expect(back.homeHistory.first.goalSequence, isNotNull);
      expect(back.check(StructuralFactor.redCardExposure).uncertainty, isNotEmpty);
      expect(back.scenarios.length, s.scenarios.length);
      expect(back.kickoff, s.kickoff);

      // Same verdict after persistence.
      final engine = KingsVisaEngine(clock: () => testNow);
      expect(engine.audit(back).verdict, engine.audit(s).verdict);

      // Update replaces children.
      await db.saveSelection(back.copyWith(homeHistory: back.homeHistory.take(3).toList()));
      expect((await db.getSelection(id))!.homeHistory.length, 3);
    });

    test('audits are stored and latest is returned; cascade delete', () async {
      final id = await db.saveSelection(Selection(homeTeam: 'SYN A', awayTeam: 'SYN B', market: noThreeInARow));
      final engine = KingsVisaEngine(clock: () => testNow);
      final s = (await db.getSelection(id))!;
      await db.saveAudit(id, engine.audit(s));
      await db.saveAudit(id, engine.audit(s));
      expect((await db.auditHistory(id)).length, 2);
      expect((await db.latestAudit(id))!.verdict, FinalVerdict.incomplete);
      expect((await db.latestAudits()).keys, [id]);
      await db.deleteSelection(id);
      expect(await db.auditCount(), 0);
    });

    test('bets and settings', () async {
      final id = await db.saveBet(Bet(createdAt: testNow, label: 'x', odds: 1.9, stake: 5000));
      await db.saveBet((await db.listBets()).single.copyWith(status: BetStatus.won, settledAt: testNow));
      final b = (await db.listBets()).single;
      expect(b.id, id);
      expect(b.pnl, closeTo(4500, 1e-9));
      await db.setSetting('k', 'v1');
      await db.setSetting('k', 'v2');
      expect(await db.getSetting('k'), 'v2');
    });
  });
}
