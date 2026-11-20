import 'dart:convert';

import 'enums.dart';

/// A single goal in a historical match, used for sequence-dependent markets.
class GoalEvent {
  const GoalEvent({required this.minute, required this.side});

  /// Match minute (stoppage time may be expressed as e.g. 90 or 93).
  final int minute;

  /// Which side of *that historical match* scored.
  final Side side;

  Map<String, dynamic> toJson() => {'m': minute, 's': side.name};

  factory GoalEvent.fromJson(Map<String, dynamic> j) =>
      GoalEvent(minute: (j['m'] as num).toInt(), side: Side.parse(j['s'] as String?));
}

/// A completed historical match used as evidence for VISA B / VISA D.
///
/// Every nullable field means "not available". The engine never fills a
/// missing field with an assumed value: anything a market needs that is
/// absent turns that observation into UNKNOWN.
class HistoricalMatch {
  HistoricalMatch({
    this.id,
    required this.date,
    required this.homeTeam,
    required this.awayTeam,
    this.competition = '',
    this.ftHome,
    this.ftAway,
    this.htHome,
    this.htAway,
    this.goalSequence,
    this.cornersHome,
    this.cornersAway,
    this.redCardsHome,
    this.redCardsAway,
    this.comparable = true,
    this.source = '',
    this.origin = DataOrigin.userEntered,
    this.marketResultOverride,
  });

  final int? id;
  final DateTime date;
  final String homeTeam;
  final String awayTeam;
  final String competition;
  final int? ftHome;
  final int? ftAway;
  final int? htHome;
  final int? htAway;

  /// Chronological goal sequence; `null` means the order is unknown.
  final List<GoalEvent>? goalSequence;
  final int? cornersHome;
  final int? cornersAway;
  final int? redCardsHome;
  final int? redCardsAway;

  /// Whether the opponent / context is comparable to the audited fixture.
  /// Non-comparable observations are excluded from the failure rate and
  /// reported separately.
  final bool comparable;
  final String source;
  final DataOrigin origin;

  /// For user-defined (custom) markets only: user-recorded settlement of this
  /// market in this match: 'win', 'lose' or 'unknown'.
  final String? marketResultOverride;

  bool get hasFullTime => ftHome != null && ftAway != null;
  bool get hasHalfTime => htHome != null && htAway != null;
  bool get hasCorners => cornersHome != null && cornersAway != null;
  bool get hasRedCardData => redCardsHome != null && redCardsAway != null;
  bool get hadRedCard => (redCardsHome ?? 0) + (redCardsAway ?? 0) > 0;
  int? get totalGoals => hasFullTime ? ftHome! + ftAway! : null;

  /// A goal sequence is only usable if it is consistent with the final score.
  bool get hasValidSequence {
    final seq = goalSequence;
    if (seq == null || !hasFullTime) return false;
    final h = seq.where((g) => g.side == Side.home).length;
    final a = seq.where((g) => g.side == Side.away).length;
    return h == ftHome && a == ftAway;
  }

  Side? sideOf(String team) {
    final t = team.trim().toLowerCase();
    if (homeTeam.trim().toLowerCase() == t) return Side.home;
    if (awayTeam.trim().toLowerCase() == t) return Side.away;
    return null;
  }

  int? goalsFor(Side s) => s == Side.home ? ftHome : ftAway;
  int? htGoalsFor(Side s) => s == Side.home ? htHome : htAway;
  int? cornersFor(Side s) => s == Side.home ? cornersHome : cornersAway;

  String get scoreLabel => hasFullTime ? '$ftHome-$ftAway' : '?-?';

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'date': date.toUtc().millisecondsSinceEpoch,
        'home_team': homeTeam,
        'away_team': awayTeam,
        'competition': competition,
        'ft_home': ftHome,
        'ft_away': ftAway,
        'ht_home': htHome,
        'ht_away': htAway,
        'goal_seq': goalSequence == null
            ? null
            : jsonEncode(goalSequence!.map((g) => g.toJson()).toList()),
        'corners_home': cornersHome,
        'corners_away': cornersAway,
        'reds_home': redCardsHome,
        'reds_away': redCardsAway,
        'comparable': comparable ? 1 : 0,
        'source': source,
        'origin': origin.name,
        'market_override': marketResultOverride,
      };

  factory HistoricalMatch.fromMap(Map<String, dynamic> m) {
    final seqRaw = m['goal_seq'];
    return HistoricalMatch(
      id: m['id'] as int?,
      date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int, isUtc: true),
      homeTeam: m['home_team'] as String,
      awayTeam: m['away_team'] as String,
      competition: (m['competition'] as String?) ?? '',
      ftHome: m['ft_home'] as int?,
      ftAway: m['ft_away'] as int?,
      htHome: m['ht_home'] as int?,
      htAway: m['ht_away'] as int?,
      goalSequence: seqRaw == null
          ? null
          : (jsonDecode(seqRaw as String) as List)
              .map((e) => GoalEvent.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList(),
      cornersHome: m['corners_home'] as int?,
      cornersAway: m['corners_away'] as int?,
      redCardsHome: m['reds_home'] as int?,
      redCardsAway: m['reds_away'] as int?,
      comparable: (m['comparable'] as int? ?? 1) == 1,
      source: (m['source'] as String?) ?? '',
      origin: DataOrigin.parse(m['origin'] as String?),
      marketResultOverride: m['market_override'] as String?,
    );
  }

  HistoricalMatch copyWith({int? id, bool? comparable}) => HistoricalMatch(
        id: id ?? this.id,
        date: date,
        homeTeam: homeTeam,
        awayTeam: awayTeam,
        competition: competition,
        ftHome: ftHome,
        ftAway: ftAway,
        htHome: htHome,
        htAway: htAway,
        goalSequence: goalSequence,
        cornersHome: cornersHome,
        cornersAway: cornersAway,
        redCardsHome: redCardsHome,
        redCardsAway: redCardsAway,
        comparable: comparable ?? this.comparable,
        source: source,
        origin: origin,
        marketResultOverride: marketResultOverride,
      );

  /// Parses a compact goal sequence string such as `"12H,40A,77H"`.
  /// Returns `null` for an empty string (meaning unknown order).
  static List<GoalEvent>? parseSequence(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    if (s == '-' || s.toLowerCase() == 'none') return const [];
    final out = <GoalEvent>[];
    for (final part in s.split(RegExp(r'[,;\s]+'))) {
      if (part.isEmpty) continue;
      final m = RegExp(r"^(\d{1,3})'?([HhAa])$").firstMatch(part);
      if (m == null) {
        throw FormatException('Invalid goal token "$part". Use e.g. 23H or 67A.');
      }
      out.add(GoalEvent(
        minute: int.parse(m.group(1)!),
        side: m.group(2)!.toUpperCase() == 'H' ? Side.home : Side.away,
      ));
    }
    // Order is taken exactly as entered (goals in the same minute keep their
    // entered order). Out-of-order minutes are rejected rather than re-sorted.
    for (var i = 1; i < out.length; i++) {
      if (out[i].minute < out[i - 1].minute) {
        throw const FormatException('Goal sequence must be in chronological order.');
      }
    }
    return out;
  }

  static String formatSequence(List<GoalEvent>? seq) {
    if (seq == null) return '';
    if (seq.isEmpty) return '-';
    return seq.map((g) => '${g.minute}${g.side == Side.home ? 'H' : 'A'}').join(',');
  }
}
