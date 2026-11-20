import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../capital/capital.dart';
import '../core/l10n.dart';
import '../data/ai/ai_explainer.dart';
import '../data/api/api_football_provider.dart';
import '../data/api/football_provider.dart';
import '../data/db/app_database.dart';
import '../data/secure_store.dart';
import '../domain/audit.dart';
import '../domain/enums.dart';
import '../domain/selection.dart';
import '../engine/engine_config.dart';
import '../engine/kings_visa_engine.dart';

/// Overridden in `main()` with the opened database.
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError('database not opened'));

final secretStoreProvider = Provider<SecretStore>((ref) => SecureSecretStore());

class AppSettings {
  const AppSettings({
    this.engine = const EngineConfig(),
    this.capital = const CapitalSettings(),
    this.includeEnglishLeagues = false,
    this.language = 'en',
    this.aiModel = 'claude-opus-5-5',
    this.hasFootballKey = false,
    this.hasAiKey = false,
  });

  final EngineConfig engine;
  final CapitalSettings capital;

  /// English leagues are excluded from default recommendations unless enabled.
  final bool includeEnglishLeagues;
  final String language;
  final String aiModel;
  final bool hasFootballKey;
  final bool hasAiKey;

  S get s => S(language);

  AppSettings copyWith({
    EngineConfig? engine,
    CapitalSettings? capital,
    bool? includeEnglishLeagues,
    String? language,
    String? aiModel,
    bool? hasFootballKey,
    bool? hasAiKey,
  }) =>
      AppSettings(
        engine: engine ?? this.engine,
        capital: capital ?? this.capital,
        includeEnglishLeagues: includeEnglishLeagues ?? this.includeEnglishLeagues,
        language: language ?? this.language,
        aiModel: aiModel ?? this.aiModel,
        hasFootballKey: hasFootballKey ?? this.hasFootballKey,
        hasAiKey: hasAiKey ?? this.hasAiKey,
      );
}

class SettingsController extends AsyncNotifier<AppSettings> {
  AppDatabase get _db => ref.read(databaseProvider);
  SecretStore get _secrets => ref.read(secretStoreProvider);

  @override
  Future<AppSettings> build() async {
    final engine = EngineConfig.decode(await _db.getSetting('engine'));
    final capRaw = await _db.getSetting('capital');
    final capital = capRaw == null
        ? const CapitalSettings()
        : CapitalSettings.fromJson(jsonDecode(capRaw) as Map<String, dynamic>);
    return AppSettings(
      engine: engine,
      capital: capital,
      includeEnglishLeagues: (await _db.getSetting('includeEnglish')) == 'true',
      language: (await _db.getSetting('language')) ?? 'en',
      aiModel: (await _db.getSetting('aiModel')) ?? 'claude-opus-5-5',
      hasFootballKey: ((await _secrets.read(SecretKeys.footballApiKey)) ?? '').isNotEmpty,
      hasAiKey: ((await _secrets.read(SecretKeys.aiApiKey)) ?? '').isNotEmpty,
    );
  }

  Future<void> save(AppSettings s) async {
    await _db.setSetting('engine', s.engine.sanitized().encode());
    await _db.setSetting('capital', jsonEncode(s.capital.toJson()));
    await _db.setSetting('includeEnglish', '${s.includeEnglishLeagues}');
    await _db.setSetting('language', s.language);
    await _db.setSetting('aiModel', s.aiModel);
    final cur = state.value;
    state = AsyncData(s.copyWith(
      engine: s.engine.sanitized(),
      hasFootballKey: cur?.hasFootballKey,
      hasAiKey: cur?.hasAiKey,
    ));
  }

  Future<void> setSecret(String key, String? value) async {
    await _secrets.write(key, value?.trim());
    ref.invalidateSelf();
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsController, AppSettings>(SettingsController.new);

final engineProvider = Provider<KingsVisaEngine>((ref) {
  final s = ref.watch(settingsProvider).value ?? const AppSettings();
  return KingsVisaEngine(config: s.engine);
});

final stringsProvider = Provider<S>((ref) => (ref.watch(settingsProvider).value ?? const AppSettings()).s);

/// Live data provider, or null in manual mode (no key configured).
final footballDataProvider = FutureProvider<FootballDataProvider?>((ref) async {
  ref.watch(settingsProvider);
  final key = await ref.read(secretStoreProvider).read(SecretKeys.footballApiKey);
  if (key == null || key.trim().isEmpty) return null;
  return ApiFootballProvider(apiKey: key);
});

final aiExplainerProvider = FutureProvider<AiExplainer?>((ref) async {
  final s = await ref.watch(settingsProvider.future);
  final key = await ref.read(secretStoreProvider).read(SecretKeys.aiApiKey);
  if (key == null || key.trim().isEmpty) return null;
  return AiExplainer(apiKey: key, model: s.aiModel);
});

class AuditedSelection {
  const AuditedSelection(this.selection, this.audit);
  final Selection selection;
  final AuditReport? audit;
  FinalVerdict? get verdict => audit?.verdict;
  double? get score => audit?.score?.total;
}

const _englishMarkers = ['england', 'premier league', 'championship', 'league one', 'league two', 'fa cup', 'efl'];

bool isEnglishLeague(Selection s) {
  final c = s.country.toLowerCase(), l = s.league.toLowerCase();
  if (c == 'england') return true;
  return c.isEmpty && _englishMarkers.any((m) => l.contains(m)) && !l.contains('scottish');
}

class SelectionsController extends AsyncNotifier<List<AuditedSelection>> {
  AppDatabase get _db => ref.read(databaseProvider);

  @override
  Future<List<AuditedSelection>> build() async {
    final sels = await _db.listSelections();
    final audits = await _db.latestAudits();
    return sels.map((s) => AuditedSelection(s, audits[s.id])).toList();
  }

  Future<int> save(Selection s) async {
    final id = await _db.saveSelection(s.copyWith(dataUpdatedAt: DateTime.now().toUtc()));
    ref.invalidateSelf();
    await future;
    return id;
  }

  /// Runs the deterministic engine and stores an immutable audit snapshot.
  Future<AuditReport> audit(int id) async {
    final s = await _db.getSelection(id);
    if (s == null) throw StateError('Selection $id not found');
    final r = ref.read(engineProvider).audit(s);
    await _db.saveAudit(id, r);
    ref.invalidateSelf();
    await future;
    return r;
  }

  Future<int> auditAll() async {
    final list = await _db.listSelections();
    final engine = ref.read(engineProvider);
    for (final s in list) {
      await _db.saveAudit(s.id!, engine.audit(s));
    }
    ref.invalidateSelf();
    await future;
    return list.length;
  }

  Future<void> delete(int id) async {
    await _db.deleteSelection(id);
    ref.invalidateSelf();
  }

  Future<void> setOutcome(int id, String? outcome) async {
    await _db.setOutcome(id, outcome);
    ref.invalidateSelf();
  }
}

final selectionsProvider =
    AsyncNotifierProvider<SelectionsController, List<AuditedSelection>>(SelectionsController.new);

class BetsController extends AsyncNotifier<List<Bet>> {
  AppDatabase get _db => ref.read(databaseProvider);
  @override
  Future<List<Bet>> build() => _db.listBets();

  Future<void> save(Bet b) async {
    await _db.saveBet(b);
    ref.invalidateSelf();
  }

  Future<void> delete(int id) async {
    await _db.deleteBet(id);
    ref.invalidateSelf();
  }
}

final betsProvider = AsyncNotifierProvider<BetsController, List<Bet>>(BetsController.new);

final metricsProvider = Provider<BankrollMetrics?>((ref) {
  final bets = ref.watch(betsProvider).value;
  final s = ref.watch(settingsProvider).value;
  if (bets == null || s == null) return null;
  return CapitalEngine.compute(bets, s.capital);
});
