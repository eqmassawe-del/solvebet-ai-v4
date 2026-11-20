import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../capital/capital.dart';
import '../../domain/audit.dart';
import '../../domain/enums.dart';
import '../../domain/market.dart';
import '../../domain/match_data.dart';
import '../../domain/selection.dart';

/// SQLite schema (version 1).
///
/// selections ─┬─< evidence_matches   (home/away team history, provenance)
///             ├─< structural_checks  (VISA C inputs)
///             ├─< stress_scenarios   (VISA D inputs)
///             └─< audits             (immutable audit snapshots, JSON report)
/// bets        (paper/real betting ledger, CAPITAL CONTROL)
/// settings    (key/value: engine thresholds, capital limits, preferences)
/// fixture_cache (provider fixtures/odds snapshots with fetch timestamps)
const _schema = <String>[
  '''CREATE TABLE selections(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    match_ref TEXT NOT NULL DEFAULT '',
    home_team TEXT NOT NULL,
    away_team TEXT NOT NULL,
    league TEXT NOT NULL DEFAULT '',
    country TEXT NOT NULL DEFAULT '',
    kickoff INTEGER,
    market TEXT NOT NULL,
    odds REAL,
    odds_source TEXT NOT NULL DEFAULT '',
    odds_updated_at INTEGER,
    data_updated_at INTEGER,
    origin TEXT NOT NULL,
    notes TEXT NOT NULL DEFAULT '',
    actual_outcome TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    last_verdict TEXT,
    last_score REAL
  )''',
  '''CREATE TABLE evidence_matches(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    selection_id INTEGER NOT NULL REFERENCES selections(id) ON DELETE CASCADE,
    team_role TEXT NOT NULL,
    date INTEGER NOT NULL,
    home_team TEXT NOT NULL,
    away_team TEXT NOT NULL,
    competition TEXT NOT NULL DEFAULT '',
    ft_home INTEGER, ft_away INTEGER,
    ht_home INTEGER, ht_away INTEGER,
    goal_seq TEXT,
    corners_home INTEGER, corners_away INTEGER,
    reds_home INTEGER, reds_away INTEGER,
    comparable INTEGER NOT NULL DEFAULT 1,
    source TEXT NOT NULL DEFAULT '',
    origin TEXT NOT NULL,
    market_override TEXT
  )''',
  'CREATE INDEX idx_evidence_sel ON evidence_matches(selection_id)',
  '''CREATE TABLE structural_checks(
    selection_id INTEGER NOT NULL REFERENCES selections(id) ON DELETE CASCADE,
    factor TEXT NOT NULL,
    status TEXT NOT NULL,
    evidence TEXT NOT NULL DEFAULT '',
    uncertainty TEXT NOT NULL DEFAULT '',
    origin TEXT NOT NULL,
    PRIMARY KEY(selection_id, factor)
  )''',
  '''CREATE TABLE stress_scenarios(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    selection_id INTEGER NOT NULL REFERENCES selections(id) ON DELETE CASCADE,
    ord INTEGER NOT NULL,
    kind TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    relevance TEXT NOT NULL,
    pathway TEXT NOT NULL,
    evidence TEXT NOT NULL DEFAULT '',
    severity TEXT NOT NULL,
    evidence_sufficient INTEGER,
    origin TEXT NOT NULL
  )''',
  '''CREATE TABLE audits(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    selection_id INTEGER NOT NULL REFERENCES selections(id) ON DELETE CASCADE,
    created_at INTEGER NOT NULL,
    visa_a TEXT NOT NULL, visa_b TEXT NOT NULL, visa_c TEXT NOT NULL, visa_d TEXT NOT NULL,
    verdict TEXT NOT NULL,
    score REAL,
    engine_version TEXT NOT NULL,
    report TEXT NOT NULL
  )''',
  'CREATE INDEX idx_audits_sel ON audits(selection_id, created_at)',
  '''CREATE TABLE bets(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at INTEGER NOT NULL,
    label TEXT NOT NULL,
    odds REAL NOT NULL,
    stake REAL NOT NULL,
    status TEXT NOT NULL,
    settled_at INTEGER,
    paper INTEGER NOT NULL DEFAULT 1,
    selection_ids TEXT NOT NULL DEFAULT '[]',
    notes TEXT NOT NULL DEFAULT '',
    cost REAL NOT NULL DEFAULT 0
  )''',
  'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  '''CREATE TABLE fixture_cache(
    id TEXT PRIMARY KEY,
    provider TEXT NOT NULL,
    payload TEXT NOT NULL,
    fetched_at INTEGER NOT NULL
  )''',
];

class AppDatabase {
  AppDatabase._(this.db);
  final Database db;

  static Future<AppDatabase> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'mathbetai.db');
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, v) async {
          for (final s in _schema) {
            await db.execute(s);
          }
        },
      ),
    );
    return AppDatabase._(db);
  }

  Future<void> close() => db.close();

  // ------------------------------------------------------------ selections
  Future<int> saveSelection(Selection s) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    return db.transaction((tx) async {
      final row = {
        'match_ref': s.matchRef,
        'home_team': s.homeTeam.trim(),
        'away_team': s.awayTeam.trim(),
        'league': s.league.trim(),
        'country': s.country.trim(),
        'kickoff': s.kickoff?.toUtc().millisecondsSinceEpoch,
        'market': jsonEncode(s.market.toJson()),
        'odds': s.odds,
        'odds_source': s.oddsSource,
        'odds_updated_at': s.oddsUpdatedAt?.toUtc().millisecondsSinceEpoch,
        'data_updated_at': s.dataUpdatedAt?.toUtc().millisecondsSinceEpoch,
        'origin': s.origin.name,
        'notes': s.notes,
        'actual_outcome': s.actualOutcome,
        'updated_at': now,
      };
      int id;
      if (s.id == null) {
        id = await tx.insert('selections', {...row, 'created_at': s.createdAt.millisecondsSinceEpoch});
      } else {
        id = s.id!;
        await tx.update('selections', row, where: 'id = ?', whereArgs: [id]);
        await tx.delete('evidence_matches', where: 'selection_id = ?', whereArgs: [id]);
        await tx.delete('structural_checks', where: 'selection_id = ?', whereArgs: [id]);
        await tx.delete('stress_scenarios', where: 'selection_id = ?', whereArgs: [id]);
      }
      for (final e in [('home', s.homeHistory), ('away', s.awayHistory)]) {
        for (final m in e.$2) {
          final map = m.toMap()..remove('id');
          await tx.insert('evidence_matches', {...map, 'selection_id': id, 'team_role': e.$1});
        }
      }
      for (final c in s.checks) {
        await tx.insert('structural_checks', {
          'selection_id': id,
          'factor': c.factor.name,
          'status': c.status.name,
          'evidence': c.evidence,
          'uncertainty': c.uncertainty,
          'origin': c.origin.name,
        });
      }
      for (var i = 0; i < s.scenarios.length; i++) {
        final sc = s.scenarios[i];
        await tx.insert('stress_scenarios', {
          'selection_id': id,
          'ord': i,
          'kind': sc.kind.name,
          'title': sc.title,
          'description': sc.description,
          'relevance': sc.relevance,
          'pathway': sc.pathway,
          'evidence': sc.evidence,
          'severity': sc.severity.name,
          'evidence_sufficient': sc.evidenceSufficient == null ? null : (sc.evidenceSufficient! ? 1 : 0),
          'origin': sc.origin.name,
        });
      }
      return id;
    });
  }

  Future<Selection?> getSelection(int id) async {
    final rows = await db.query('selections', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return _hydrate(rows.first);
  }

  Future<List<Selection>> listSelections() async {
    final rows = await db.query('selections', orderBy: 'COALESCE(kickoff, created_at) DESC');
    return [for (final r in rows) await _hydrate(r)];
  }

  Future<void> deleteSelection(int id) => db.delete('selections', where: 'id = ?', whereArgs: [id]);

  Future<void> setOutcome(int id, String? outcome) =>
      db.update('selections', {'actual_outcome': outcome}, where: 'id = ?', whereArgs: [id]);

  Future<Selection> _hydrate(Map<String, Object?> r) async {
    final id = r['id'] as int;
    final ev = await db.query('evidence_matches', where: 'selection_id = ?', whereArgs: [id], orderBy: 'date DESC');
    final checksRows = await db.query('structural_checks', where: 'selection_id = ?', whereArgs: [id]);
    final scRows = await db.query('stress_scenarios', where: 'selection_id = ?', whereArgs: [id], orderBy: 'ord');
    DateTime? ts(Object? v) => v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int, isUtc: true);

    final checks = StructuralCheck.defaults().map((d) {
      final row = checksRows.where((c) => c['factor'] == d.factor.name);
      if (row.isEmpty) return d;
      final c = row.first;
      return StructuralCheck(
        factor: d.factor,
        status: CheckStatus.parse(c['status'] as String?),
        evidence: (c['evidence'] as String?) ?? '',
        uncertainty: (c['uncertainty'] as String?) ?? '',
        origin: DataOrigin.parse(c['origin'] as String?),
      );
    }).toList();

    return Selection(
      id: id,
      matchRef: (r['match_ref'] as String?) ?? '',
      homeTeam: r['home_team'] as String,
      awayTeam: r['away_team'] as String,
      league: (r['league'] as String?) ?? '',
      country: (r['country'] as String?) ?? '',
      kickoff: ts(r['kickoff']),
      market: MarketSpec.fromJson(jsonDecode(r['market'] as String) as Map<String, dynamic>),
      odds: (r['odds'] as num?)?.toDouble(),
      oddsSource: (r['odds_source'] as String?) ?? '',
      oddsUpdatedAt: ts(r['odds_updated_at']),
      dataUpdatedAt: ts(r['data_updated_at']),
      origin: DataOrigin.parse(r['origin'] as String?),
      notes: (r['notes'] as String?) ?? '',
      actualOutcome: r['actual_outcome'] as String?,
      createdAt: ts(r['created_at']),
      homeHistory: ev.where((e) => e['team_role'] == 'home').map((e) => HistoricalMatch.fromMap(e)).toList(),
      awayHistory: ev.where((e) => e['team_role'] == 'away').map((e) => HistoricalMatch.fromMap(e)).toList(),
      checks: checks,
      scenarios: scRows
          .map((c) => StressScenario(
                kind: ScenarioKind.parse(c['kind'] as String?),
                title: c['title'] as String,
                description: c['description'] as String,
                relevance: c['relevance'] as String,
                pathway: c['pathway'] as String,
                evidence: (c['evidence'] as String?) ?? '',
                severity: Severity.parse(c['severity'] as String?),
                evidenceSufficient: c['evidence_sufficient'] == null ? null : c['evidence_sufficient'] == 1,
                origin: DataOrigin.parse(c['origin'] as String?),
              ))
          .toList(),
    );
  }

  // ---------------------------------------------------------------- audits
  Future<int> saveAudit(int selectionId, AuditReport r) async {
    return db.transaction((tx) async {
      final id = await tx.insert('audits', {
        'selection_id': selectionId,
        'created_at': r.createdAt.millisecondsSinceEpoch,
        'visa_a': r.visaA.outcome.name,
        'visa_b': r.visaB.outcome.name,
        'visa_c': r.visaC.outcome.name,
        'visa_d': r.visaD.outcome.name,
        'verdict': r.verdict.name,
        'score': r.score?.total,
        'engine_version': r.engineVersion,
        'report': jsonEncode(r.toJson()),
      });
      await tx.update('selections', {'last_verdict': r.verdict.name, 'last_score': r.score?.total},
          where: 'id = ?', whereArgs: [selectionId]);
      return id;
    });
  }

  Future<AuditReport?> latestAudit(int selectionId) async {
    final rows = await db.query('audits',
        where: 'selection_id = ?', whereArgs: [selectionId], orderBy: 'created_at DESC, id DESC', limit: 1);
    if (rows.isEmpty) return null;
    return _audit(rows.first);
  }

  Future<List<AuditReport>> auditHistory(int selectionId) async {
    final rows = await db.query('audits',
        where: 'selection_id = ?', whereArgs: [selectionId], orderBy: 'created_at DESC, id DESC');
    return rows.map(_audit).toList();
  }

  /// Latest audit per selection.
  Future<Map<int, AuditReport>> latestAudits() async {
    final rows = await db.rawQuery('''
      SELECT a.* FROM audits a
      JOIN (SELECT selection_id, MAX(id) AS mid FROM audits GROUP BY selection_id) l
        ON a.id = l.mid''');
    return {for (final r in rows) r['selection_id'] as int: _audit(r)};
  }

  AuditReport _audit(Map<String, Object?> r) => AuditReport.fromJson(
        jsonDecode(r['report'] as String) as Map<String, dynamic>,
        id: r['id'] as int,
        selectionId: r['selection_id'] as int,
      );

  Future<int> auditCount() async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM audits')) ?? 0;

  // ------------------------------------------------------------------ bets
  Future<int> saveBet(Bet b) async {
    if (b.id == null) return db.insert('bets', b.toMap());
    await db.update('bets', b.toMap(), where: 'id = ?', whereArgs: [b.id]);
    return b.id!;
  }

  Future<List<Bet>> listBets() async =>
      (await db.query('bets', orderBy: 'created_at DESC, id DESC')).map(Bet.fromMap).toList();

  Future<void> deleteBet(int id) => db.delete('bets', where: 'id = ?', whereArgs: [id]);

  // -------------------------------------------------------------- settings
  Future<String?> getSetting(String key) async {
    final r = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) =>
      db.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  // --------------------------------------------------------- fixture cache
  Future<void> cacheFixture(String id, String provider, String payload) => db.insert(
        'fixture_cache',
        {'id': id, 'provider': provider, 'payload': payload, 'fetched_at': DateTime.now().toUtc().millisecondsSinceEpoch},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<({String payload, DateTime fetchedAt})?> cachedFixture(String id) async {
    final r = await db.query('fixture_cache', where: 'id = ?', whereArgs: [id]);
    if (r.isEmpty) return null;
    return (
      payload: r.first['payload'] as String,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(r.first['fetched_at'] as int, isUtc: true),
    );
  }
}
