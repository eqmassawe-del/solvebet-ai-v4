/// Core enumerations shared by the KING'S VISA engine, persistence and UI.
library;

/// Outcome of a single VISA stage.
///
/// VISA A only ever produces [pass], [fail] or [unknown]; the other stages may
/// also return [watch].
enum VisaOutcome {
  pass,
  watch,
  fail,
  unknown;

  String get label => name.toUpperCase();

  static VisaOutcome parse(String? s) => VisaOutcome.values.firstWhere(
        (e) => e.name == s,
        orElse: () => VisaOutcome.unknown,
      );
}

/// Final KING'S VISA verdict produced by the decision matrix.
enum FinalVerdict {
  approved,
  watch,
  rejected,
  incomplete;

  String get label => name.toUpperCase();

  static FinalVerdict? tryParse(String? s) {
    for (final v in FinalVerdict.values) {
      if (v.name == s) return v;
    }
    return null;
  }
}

/// Provenance of any piece of data held by the app. The UI always shows this
/// so that a user can tell verified facts from their own entries, AI text or
/// test fixtures.
enum DataOrigin {
  /// Retrieved from a configured licensed data provider.
  verifiedApi,

  /// Typed or imported by the user.
  userEntered,

  /// Text produced by an optional language model. Never counted as evidence.
  modelGenerated,

  /// Computed by the deterministic engine from other records.
  engineDerived,

  /// Explicitly labelled synthetic data used only by automated tests.
  synthetic;

  String get label => switch (this) {
        DataOrigin.verifiedApi => 'VERIFIED (API)',
        DataOrigin.userEntered => 'USER-ENTERED',
        DataOrigin.modelGenerated => 'MODEL-GENERATED',
        DataOrigin.engineDerived => 'ENGINE-DERIVED',
        DataOrigin.synthetic => 'SYNTHETIC TEST DATA',
      };

  static DataOrigin parse(String? s) => DataOrigin.values.firstWhere(
        (e) => e.name == s,
        orElse: () => DataOrigin.userEntered,
      );
}

/// Side of a fixture.
enum Side {
  home,
  away;

  Side get other => this == Side.home ? Side.away : Side.home;

  static Side parse(String? s) => s == 'away' ? Side.away : Side.home;
}
