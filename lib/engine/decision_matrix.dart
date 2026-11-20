import '../domain/enums.dart';

/// The mandatory KING'S VISA decision matrix.
///
/// * Any FAIL → REJECTED.
/// * Any UNKNOWN (no FAIL) → INCOMPLETE.
/// * Any WATCH (no FAIL / UNKNOWN) → WATCH.
/// * Four PASS → APPROVED.
///
/// This function takes *only* stage outcomes. No score, threshold or setting
/// can reach it, so a high numerical score can never override a failed gate.
FinalVerdict decide(VisaOutcome a, VisaOutcome b, VisaOutcome c, VisaOutcome d) {
  final all = [a, b, c, d];
  if (all.contains(VisaOutcome.fail)) return FinalVerdict.rejected;
  if (all.contains(VisaOutcome.unknown)) return FinalVerdict.incomplete;
  if (all.contains(VisaOutcome.watch)) return FinalVerdict.watch;
  return FinalVerdict.approved;
}

/// Combines several check results into a single stage outcome using the same
/// precedence (FAIL > UNKNOWN > WATCH > PASS).
VisaOutcome combineOutcomes(Iterable<VisaOutcome> outcomes) {
  final s = outcomes.toSet();
  if (s.contains(VisaOutcome.fail)) return VisaOutcome.fail;
  if (s.contains(VisaOutcome.unknown)) return VisaOutcome.unknown;
  if (s.contains(VisaOutcome.watch)) return VisaOutcome.watch;
  return VisaOutcome.pass;
}
