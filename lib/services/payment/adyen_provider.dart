import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/environment_config.dart';
import '../log_service.dart';
import 'adyen_app_link_service.dart';
import 'adyen_nexo.dart';
import 'adyen_nexo_crypto.dart';
import 'payment_provider.dart';
import 'payment_result.dart';

/// Adyen Payments-app integration across all three phases:
///
/// * Phase A: credential model + provider abstraction.
/// * Phase B: `/boarded` probe + `/board` completion via the Adyen
///   Management API exchange. Yields the installationId we use as
///   POIID in Terminal API messages.
/// * Phase C: NEXO Terminal API over the `/nexo` App Link. Inner JSON
///   is AES-256-CBC-encrypted and HMAC-SHA256-signed with keys derived
///   from `adyenSharedKey` (the shared passphrase set up in Adyen CA
///   → Point-of-sale → Shared secret).
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

  /// Payments App API base URL used to exchange a
  /// `boardingRequestToken` for a `boardingToken`. Shares the host
  /// with the general Management API (`management-*.adyen.com`) but
  /// versioned separately at `/v1` — not `/v3`. Test or live picked
  /// from `adyenTestMode`.
  String get _paymentsAppApiBase => config.adyenTestMode
      ? 'https://management-test.adyen.com/v1'
      : 'https://management-live.adyen.com/v1';

  /// Finish the onboarding round-trip. Three-step flow per the Adyen
  /// docs at `point-of-sale/mobile-android/build/payments-app`:
  ///
  ///   1. We already have a `boardingRequestToken` from `/boarded`.
  ///   2. POST it to the Adyen Payments App API
  ///      (`/v1/merchants/{id}/stores/{id}/generatePaymentsAppBoardingToken`)
  ///      authenticated with `X-API-Key`, receive a `boardingToken`
  ///      (Base64URL, valid one hour). Note: this is a separate API
  ///      surface from the general Management API (v3) — same host,
  ///      different version prefix.
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

    final rawToken = await _exchangeBoardingToken();
    // The Payments App API returns `boardingToken` as a JWT string
    // (e.g. `eyJhbGciOi…`). The /board App Link expects that whole
    // string to be Base64URL-encoded a second time — the docs show
    // an example URL whose boardingToken starts with `ZXlK…`, i.e.
    // the Base64URL of `eyJ…`. Encoding the UTF-8 bytes of the JWT
    // and stripping padding matches that shape. Error 02_005 is what
    // you get if you pass the raw JWT through instead.
    final boardingToken =
        base64Url.encode(utf8.encode(rawToken)).replaceAll('=', '');
    _logTokenShape('raw', rawToken);
    _logTokenShape('wrapped', boardingToken);

    // Build the /board URL by string concatenation to avoid any
    // re-encoding of an already-Base64URL token. Dart's Uri.replace
    // with queryParameters runs encodeQueryComponent on the values —
    // harmless for Base64URL chars (A-Z, a-z, 0-9, -, _) but we want
    // the URL the Adyen app sees to be exactly the token we computed,
    // verbatim.
    final encodedReturnUrl = Uri.encodeQueryComponent(
        AdyenAppLinkService.returnUrl);
    final url = Uri.parse(
        '$_appLinkBase/board?boardingToken=$boardingToken'
        '&returnUrl=$encodedReturnUrl');
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

  /// Logs metadata about a token (length, dot count, char class
  /// counts, first/last few chars) without dumping the whole value.
  /// Helps debug 02_005 "boarding token error" without leaking the
  /// secret into logs.
  void _logTokenShape(String label, String token) {
    int dots = 0;
    int stdB64Only = 0; // + / =
    int b64UrlOnly = 0; // - _
    for (var i = 0; i < token.length; i++) {
      final c = token[i];
      if (c == '.') dots++;
      if (c == '+' || c == '/' || c == '=') stdB64Only++;
      if (c == '-' || c == '_') b64UrlOnly++;
    }
    final head = token.length > 6 ? token.substring(0, 6) : token;
    final tail = token.length > 6 ? token.substring(token.length - 6) : '';
    _log.info('Adyen token[$label]: len=${token.length} dots=$dots '
        'stdB64-only=$stdB64Only b64url-only=$b64UrlOnly '
        'head=$head tail=$tail');
  }

  /// POSTs the cached `boardingRequestToken` to the Management API and
  /// returns the short-lived `boardingToken`.
  ///
  /// When `adyenStoreId` is set we first try the store-scoped endpoint
  /// `/merchants/{id}/stores/{storeId}/…`. That path wants Adyen's
  /// **internal** store reference (format like `ST322LJ22UR…`) — not
  /// the merchant-defined store code. If the user typed a store code
  /// it 404s, so we transparently fall back to the merchant-level
  /// endpoint `/merchants/{id}/…`, which is the right shape for
  /// merchant-wide Payments app boarding.
  Future<String> _exchangeBoardingToken() async {
    final merchantId = Uri.encodeComponent(config.adyenMerchantAccount);
    final storeId = config.adyenStoreId;
    final merchantPath =
        '/merchants/$merchantId/generatePaymentsAppBoardingToken';

    if (storeId.isNotEmpty) {
      final storePath = '/merchants/$merchantId/stores/'
          '${Uri.encodeComponent(storeId)}/generatePaymentsAppBoardingToken';
      final storeResult = await _postExchange(storePath);
      if (storeResult != null) return storeResult;
      _log.warn('Adyen: store-level exchange returned 404 — falling back '
          'to merchant-level. The Management API expects Adyen\'s internal '
          'store reference (ST…) here, not the merchant-defined store code.');
    }
    final merchantResult = await _postExchange(merchantPath);
    if (merchantResult != null) return merchantResult;
    throw StateError(
        'Management API rejected the boardingRequestToken at both '
        'store-level and merchant-level paths. See logs for the HTTP '
        'response body.');
  }

  /// Single POST attempt at [path]. Returns the boardingToken on
  /// success, or null if the endpoint returned 404 (letting the caller
  /// try a fallback path). Throws [StateError] on any other failure.
  Future<String?> _postExchange(String path) async {
    final url = Uri.parse('$_paymentsAppApiBase$path');
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
    if (response.statusCode == 404) {
      _log.warn('Adyen: boardingToken exchange 404 at $path');
      return null;
    }
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
    _log.info('Adyen: received boardingToken (1h TTL) from $path');
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
    final precheck = _requirePhaseCReady('purchase');
    if (precheck != null) return precheck;

    final nexo = _buildNexo();
    final serviceId = _newServiceId();
    final saleTransactionId = posReferenceNumber ?? serviceId;
    final transactionId = 'TX-$serviceId';
    final inner = <String, dynamic>{
      'PaymentRequest': <String, dynamic>{
        'SaleData': <String, dynamic>{
          'SaleTransactionID': <String, dynamic>{
            'TransactionID': transactionId,
            'TimeStamp': DateTime.now().toUtc().toIso8601String(),
          },
          'SaleReferenceID': saleTransactionId,
        },
        // PaymentData.PaymentType disambiguates the transaction flavour
        // for the POI. "Normal" is the vanilla card-present sale; the
        // Adyen Payments App returns UnavailableService without this
        // because it has no default service wired.
        'PaymentData': <String, dynamic>{
          'PaymentType': 'Normal',
        },
        'PaymentTransaction': <String, dynamic>{
          'AmountsReq': <String, dynamic>{
            'Currency': currency,
            'RequestedAmount': _minorToDecimal(amount, currency),
          },
        },
      },
    };

    try {
      final response = await nexo.roundTrip(
        messageCategory: 'Payment',
        serviceId: serviceId,
        innerRequest: inner,
      );
      return _mapPaymentResponse(
        response,
        requestedAmount: amount,
        currency: currency,
        serviceId: serviceId,
      );
    } on TimeoutException {
      _log.error('Adyen NEXO: purchase timed out ref=$posReferenceNumber');
      return PaymentResult.declined(
        errorCode: 'ADYEN_NEXO_TIMEOUT',
        errorMessage:
            'Adyen terminal did not respond in time. State of the payment '
            'is unknown — check the Adyen Customer Area before retrying.',
        transaction: PaymentTransaction(providerTransactionId: serviceId),
      );
    } catch (e) {
      _log.error('Adyen NEXO: purchase failed: $e');
      return PaymentResult.declined(
        errorCode: 'ADYEN_NEXO_ERROR',
        errorMessage: e.toString(),
        transaction: PaymentTransaction(providerTransactionId: serviceId),
      );
    }
  }

  @override
  Future<PaymentResult> refund({
    required int amount,
    required String currency,
    String? posReferenceNumber,
  }) async =>
      const PaymentResult.declined(
        errorCode: 'ADYEN_NOT_IMPLEMENTED',
        errorMessage: 'Adyen refund flow is not wired yet — the /nexo '
            'round-trip is in place but refund mapping is TODO.',
      );

  @override
  Future<PaymentResult> cancel({String? providerTransactionId}) async =>
      const PaymentResult.declined(
        errorCode: 'ADYEN_NOT_IMPLEMENTED',
        errorMessage: 'Adyen cancel flow is not wired yet — the /nexo '
            'round-trip is in place but reversal mapping is TODO.',
      );

  /// Build a fresh NEXO channel wrapper for the current config.
  /// Kept per-call (rather than cached) because the shared passphrase
  /// or installationId can change at any time via Settings — and
  /// PBKDF2 at 4000 rounds is cheap enough (~10ms).
  AdyenNexo _buildNexo() => AdyenNexo(
        crypto: AdyenNexoCrypto.fromPassphrase(config.adyenSharedKey),
        appLinks: _appLinks,
        appLinkBase: _appLinkBase,
        keyIdentifier: config.adyenKeyIdentifier,
        keyVersion: config.adyenKeyVersion,
        saleId: config.adyenSaleId,
        poiId: _installationId,
      );

  /// Validates that we have everything needed to encrypt + send a NEXO
  /// request. Returns a declined [PaymentResult] on failure, or null
  /// when ready to proceed.
  PaymentResult? _requirePhaseCReady(String op) {
    if (!_initialized) {
      return PaymentResult.declined(
        errorCode: 'ADYEN_NOT_INITIALIZED',
        errorMessage: 'Adyen provider is not initialized — $op aborted.',
      );
    }
    if (!_isBoarded || _installationId.isEmpty) {
      return const PaymentResult.declined(
        errorCode: 'ADYEN_NOT_BOARDED',
        errorMessage: 'Adyen device is not boarded yet. '
            'Run "Check boarding status" and "Pair" in Settings first.',
      );
    }
    final missing = <String>[
      if (config.adyenSharedKey.isEmpty) 'sharedKey (passphrase)',
      if (config.adyenKeyIdentifier.isEmpty) 'keyIdentifier',
      if (config.adyenKeyVersion <= 0) 'keyVersion',
      if (config.adyenSaleId.isEmpty) 'saleId',
    ];
    if (missing.isNotEmpty) {
      return PaymentResult.declined(
        errorCode: 'ADYEN_CONFIG_INCOMPLETE',
        errorMessage:
            'Adyen Phase C config incomplete — missing: ${missing.join(", ")}. '
            'Fill in the Adyen credentials in Settings.',
      );
    }
    return null;
  }

  /// 10-digit numeric ServiceID — the NEXO protocol's per-request
  /// identifier. Adyen echoes it back in the SaleToPOIResponse so we
  /// can correlate; our round-trip helper rejects mismatched values.
  String _newServiceId() {
    final r = Random.secure();
    final buf = StringBuffer();
    for (var i = 0; i < 10; i++) {
      buf.write(r.nextInt(10));
    }
    return buf.toString();
  }

  /// Convert minor-unit integers (3400 DKK cents) into the decimal
  /// string NEXO expects in RequestedAmount. NEXO treats this as a
  /// JSON number, but the JSON serializer will render 34 and 34.00
  /// differently — we pass a `num` with the right exponent so Dart's
  /// serializer keeps the fractional part when needed.
  num _minorToDecimal(int minor, String currency) {
    // Zero-decimal currencies (JPY, KRW, …) are rare but supported.
    final zeroDecimal = {'JPY', 'KRW', 'CLP', 'VND'};
    if (zeroDecimal.contains(currency.toUpperCase())) return minor;
    return minor / 100.0;
  }

  /// Map a decrypted NEXO `PaymentResponse` onto our provider-neutral
  /// [PaymentResult]. Extracts the ApprovedAmount, payment brand,
  /// masked PAN and acquirer auth code when present; on decline pulls
  /// the Response.ErrorCondition + AdditionalResponse text so the
  /// cashier UI can show something actionable.
  PaymentResult _mapPaymentResponse(
    Map<String, dynamic> response, {
    required int requestedAmount,
    required String currency,
    required String serviceId,
  }) {
    final pr = response['PaymentResponse'] as Map<String, dynamic>?;
    if (pr == null) {
      return PaymentResult.declined(
        errorCode: 'ADYEN_BAD_RESPONSE',
        errorMessage: 'NEXO response missing PaymentResponse: '
            '${response.keys.join(",")}',
        transaction: PaymentTransaction(providerTransactionId: serviceId),
      );
    }
    final resp = pr['Response'] as Map<String, dynamic>? ?? const {};
    final result = (resp['Result'] as String? ?? '').toLowerCase();
    final errorCondition = resp['ErrorCondition'] as String?;
    final additional = resp['AdditionalResponse'] as String?;

    // Log a structured summary of the Adyen response so we can tell
    // "declined because X" apart from "declined because Y" without
    // decrypting after the fact. AdditionalResponse is a URL-encoded
    // query string like `message=&refusalReason=…&traceparent=…` —
    // most diagnostic info lives there.
    final keys = pr.keys.toList();
    _log.info('Adyen NEXO response: result=$result '
        'errorCondition=${errorCondition ?? "none"} '
        'paymentResponseKeys=${keys.join(",")}');
    if (additional != null && additional.isNotEmpty) {
      _log.info('Adyen NEXO AdditionalResponse: $additional');
    }
    // POIData carries the terminal's self-description — especially
    // useful when errorCondition is UnavailableService, because it
    // shows what the POI thinks it CAN do. Dump it verbatim (no PII).
    final poiData = pr['POIData'];
    if (poiData != null) {
      _log.info('Adyen NEXO POIData: ${jsonEncode(poiData)}');
    }

    final paymentResult = pr['PaymentResult'] as Map<String, dynamic>?;
    final amountsResp =
        paymentResult?['AmountsResp'] as Map<String, dynamic>?;
    final approved = amountsResp?['AuthorizedAmount'];
    final approvedMinor = approved is num
        ? (approved * 100).round()
        : requestedAmount;

    final instrument = paymentResult?['PaymentInstrumentData']
        as Map<String, dynamic>?;
    final cardData = instrument?['CardData'] as Map<String, dynamic>?;
    final maskedPan = cardData?['MaskedPan'] as String?;
    final brand = cardData?['PaymentBrand'] as String?;

    final acquirerData = paymentResult?['PaymentAcquirerData']
        as Map<String, dynamic>?;
    final authCode = (acquirerData?['AcquirerTransactionID']
            as Map<String, dynamic>?)?['TransactionID'] as String? ??
        acquirerData?['ApprovalCode'] as String?;

    final txn = PaymentTransaction(
      providerTransactionId: serviceId,
      authorizationCode: authCode,
      cardScheme: brand,
      cardToken: maskedPan,
      state: result,
      amountMinor: approvedMinor,
      currencyCode: currency,
    );

    if (result == 'success') return PaymentResult.approved(txn);

    return PaymentResult.declined(
      errorCode: errorCondition ?? 'ADYEN_DECLINED',
      errorMessage: additional ?? 'Adyen payment not approved ($result)',
      supportCode: additional,
      transaction: txn,
    );
  }

  @override
  Future<void> dispose() async {
    _initialized = false;
  }
}
