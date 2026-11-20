import '../../domain/market.dart';
import '../../domain/match_data.dart';

/// Upcoming fixture as returned by a licensed provider.
class ProviderFixture {
  const ProviderFixture({
    required this.id,
    required this.kickoff,
    required this.homeTeam,
    required this.awayTeam,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.league,
    required this.country,
    required this.status,
    required this.fetchedAt,
    required this.provider,
  });

  final String id;
  final DateTime kickoff;
  final String homeTeam;
  final String awayTeam;
  final int homeTeamId;
  final int awayTeamId;
  final String league;
  final String country;
  final String status;
  final DateTime fetchedAt;
  final String provider;
}

/// A priced market from the provider, mapped to an internal [MarketSpec].
class ProviderOdd {
  const ProviderOdd({
    required this.spec,
    required this.odds,
    required this.bookmaker,
    required this.rawLabel,
    required this.updatedAt,
  });

  final MarketSpec spec;
  final double odds;
  final String bookmaker;
  final String rawLabel;
  final DateTime? updatedAt;
}

class ProviderInjury {
  const ProviderInjury(this.team, this.player, this.reason);
  final String team;
  final String player;
  final String reason;
}

/// Abstraction for licensed football statistics / odds providers.
abstract class FootballDataProvider {
  String get name;

  Future<List<ProviderFixture>> fixturesOn(DateTime eatDate);

  /// Most recent completed matches of a team, with goal sequence, red cards
  /// and corners where the provider supplies them. Absent fields stay null.
  Future<List<HistoricalMatch>> teamHistory(int teamId, {int last = 10});

  Future<List<ProviderOdd>> odds(ProviderFixture f);

  Future<List<ProviderInjury>> injuries(String fixtureId);
}
