import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/audit.dart';
import '../../domain/selection.dart';
import '../../engine/markets/markets.dart';
import '../api/api_errors.dart';

/// Optional AI explanation of a finished audit (Claude Messages API).
///
/// The returned text is MODEL-GENERATED analysis. It is displayed with that
/// label, never stored as evidence and never fed back into the deterministic
/// KING'S VISA engine, which alone decides approval.
class AiExplainer {
  AiExplainer({
    required this.apiKey,
    this.model = 'claude-opus-5-5',
    http.Client? client,
    this.endpoint = 'https://api.anthropic.com/v1/messages',
  }) : _client = client ?? http.Client();

  final String apiKey;
  final String model;
  final String endpoint;
  final http.Client _client;

  static const _system =
      'You are a risk analyst reviewing a deterministic football-market audit called KING\'S VISA. '
      'Explain the audit in plain language for the user: the main failure pathways, which evidence is '
      'missing, and what the user should verify next. Use only the facts in the audit JSON. Do not invent '
      'statistics, fixtures, injuries, line-ups or odds, do not state win probabilities, and do not '
      'contradict or override the verdict. Keep it under 250 words.';

  Future<String> explain(Selection s, AuditReport r) async {
    if (apiKey.trim().isEmpty) throw const ApiNotConfigured();
    final market = MarketRegistry.of(s.market.type).describe(s.market, s.homeTeam, s.awayTeam);
    final payload = {
      'match': s.matchLabel,
      'league': s.league,
      'market': market,
      'odds': s.odds,
      'audit': r.toJson(),
    };
    http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse(endpoint),
            headers: {
              'x-api-key': apiKey,
              'anthropic-version': '2026-10-21',
              'anthropic-beta': 'server-side-fallback-2026-07-01',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'max_tokens': 4000,
              'output_config': {'effort': 'low'},
              'fallbacks': 'default',
              'system': _system,
              'messages': [
                {'role': 'user', 'content': 'Audit JSON:\n${jsonEncode(payload)}'},
              ],
            }),
          )
          .timeout(const Duration(seconds: 90));
    } on TimeoutException {
      throw const ApiNetworkException('AI provider timed out.');
    } on http.ClientException catch (e) {
      throw ApiNetworkException('AI network error: ${e.message}');
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const ApiAuthException('AI provider rejected the API key.');
    }
    if (res.statusCode == 429) throw const ApiRateLimitException();
    if (res.statusCode >= 400) throw ApiHttpException(res.statusCode, 'AI provider HTTP ${res.statusCode}: ${res.body}');
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['stop_reason'] == 'refusal') {
      throw const ApiDataException('The AI provider declined to answer this request.');
    }
    final text = ((body['content'] as List?) ?? [])
        .whereType<Map>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String)
        .join('\n')
        .trim();
    if (text.isEmpty) throw const ApiDataException('AI provider returned no text.');
    return text;
  }
}
