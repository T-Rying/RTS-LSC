import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/environment_config.dart';
import '../log_service.dart';
import 'adyen_app_link_service.dart';
import 'payment_provider.dart';
import 'payment_result.dart';

/// Phase B implementation. Runs the Adyen Android Payments app `/boarded`
/// App Link probe to discover whether the device has been paired with a
/// merchant account yet. Cached `installationId` persists across restarts
/// so the probe is cheap to re-run.
///
/// Transaction operations (purchase/refund/cancel) still return a Phase-B
/// stub error — those land in Phase C once Terminal API encryption is wired
/// up.
///
/// See the Adyen Android Payments app docs at
/// https://docs.adyen.com/point-of-sale/mobile-android/build/payments-app
class AdyenProvider implements PaymentProvider {
  final EnvironmentConfig config;
  final LogService _log = LogService.instance;
  final AdyenAppLinkService _appLinks;

  /// Keys used to persist the last-known boarding state in SharedPreferences.
  /// Scoped by merchant account + store so switching accounts doesn't show
  /// a stale installationId.
  String get _boardedKey =>
      'adyen.boarded.${config.adyenMerchantAccount}.${config.adyenStoreId}';
  String get _installationIdKey =>
      'adyen.installationId.${config.adyenMerchantAccount}.${config.adyenStoreId}';

  /// Persist the latest boardingRequestToken too — without this the
  /// "Complete boarding" button in Settings would disappear on every app
  /// restart even when the device has a valid (unused) token waiting to
  /// be redeemed via /board.
  String get _boardingRequestTokenKey =>
      'adyen.boardingRequestToken.${config.adyenMerchantAccount}.${config.adyenStoreId}';

  bool _initialized = false;
  bool _isBoarded = false;
  String _installationId = '';

  /// Most recent boardingRequestToken returned by /boarded. The boarding
  /// flow (Phase C) uses this to request a boardingToken from the server
  /// and feed it back into the /board App Link.
  String _lastBoardingRequestToken = '';

  AdyenProvider(this.config, {AdyenAppLinkService? appLinks})
      : _appLinks = appLinks ?? AdyenAppLinkService.instance;

  /// Host prefix for Adyen App Links: `https://www.adyen.com/test/` in
  /// sandbox, `https://www.adyen.com/` in production.
  String get _appLinkBase => config.adyenTestMode
      ? 'https://www.adyen.com/test'
      : 'https://www.adyen.com';

  @override
  String get name => 'Adyen';

  @override
  bool get isInitialized => _initialized;

  /// Whether the probe reported the device as boarded on its most recent run.
  bool get isBoarded => _isBoarded;

  /// Installation ID returned by Adyen after boarding — this is what the
  /// POI ID field in Terminal API requests will be set to. Empty until the
  /// device has been boarded at least once.
  String get installationId => _installationId;

  /// Last boardingRequestToken from a /boarded probe, used by Phase C to
  /// bootstrap the /board flow.
  String get lastBoardingRequestToken => _lastBoardingRequestToken;

  @override
  Future<bool> initialize() async {
    // Phase B credential validation: we need at least merchant account and
    // store ID to build the /boarded URL. apiKey / sharedKey / terminalId
    // aren't used in Phase B — those kick in with Phase C's /board + /nexo.
    final missing = <String>[
      if (config.adyenMerchantAccount.isEmpty) 'merchantAccount',
      if (config.adyenStoreId.isEmpty) 'storeId',
    ];
    if (missing.isNotEmpty) {
      _log.warn('Adyen: missing required config for /boarded probe: '
          '${missing.join(", ")}');
      _initialized = false;
      return false;
    }

    // Restore cached boarding state — lets the UI show "Boarded" immediately
    // on startup without waiting for a network round-trip.
    await _loadCachedBoardingState();

    _log.info('Adyen: initialized (test=${config.adyenTestMode}, '
        'merchant=${config.adyenMerchantAccount}, '
        'store=${config.adyenStoreId}, '
        'cachedBoarded=$_isBoarded, '
        'cachedInstallationId=${_installationId.isEmpty ? "none" : _installationId})');
    _initialized = true;
    return true;
  }

  Future<void> _loadCachedBoardingState() async {
    final prefs = await SharedPreferences.getInstance();
    _isBoarded = prefs.getBool(_boardedKey) ?? false;
    _installationId = prefs.getString(_installationIdKey) ?? '';
    _lastBoardingRequestToken =
        prefs.getString(_boardingRequestTokenKey) ?? '';
  }

  Future<void> _saveCachedBoardingState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_boardedKey, _isBoarded);
    await prefs.setString(_installationIdKey, _installationId);
    await prefs.setString(
        _boardingRequestTokenKey, _lastBoardingRequestToken);
  }

  /// Run the `/boarded` App Link probe. Launches the Adyen Payments app,
  /// which returns via our deep-link scheme with `boarded`, `installationId`,
  /// and `boardingRequestToken` query params.
  ///
  /// Updates [isBoarded], [installationId], [lastBoardingRequestToken] and
  /// persists the new values. Returns true iff the device reports as boarded.
  ///
  /// Throws [TimeoutException] if the Adyen app doesn't return within 30s.
  /// Throws [StateError] if the Adyen app isn't installed or no provider
  /// credentials are set.
  Future<bool> checkBoardingStatus() async {
    if (!_initialized) {
      final ok = await initialize();
      if (!ok) {
        throw StateError(
            'Adyen provider not initialized — configure merchant account '
            'and store ID in Settings first.');
      }
    }

    final url = Uri.parse('$_appLinkBase/boarded').replace(queryParameters: {
      'returnUrl': AdyenAppLinkService.returnUrl,
    });
    _log.info('Adyen: launching /boarded probe at $url');

    final returnUri = await _appLinks.launchAndAwaitReturn(url);
    _log.info('Adyen: /boarded returned ${_summarizeReturn(returnUri)}');

    final params = returnUri.queryParameters;
    _isBoarded = params['boarded']?.toLowerCase() == 'true';
    _installationId = params['installationId'] ?? _installationId;
    _lastBoardingRequestToken = params['boardingRequestToken'] ?? '';
    await _saveCachedBoardingState();

    return _isBoarded;
  }

  /// Management API base URL used to exchange a `boardingRequestToken`
  /// for a `boardingToken`. Test or live picked from adyenTestMode.
  String get _managementApiBase => config.adyenTestMode
      ? 'https://management-test.adyen.com/v3'
      : 'https://management-live.adyen.com/v3';

  /// Finish the onboarding round-trip. Three-step flow per the Adyen
  /// docs at `point-of-sale/mobile-android/build/payments-app`:
  ///
  ///   1. We already have a `boardingRequestToken` from `/boarded`.
  ///   2. POST it to the Management API
  ///      (`/v3/merchants/{id}/stores/{id}/generatePaymentsAppBoardingToken`)
  ///      authenticated with `X-API-Key`, receive a `boardingToken`
  ///      (Base64URL, valid one hour).
  ///   3. Launch `/board?boardingToken=…&returnUrl=…` and wait for the
  ///      Adyen Payments app to call back with `boarded=true` and the
  ///      real `installationId`.
  ///
  /// Adyen's docs describe step 2 as a merchant-backend operation —
  /// RTS-LSC has no backend today, so the mobile app does the exchange
  /// itself using the API key stored in EnvironmentConfig. That's why
  /// the API key must be filled in for pairing to work.
  ///
  /// Throws [StateError] if the API key or boardingRequestToken is
  /// missing, or if the Management API rejects the exchange. Throws
  /// [TimeoutException] if the Adyen app doesn't return within 30s.
  Future<bool> completeBoarding() async {
    if (!_initialized) {
      final ok = await initialize();
      if (!ok) {
        throw StateError(
            'Adyen provider not initialized — configure merchant account '
            'and store ID in Settings first.');
      }
    }
    if (_lastBoardingRequestToken.isEmpty) {
      throw StateError(
          'No boardingRequestToken cached — run "Check boarding status" '
          'first to obtain one.');
    }
    if (config.adyenApiKey.isEmpty) {
      throw StateError(
          'Adyen API key is required to exchange the boardingRequestToken '
          'for a boardingToken. Fill in the API key in Settings → Adyen.');
    }

    final boardingToken = await _exchangeBoardingToken();

    final url = Uri.parse('$_appLinkBase/board').replace(queryParameters: {
      'returnUrl': AdyenAppLinkService.returnUrl,
      'boardingToken': boardingToken,
    });
    _log.info('Adyen: launching /board with exchanged boardingToken');

    final returnUri = await _appLinks.launchAndAwaitReturn(url);
    _log.info('Adyen: /board returned ${_summarizeReturn(returnUri)}');

    final params = returnUri.queryParameters;
    _isBoarded = params['boarded']?.toLowerCase() == 'true';
    _installationId = params['installationId'] ?? _installationId;
    // /board doesn't re-issue a boardingRequestToken — the old one is
    // single-use after the Management API exchange. On failure the user
    // should re-run /boarded to get a fresh one.
    _lastBoardingRequestToken = '';
    await _saveCachedBoardingState();
    if (!_isBoarded) {
      final err = params['error'];
      throw StateError(err != null && err.isNotEmpty
          ? 'Adyen /board returned error: $err'
          : 'Adyen /board returned boarded=false — try Check again.');
    }
    return _isBoarded;
  }

  /// POSTs the cached `boardingRequestToken` to the Management API and
  /// returns the short-lived `boardingToken`. Scoped to the store when
  /// `adyenStoreId` is set (the Adyen Payments app expects store-level
  /// pairing for POS installs).
  Future<String> _exchangeBoardingToken() async {
    final merchantId = Uri.encodeComponent(config.adyenMerchantAccount);
    final storeId = config.adyenStoreId;
    final path = storeId.isEmpty
        ? '/merchants/$merchantId/generatePaymentsAppBoardingToken'
        : '/merchants/$merchantId/stores/${Uri.encodeComponent(storeId)}'
            '/generatePaymentsAppBoardingToken';
    final url = Uri.parse('$_managementApiBase$path');
    _log.info('Adyen: POST $url (exchange boardingRequestToken)');

    final response = await http.post(
      url,
      headers: {
        'X-API-Key': config.adyenApiKey,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'boardingRequestToken': _lastBoardingRequestToken}),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      _log.error('Adyen: boardingToken exchange failed '
          '(${response.statusCode}): ${response.body}');
      throw StateError(
          'Management API rejected the boardingRequestToken '
          '(${response.statusCode}): ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Management API returned non-JSON response');
    }
    final token = decoded['boardingToken'] as String?;
    if (token == null || token.isEmpty) {
      throw StateError(
          'Management API response missing boardingToken: ${response.body}');
    }
    final installation = decoded['installationId'] as String?;
    if (installation != null && installation.isNotEmpty) {
      _installationId = installation;
    }
    _log.info('Adyen: received boardingToken (1h TTL) from Management API');
    return token;
  }

  String _summarizeReturn(Uri uri) {
    final q = uri.queryParameters;
    final token = q['boardingRequestToken'];
    final tokenSummary = token == null || token.isEmpty
        ? 'none'
        : '${token.substring(0, token.length.clamp(0, 4))}…(${token.length}c)';
    return 'boarded=${q['boarded']} '
        'installationId=${q['installationId'] ?? "none"} '
        'boardingRequestToken=$tokenSummary';
  }

  @override
  Future<PaymentResult> purchase({
    required int amount,
    required String currency,
    String? posReferenceNumber,
  }) async {
    _log.warn('Adyen.purchase called — not implemented yet (Phase B stub, '
        'waiting for Phase C). amount=$amount $currency ref=$posReferenceNumber');
    if (!_isBoarded) {
      return const PaymentResult.declined(
        errorCode: 'ADYEN_NOT_BOARDED',
        errorMessage: 'Adyen device is not boarded yet. '
            'Run "Check boarding status" in Settings first.',
      );
    }
    return const PaymentResult.declined(
      errorCode: 'ADYEN_NOT_IMPLEMENTED',
      errorMessage: 'Adyen purchase flow is not wired yet (Phase C pending). '
          'Switch to SoftPay in Settings for now.',
    );
  }

  @override
  Future<PaymentResult> refund({
    required int amount,
    required String currency,
    String? posReferenceNumber,
  }) async =>
      const PaymentResult.declined(
        errorCode: 'ADYEN_NOT_IMPLEMENTED',
        errorMessage: 'Adyen refund flow is not wired yet (Phase C pending).',
      );

  @override
  Future<PaymentResult> cancel({String? providerTransactionId}) async =>
      const PaymentResult.declined(
        errorCode: 'ADYEN_NOT_IMPLEMENTED',
        errorMessage: 'Adyen cancel flow is not wired yet (Phase C pending).',
      );

  @override
  Future<void> dispose() async {
    _initialized = false;
  }
}
