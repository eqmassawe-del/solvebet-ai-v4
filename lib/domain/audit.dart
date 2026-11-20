import 'enums.dart';
import 'market.dart';

/// One historical observation as settled by the market evaluator.
class ObservationRecord {
  const ObservationRecord({
    required this.date,
    required this.label,
    required this.settlement,
    required this.comparable,
    required this.origin,
    this.source = '',
    this.margin,
    this.venue,
    this.hadRedCard,
    this.note = '',
  });

  final DateTime date;

  /// e.g. "Simba 2-1 Yanga".
  final String label;
  final Settlement settlement;
  final bool comparable;
  final DataOrigin origin;
  final String source;

  /// Market safety margin (positive = cushion), when meaningful.
  final double? margin;

  /// Venue of the *team whose history this is*.
  final Side? venue;
  final bool? hadRedCard;
  final String note;

  Map<String, dynamic> toJson() => {
        'date': date.millisecondsSinceEpoch,
        'label': label,
        'settlement': settlement.name,
        'comparable': comparable,
        'origin': origin.name,
        'source': source,
        'margin': margin,
        'venue': venue?.name,
        'red': hadRedCard,
        'note': note,
      };

  factory ObservationRecord.fromJson(Map<String, dynamic> j) => ObservationRecord(
        date: DateTime.fromMillisecondsSinceEpoch(j['date'] as int, isUtc: true),
        label: j['label'] as String,
        settlement: Settlement.values.firstWhere((s) => s.name == j['settlement'],
            orElse: () => Settlement.unknown),
        comparable: j['comparable'] as bool? ?? true,
        origin: DataOrigin.parse(j['origin'] as String?),
        source: (j['source'] as String?) ?? '',
        margin: (j['margin'] as num?)?.toDouble(),
        venue: j['venue'] == null ? null : Side.parse(j['venue'] as String?),
        hadRedCard: j['red'] as bool?,
        note: (j['note'] as String?) ?? '',
      );
}

/// Failure statistics with explicit denominators for one evidence window.
class FailureStats {
  const FailureStats({
    required this.label,
    required this.considered,
    required this.valid,
    required this.failures,
    required this.unknown,
    required this.pushes,
    required this.nonComparable,
  });

  final String label;

  /// Observations inside the window (before exclusions).
  final int considered;

  /// Valid comparable observations (the denominator).
  final int valid;
  final int failures;
  final int unknown;
  final int pushes;
  final int nonComparable;

  /// Failure Rate = failures / valid comparable observations.
  double? get failureRate => valid == 0 ? null : failures / valid;

  /// Historical success rate = 1 − failure rate. NOT a calibrated probability.
  double? get successRate => failureRate == null ? null : 1 - failureRate!;

  String get summary {
    final fr = failureRate;
    final pct = fr == null ? 'n/a' : '${(fr * 100).toStringAsFixed(0)}%';
    return '$label: $failures failures / $valid valid ($pct)'
        '${unknown > 0 ? ', $unknown unknown' : ''}'
        '${pushes > 0 ? ', $pushes void' : ''}'
        '${nonComparable > 0 ? ', $nonComparable non-comparable excluded' : ''}';
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'considered': considered,
        'valid': valid,
        'failures': failures,
        'unknown': unknown,
        'pushes': pushes,
        'nonComparable': nonComparable,
      };

  factory FailureStats.fromJson(Map<String, dynamic> j) => FailureStats(
        label: j['label'] as String,
        considered: j['considered'] as int,
        valid: j['valid'] as int,
        failures: j['failures'] as int,
        unknown: j['unknown'] as int,
        pushes: j['pushes'] as int,
        nonComparable: j['nonComparable'] as int,
      );
}

enum FindingLevel { info, ok, watch, fail, unknown }

class Finding {
  const Finding(this.level, this.text, {this.origin = DataOrigin.engineDerived});

  final FindingLevel level;
  final String text;
  final DataOrigin origin;

  Map<String, dynamic> toJson() => {'l': level.name, 't': text, 'o': origin.name};

  factory Finding.fromJson(Map<String, dynamic> j) => Finding(
        FindingLevel.values.firstWhere((l) => l.name == j['l'], orElse: () => FindingLevel.info),
        j['t'] as String,
        origin: DataOrigin.parse(j['o'] as String?),
      );
}

class VisaStageResult {
  const VisaStageResult({
    required this.stage,
    required this.title,
    required this.outcome,
    this.findings = const [],
    this.stats = const [],
    this.records = const {},
  });

  /// 'A', 'B', 'C' or 'D'.
  final String stage;
  final String title;
  final VisaOutcome outcome;
  final List<Finding> findings;
  final List<FailureStats> stats;

  /// Source records keyed by group label (e.g. "Home team history").
  final Map<String, List<ObservationRecord>> records;

  Iterable<Finding> get blocking => findings.where(
      (f) => f.level == FindingLevel.fail || f.level == FindingLevel.unknown);

  Map<String, dynamic> toJson() => {
        'stage': stage,
        'title': title,
        'outcome': outcome.name,
        'findings': findings.map((f) => f.toJson()).toList(),
        'stats': stats.map((s) => s.toJson()).toList(),
        'records': records.map((k, v) => MapEntry(k, v.map((r) => r.toJson()).toList())),
      };

  factory VisaStageResult.fromJson(Map<String, dynamic> j) => VisaStageResult(
        stage: j['stage'] as String,
        title: j['title'] as String,
        outcome: VisaOutcome.parse(j['outcome'] as String?),
        findings: ((j['findings'] as List?) ?? [])
            .map((e) => Finding.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        stats: ((j['stats'] as List?) ?? [])
            .map((e) => FailureStats.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        records: ((j['records'] as Map?) ?? {}).map((k, v) => MapEntry(
            k as String,
            (v as List)
                .map((e) => ObservationRecord.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList())),
      );
}

/// Explainable evidence score (0–100). This is a ranking aid, NOT a win
/// probability.
class EvidenceScore {
  const EvidenceScore({required this.total, required this.components, required this.weights});

  final double total;

  /// Component values in 0..1.
  final Map<String, double> components;
  final Map<String, double> weights;

  Map<String, dynamic> toJson() => {'total': total, 'components': components, 'weights': weights};

  factory EvidenceScore.fromJson(Map<String, dynamic> j) => EvidenceScore(
        total: (j['total'] as num).toDouble(),
        components: Map<String, dynamic>.from(j['components'] as Map)
            .map((k, v) => MapEntry(k, (v as num).toDouble())),
        weights: Map<String, dynamic>.from(j['weights'] as Map)
            .map((k, v) => MapEntry(k, (v as num).toDouble())),
      );
}

class AuditReport {
  const AuditReport({
    this.id,
    this.selectionId,
    required this.createdAt,
    required this.visaA,
    required this.visaB,
    required this.visaC,
    required this.visaD,
    required this.verdict,
    required this.failureCondition,
    required this.failureEvidence,
    required this.primaryRisk,
    required this.reasoning,
    this.score,
    this.engineVersion = kEngineVersion,
  });

  final int? id;
  final int? selectionId;
  final DateTime createdAt;
  final VisaStageResult visaA;
  final VisaStageResult visaB;
  final VisaStageResult visaC;
  final VisaStageResult visaD;
  final FinalVerdict verdict;

  /// The specific event that would make the selection lose.
  final String failureCondition;
  final String failureEvidence;
  final String primaryRisk;
  final String reasoning;

  /// Only computed for selections that are not REJECTED/INCOMPLETE.
  final EvidenceScore? score;
  final String engineVersion;

  List<VisaStageResult> get stages => [visaA, visaB, visaC, visaD];

  Map<String, dynamic> toJson() => {
        'createdAt': createdAt.millisecondsSinceEpoch,
        'a': visaA.toJson(),
        'b': visaB.toJson(),
        'c': visaC.toJson(),
        'd': visaD.toJson(),
        'verdict': verdict.name,
        'failureCondition': failureCondition,
        'failureEvidence': failureEvidence,
        'primaryRisk': primaryRisk,
        'reasoning': reasoning,
        'score': score?.toJson(),
        'engineVersion': engineVersion,
      };

  factory AuditReport.fromJson(Map<String, dynamic> j, {int? id, int? selectionId}) =>
      AuditReport(
        id: id,
        selectionId: selectionId,
        createdAt: DateTime.fromMillisecondsSinceEpoch(j['createdAt'] as int, isUtc: true),
        visaA: VisaStageResult.fromJson(Map<String, dynamic>.from(j['a'] as Map)),
        visaB: VisaStageResult.fromJson(Map<String, dynamic>.from(j['b'] as Map)),
        visaC: VisaStageResult.fromJson(Map<String, dynamic>.from(j['c'] as Map)),
        visaD: VisaStageResult.fromJson(Map<String, dynamic>.from(j['d'] as Map)),
        verdict: FinalVerdict.tryParse(j['verdict'] as String?) ?? FinalVerdict.incomplete,
        failureCondition: (j['failureCondition'] as String?) ?? '',
        failureEvidence: (j['failureEvidence'] as String?) ?? '',
        primaryRisk: (j['primaryRisk'] as String?) ?? '',
        reasoning: (j['reasoning'] as String?) ?? '',
        score: j['score'] == null
            ? null
            : EvidenceScore.fromJson(Map<String, dynamic>.from(j['score'] as Map)),
        engineVersion: (j['engineVersion'] as String?) ?? kEngineVersion,
      );
}

const kEngineVersion = 'kings-visa-1.0.0';
