/// Typed failures for external integrations. The UI shows each one plainly;
/// none of them is ever papered over with placeholder data.
sealed class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ApiNotConfigured extends ApiException {
  const ApiNotConfigured() : super('No data provider API key configured — using manual analysis mode.');
}

class ApiAuthException extends ApiException {
  const ApiAuthException([super.message = 'Authentication failed — check the API key in Settings.']);
}

class ApiRateLimitException extends ApiException {
  const ApiRateLimitException([this.retryAfter])
      : super('Rate limit / quota reached at the data provider. Try again later.');
  final Duration? retryAfter;
}

class ApiHttpException extends ApiException {
  const ApiHttpException(this.status, super.message);
  final int status;
}

class ApiNetworkException extends ApiException {
  const ApiNetworkException(super.message);
}

class ApiDataException extends ApiException {
  const ApiDataException(super.message);
}
