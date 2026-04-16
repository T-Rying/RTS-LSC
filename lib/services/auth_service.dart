import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/environment_config.dart';
import 'log_service.dart';

/// OAuth2 client credentials token manager for BC SaaS.
/// Caches the token in memory and refreshes before expiry.
class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  static const _scope = 'https://api.businesscentral.dynamics.com/.default';
  static const _refreshSkew = Duration(seconds: 60);

  final _log = LogService.instance;

  String? _cachedToken;
  DateTime? _expiresAt;
  String? _cacheKey;

  /// Returns a valid access token, fetching a new one if missing or expired.
  Future<String> getAccessToken(EnvironmentConfig config) async {
    final key = '${config.tenant}|${config.clientId}';
    final now = DateTime.now();

    if (_cachedToken != null &&
        _cacheKey == key &&
        _expiresAt != null &&
        now.isBefore(_expiresAt!.subtract(_refreshSkew))) {
      return _cachedToken!;
    }

    return _fetchToken(config, key);
  }

  Future<String> _fetchToken(EnvironmentConfig config, String key) async {
    if (config.tenant.isEmpty || config.clientId.isEmpty || config.clientSecret.isEmpty) {
      throw StateError('Tenant ID, Client ID and Client Secret are required');
    }

    final url = Uri.parse(
      'https://login.microsoftonline.com/${Uri.encodeComponent(config.tenant)}/oauth2/v2.0/token',
    );

    _log.info('AuthService: fetching token for tenant ${config.tenant}');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'client_credentials',
        'client_id': config.clientId,
        'client_secret': config.clientSecret,
        'scope': _scope,
      },
    );

    if (response.statusCode != 200) {
      _log.error('AuthService: token request failed (${response.statusCode}): ${response.body}');
      throw HttpException(
        'Token request failed (${response.statusCode}): ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final token = json['access_token'] as String?;
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
    if (token == null || token.isEmpty) {
      throw const HttpException('Token response missing access_token');
    }

    _cachedToken = token;
    _cacheKey = key;
    _expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
    _log.info('AuthService: token acquired, expires in ${expiresIn}s');

    return token;
  }

  void invalidate() {
    _cachedToken = null;
    _cacheKey = null;
    _expiresAt = null;
  }
}

class HttpException implements Exception {
  final String message;
  const HttpException(this.message);
  @override
  String toString() => message;
}
