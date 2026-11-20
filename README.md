# MATHematics BET AI (MathBetAI)

An Android app that audits football betting selections with a deterministic decision framework called **KING'S VISA**. It looks for evidence that a selection could fail, rejects anything weak or missing evidence, ranks what is left, builds risk-aware accumulators, and tracks a bankroll.

> **No guarantees.** An APPROVED verdict means only that no failure pathway was found in the evidence you recorded. It does not mean the bet will win. The app never invents fixtures, statistics, line-ups, injuries, odds or probabilities.

- Package: `com.mathbetai.app` · Android 10+ (minSdk 29)
- Flutter 3.50.1 / Dart 3.14 · Material 3 · Riverpod 3 · SQLite (sqflite)
- Timezone: Africa/Dar_es_Salaam (EAT, UTC+3, no daylight saving, so a fixed offset is used)

---

## 1. Architecture

```
lib/
  domain/           Pure models: matches, markets, selections, audit reports, data provenance
  engine/           KING'S VISA (deterministic, no I/O)
    markets/        One evaluator per market (settlement, failure condition, margin, stress templates)
    visa_a.dart     Market & identity            → PASS / FAIL / UNKNOWN
    visa_b.dart     Current failure evidence     → PASS / FAIL / WATCH / UNKNOWN
    visa_c.dart     Structural risk (+ mandatory red-card check)
    visa_d.dart     Stress & adversarial test
    decision_matrix.dart   Final verdict (outcomes only; scores cannot reach it)
    scoring.dart    Explainable 0–100 evidence score (ranking only)
    kings_visa_engine.dart Orchestrator
  builder/          KING'S BUILDER: best-of-available accumulator, correlation and exposure checks
  capital/          CAPITAL CONTROL: ledger metrics, stake limits, target assessment, Monte-Carlo simulator
  data/
    db/             SQLite schema and repository
    api/            Provider abstraction + API-Football implementation with typed errors
    import/         CSV/JSON importer, betting-slip OCR parser (drafts only)
    ai/             Optional Claude explainer (labelled MODEL-GENERATED, never evidence)
    secure_store.dart  Android Keystore-backed credential storage
  state/            Riverpod providers
  ui/               Screens and widgets
```

### Data provenance

Every record carries a `DataOrigin`, shown as a badge in the UI:

| Origin | Meaning | Counts as evidence? |
|---|---|---|
| `VERIFIED (API)` | Retrieved from the configured licensed provider | Yes |
| `USER-ENTERED` | Typed or imported by you | Yes (you are the source) |
| `ENGINE-DERIVED` | Computed by the engine from other records | Context only |
| `MODEL-GENERATED` | AI text | **Never.** A mandatory check fed with it stays UNKNOWN |
| `SYNTHETIC TEST DATA` | Test fixtures | **Never.** VISA A FAILS any selection that contains it |

### Database schema (SQLite v1)

| Table | Purpose |
|---|---|
| `selections` | Fixture identity, market spec (JSON), odds and odds timestamp, origin, notes, recorded result, latest verdict and score |
| `evidence_matches` | Per-selection home and away team history: FT/HT scores, goal sequence, corners, red cards, comparability, source, origin |
| `structural_checks` | VISA C inputs per factor: status, evidence, uncertainty, origin |
| `stress_scenarios` | VISA D inputs: scenario, relevance, pathway, evidence, severity, evidence sufficiency |
| `audits` | Immutable audit snapshots (full JSON report, stage outcomes, verdict, score, engine version) |
| `bets` | Paper or real ledger: stake, odds, status, settlement time, cost |
| `settings` | Engine thresholds, capital limits, preferences |
| `fixture_cache` | Provider payload snapshots with fetch timestamps |

Foreign keys cascade, so deleting a selection removes its evidence and audits.

---

## 2. KING'S VISA

Each selection passes through four separate stages.

**VISA A, market & identity.** Checks the teams (present and different), competition, kickoff (present and in the future), the exact market definition and settlement rule, the explicit failure event, the decimal odds (within range and not stale), and whether history exists and is current. It also confirms that every history record actually contains the team. Synthetic or AI-generated records cause a FAIL. Missing information gives UNKNOWN, never PASS.

**VISA B, current failure evidence.** Each team's history is settled against the exact market:

- Last 5 (most weight), last 10 (trend), and the last 3 (any failure there triggers WATCH).
- `Failure Rate = failures / valid comparable observations`. Denominators, unknowns, voids and excluded non-comparable matches are all shown.
- Venue splits (home team at home, away team away), margin-of-safety deterioration, and red-card history.
- An observation that cannot be settled (for example, no goal order for a 3–1 in "3 in a row") is **UNKNOWN**, never a success.
- The historical success rate is labelled descriptive. It is not a calibrated probability.

Mirrored perspective: in the away team's history, a "home win" selection fails whenever the away team avoided defeat.

**VISA C, structural risk.** Thirteen factors. Motivation, line-ups, injuries/suspensions and **red-card exposure** are mandatory and need written evidence. The red-card check also needs a stated uncertainty. CRITICAL → FAIL, CONCERN → WATCH, and a missing mandatory check → UNKNOWN.

**VISA D, stress & adversarial test.** Market-specific adverse scenarios (early red card, early goal, injury, rotation, stronger opponent, collapse, late surge, low-probability states). Each scenario records its description, relevance, plausibility evidence, failure pathway, severity, and whether the evidence is sufficient. No numeric probabilities are assigned. A red-card scenario is mandatory.

- CRITICAL → FAIL.
- HIGH with sufficient evidence → WATCH; HIGH with insufficient evidence → UNKNOWN.
- The engine cross-checks the history. If the market failed in at least half of three or more past matches where the condition actually happened, a LOW or MEDIUM rating is flagged WATCH.

### Decision matrix (`engine/decision_matrix.dart`)

| Rule | Final |
|---|---|
| Any FAIL | REJECTED |
| Any UNKNOWN (no FAIL) | INCOMPLETE |
| Any WATCH (no FAIL/UNKNOWN) | WATCH |
| Four PASS | APPROVED |

`decide()` receives only the four stage outcomes, so no score or setting can override a failed gate. Thresholds in Settings are clamped (`EngineConfig.sanitized`), so they cannot switch a gate off.

### Evidence score (0–100)

The score is computed only for APPROVED or WATCH selections. It is `Σ(component × weight) / Σweights × 100`, with these default weights (all editable in Settings):

| Component | Weight | Definition |
|---|---|---|
| Recent market behaviour | 25 | 1 − blended failure rate (last 5 weighted 2:1 over last 10) |
| Quality & size of evidence | 15 | valid observations ÷ 20 × (1 − unknown share) |
| Comparable-opponent evidence | 10 | share of observations marked comparable |
| Market-specific safety margin | 15 | average cushion versus the line, capped at 2 (0.5 for markets without a margin) |
| Structural stability | 15 | 1 − penalties (0.15 per concern, 0.5 per critical, 0.03 per unassessed optional factor) |
| Stress-test resilience | 10 | 1 − mean severity / 4 |
| Data freshness | 10 | odds age and history recency |

The score measures evidence strength. **It is not a win probability.**

### Markets

| Group | Markets |
|---|---|
| Core | 1X2, Double Chance, Over/Under, BTTS, Team Total, Total Corners, Team Corners, Asian Handicap (including quarter lines) |
| Special | Any Team To Score 3 in a Row YES/NO, Team To Score Consecutive Goals, 1st/2nd Half Goals, Draw No Bet |
| Custom | User-defined win and failure conditions. You record WIN/LOSE for each past match yourself |

Goal-order markets use the final score only where the answer is logically certain: neither side reached 3 goals, or one side scored 3+ while the other scored none. Otherwise the recorded goal sequence is required, and it must agree with the final score.

---

## 3. Screens

| Screen | What it does |
|---|---|
| **Command** (dashboard) | Totals by verdict, bankroll, exposure, drawdown, top approved |
| **King's Scanner** | With an API key: fixtures for today and the next 2 days (search, source and fetch time, English leagues hidden by default). Pick a priced market to fetch both teams' last 10 matches and injuries, then audit. Without a key: manual mode, CSV/JSON import, slip OCR |
| **My Selections** | Tabs for Approved (ranked by score), Watch, Incomplete, Rejected, Not audited, All. Search, and re-audit all |
| **Selection editor** | Tabs A to D covering every engine input, with live settlement of each history row |
| **King's VISA Report** | Summary block (MATCH, MARKET, ODDS, verdict, score, FAILURE EVIDENCE, PRIMARY RISK, FINAL REASONING), expandable stages with failure-rate tables and source records, score breakdown, optional AI explanation, audit history, record result or paper bet |
| **King's Builder** | Target 2/5/10/20/50/100 or custom. Max legs, minimum score, league cap. Best combination or best-of-available, shortlist, exclusions with reasons, correlation warnings |
| **Capital Control** | Bankroll, P/L, ROI, yield, streaks, drawdown, equity curve, stake advice within limits, daily target assessment, risk of ruin, ledger, Monte-Carlo simulator |
| **Performance Lab** | Hit rate by verdict, by market and by score band; bookmaker-implied comparison; backtest with current thresholds; strategy validation |
| **Settings** | API keys (secure storage), AI model, English leagues, language (English/Kiswahili), thresholds, score weights, capital limits |

---

## 4. What needs a key or subscription

| Feature | Requirement | Without it |
|---|---|---|
| Live fixtures, team history, injuries | **API-Football key** (api-sports.io). The free tier is about 100 requests/day | Manual mode and import |
| Bookmaker odds in the Scanner | **API-Football paid plan** for most leagues | Enter odds manually |
| AI explanation of audits | **Anthropic API key** (billed per use). Default model `claude-opus-5-5`, configurable | The section shows "not configured". Verdicts are unaffected |
| Slip screenshot OCR | None: on-device Google ML Kit | — |

Every other feature works offline.

---

## 5. Import formats

Ready-made templates are in `docs/examples/`. They use placeholder teams marked `origin: synthetic`, so the engine always rejects them. Replace them with real, verified data.

- **JSON:** `{"selections": [{home, away, league, country, kickoff, market:{type,pick,side,line,...}, odds, odds_source, odds_updated_at, home_history:[...], away_history:[...]}]}`
- **History rows:** `{date, home, away, competition, ft:"2-1", ht:"1-0", goals:"12H,55A,80H", corners:"6-4", reds:"0-1", comparable, source, market_result}`
- **Selections CSV:** `home,away,league,country,kickoff,market_type,pick,side,line,odds,odds_source,odds_updated_at`
- **History CSV:** `team_role,date,home,away,competition,ft,ht,goals,corners,reds,comparable,source` (separate goal tokens with `;`)
- Market `type` values: `matchResult, doubleChance, overUnderGoals, btts, teamTotalGoals, totalCorners, teamCorners, handicap, anyTeam3InARow, teamConsecutiveGoals, firstHalfGoals, secondHalfGoals, drawNoBet, custom`
- Times without an offset are read as EAT.

Slip screenshots only produce **drafts**. Each one opens in the editor for you to verify before it is saved.

---

## 6. Build & run

Prerequisites: Flutter 3.50.1 (stable), JDK 17+, Android SDK (platform 36, build-tools 36).

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug      # build/app/outputs/flutter-apk/app-debug.apk
flutter build apk --release    # build/app/outputs/flutter-apk/app-release.apk
```

Install on a device with `adb install build/app/outputs/flutter-apk/app-debug.apk`.

### Signed release APK

1. Create a keystore (once) and keep it safe:
   ```bash
   keytool -genkey -v -keystore ~/mathbetai-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias mathbetai
   ```
2. Create `android/key.properties` (it is git-ignored):
   ```properties
   storeFile=/absolute/path/to/mathbetai-release.jks
   storePassword=...
   keyAlias=mathbetai
   keyPassword=...
   ```
3. Run `flutter build apk --release`. Without `key.properties`, the release build is signed with the debug key. It installs fine but cannot be uploaded to Play.

### GitHub Actions

`.github/workflows/android.yml` runs analyze, tests, and debug and release builds on every push, then uploads both APKs as the `mathbetai-apks` artifact. To sign releases in CI, add these repository secrets: `ANDROID_KEYSTORE_BASE64` (`base64 -w0 release.jks`), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`.

---

## 7. Tests

`flutter test` runs 80 tests:

- Decision matrix: all six table rows plus all 256 outcome combinations.
- Each VISA stage, including mandatory rejection and UNKNOWN never becoming PASS.
- The mandatory red-card checks, missing histories, and model-generated and synthetic provenance.
- Settlement for every market, including quarter lines and the mirrored perspective, and goal-sequence logic.
- Builder: WATCH removal, odds product, the target not being forced, shared-match exposure, correlation warnings.
- Capital: P/L, yield, ROI, streaks, drawdown, stake limits, daily loss limit, simulation.
- API failures: no key, 401, 429, 5xx, quota errors inside a 200 response, malformed JSON, missing fields.
- Import and OCR parsing, SQLite round-trips, cascade deletes, the example files, and an app start-up smoke test.

The synthetic dataset lives in `test/support/synthetic.dart` (every team is prefixed `SYN`). It is used only by tests and is never shipped as matches.

---

## 8. Known limitations

- The red-card, line-up, motivation and stress assessments are your judgement, backed by evidence you document. The app structures and enforces that work, but it cannot do it for you.
- API-Football's own-goal attribution is handled by checking the goal sequence against the final score. If they cannot be made consistent, the order is left UNKNOWN.
- Swahili translation covers navigation and the main labels. Other strings fall back to English (`lib/core/l10n.dart`).
- The evidence-score weights are heuristics. Use the Performance Lab to check them against your own recorded results before relying on them.
