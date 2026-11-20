import '../domain/audit.dart';
import '../domain/enums.dart';
import '../domain/selection.dart';
import 'engine_config.dart';

/// VISA C — STRUCTURAL RISK. Outcomes: PASS, FAIL, WATCH, UNKNOWN.
///
/// Mandatory factors (motivation, line-ups, injuries/suspensions and the
/// red-card exposure check) must be assessed with written evidence. The
/// red-card check additionally requires a written statement of uncertainty —
/// red cards cannot be predicted reliably; the purpose is to identify whether
/// one would open a serious failure pathway for this market.
VisaStageResult evaluateVisaC(Selection s, EngineConfig cfg) {
  final f = <Finding>[];
  var hasFail = false, hasUnknown = false, hasWatch = false;

  for (final factor in StructuralFactor.values) {
    final c = s.check(factor);
    final usable = c.origin != DataOrigin.modelGenerated && c.origin != DataOrigin.synthetic;
    final assessed = c.status != CheckStatus.notAssessed && c.evidence.trim().isNotEmpty && usable;

    if (factor == StructuralFactor.redCardExposure) {
      if (!assessed || c.uncertainty.trim().isEmpty) {
        hasUnknown = true;
        f.add(Finding(
          FindingLevel.unknown,
          'MANDATORY red-card assessment incomplete: status, documented evidence AND '
          'stated uncertainty are all required${usable ? '' : ' (model-generated / synthetic text is not evidence)'}.',
        ));
        continue;
      }
    } else if (factor.mandatory && !assessed) {
      hasUnknown = true;
      f.add(Finding(FindingLevel.unknown,
          '${factor.title}: mandatory check not assessed with evidence${usable ? '' : ' (non-evidence origin)'}.'));
      continue;
    }

    if (!assessed) {
      if (c.status != CheckStatus.notAssessed && c.evidence.trim().isEmpty) {
        hasWatch = true;
        f.add(Finding(FindingLevel.watch, '${factor.title}: marked ${c.status.label} without evidence.'));
      } else {
        f.add(Finding(FindingLevel.info, '${factor.title}: not assessed (optional).'));
      }
      continue;
    }

    switch (c.status) {
      case CheckStatus.critical:
        hasFail = true;
        f.add(Finding(FindingLevel.fail, '${factor.title}: CRITICAL — ${c.evidence}', origin: c.origin));
      case CheckStatus.concern:
        hasWatch = true;
        f.add(Finding(FindingLevel.watch, '${factor.title}: concern — ${c.evidence}', origin: c.origin));
      case CheckStatus.clear:
        f.add(Finding(FindingLevel.ok, '${factor.title}: clear — ${c.evidence}', origin: c.origin));
      case CheckStatus.notAssessed:
        break;
    }
    if (factor == StructuralFactor.redCardExposure) {
      f.add(Finding(FindingLevel.info, 'Red-card uncertainty: ${c.uncertainty}', origin: c.origin));
    }
  }

  // Engine context for the red-card check.
  final hist = [...s.homeHistory, ...s.awayHistory].where((m) => m.hasRedCardData).toList();
  final reds = hist.where((m) => m.hadRedCard).length;
  f.add(Finding(FindingLevel.info,
      'Red-card context from recorded history: $reds of ${hist.length} matches with card data had a red card.'));

  final outcome = hasFail
      ? VisaOutcome.fail
      : hasUnknown
          ? VisaOutcome.unknown
          : hasWatch
              ? VisaOutcome.watch
              : VisaOutcome.pass;
  return VisaStageResult(stage: 'C', title: 'STRUCTURAL RISK', outcome: outcome, findings: f);
}
