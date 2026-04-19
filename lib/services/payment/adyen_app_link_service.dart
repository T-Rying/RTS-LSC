import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:url_launcher/url_launcher.dart';

import '../log_service.dart';

/// Dedicated service for the Adyen Android Payments app "App Link" round-trip.
///
/// The Adyen integration is pure HTTP App Links (no SDK). Our POS app launches
/// a URL like `https://www.adyen.com/test/boarded?returnUrl=...`; the installed
/// Adyen app intercepts it via Android App Link verification, processes the
/// request, and calls us back via the returnUrl we provided (in our case,
/// `rts-lsc://adyen-return?...`).
///
/// This class owns:
/// - The long-lived `AppLinks` subscription (set up in the app-wide singleton)
/// - Correlation between a single outgoing launch and the matching inbound return
/// - Timeouts (Adyen may never return if the user kills the Adyen app mid-flow)
///
/// Usage:
/// ```dart
/// final service = AdyenAppLinkService.instance;
/// final returnUri = await service.launchAndAwaitReturn(
///   Uri.parse('https://www.adyen.com/test/boarded?returnUrl=rts-lsc://adyen-return'),
///   timeout: const Duration(seconds: 30),
/// );
/// // returnUri has boarded / installationId / boardingRequestToken in its query params
/// ```
class AdyenAppLinkService {
  AdyenAppLinkService._();
  static final AdyenAppLinkService instance = AdyenAppLinkService._();

  final AppLinks _appLinks = AppLinks();
  final LogService _log = LogService.instance;

  /// Scheme + host of our return URL. Must match AndroidManifest.xml
  /// intent-filter: `android:scheme="rts-lsc" android:host="adyen-return"`.
  static const String returnScheme = 'rts-lsc';
  static const String returnHost = 'adyen-return';
  static const String returnUrl = '$returnScheme://$returnHost';

  /// Completer for the currently-pending launch, or null if nothing is in-flight.
  /// Only one App Link round-trip can be active at a time.
  Completer<Uri>? _pending;

  /// Subscription to the app-wide deep-link stream.
  StreamSubscription<Uri>? _sub;

  /// Start listening for incoming deep links. Call once at app startup (from
  /// `main.dart`). Safe to call multiple times; subsequent calls are no-ops.
  Future<void> start() async {
    if (_sub != null) return;
    _sub = _appLinks.uriLinkStream.listen(
      _onIncomingUri,
      onError: (e, st) => _log.error('AppLinks stream error: $e'),
    );
    _log.info('AdyenAppLinkService: listening for $returnUrl deep links');

    // In case the app was LAUNCHED by a deep link (cold-start), grab the
    // initial URI now — uriLinkStream may not emit it otherwise.
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _onIncomingUri(initial);
    } catch (e) {
      _log.warn('AppLinks.getInitialLink failed: $e');
    }
  }

  void _onIncomingUri(Uri uri) {
    // Ignore any deep links that aren't our Adyen return scheme — leaves room
    // to add other deep-link handlers (e.g. for SoftPay or magic-link login)
    // without them fighting over this service.
    if (uri.scheme != returnScheme || uri.host != returnHost) {
      _log.debug('Ignoring non-Adyen deep link: $uri');
      return;
    }
    _log.info('Adyen return URL received: ${_redact(uri)}');

    final pending = _pending;
    if (pending == null) {
      _log.warn('Received Adyen return with no pending launch — ignoring: $uri');
      return;
    }
    if (!pending.isCompleted) pending.complete(uri);
    _pending = null;
  }

  /// Launch the given Adyen App Link URL and wait for the return URL.
  /// Throws [TimeoutException] if no return arrives within [timeout].
  /// Throws [StateError] if another launch is already in-flight.
  /// Throws [PlatformException] if `url_launcher` cannot open the URL
  /// (usually means the Adyen Payments Test app is not installed).
  Future<Uri> launchAndAwaitReturn(
    Uri appLinkUri, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (_pending != null && !_pending!.isCompleted) {
      throw StateError(
          'Another Adyen App Link launch is already in-flight. '
          'Wait for it to return (or time out) before starting a new one.');
    }

    if (_sub == null) {
      await start();
    }

    _log.info('Launching Adyen App Link: ${_redact(appLinkUri)}');
    final completer = Completer<Uri>();
    _pending = completer;

    // Launch via url_launcher with externalApplication mode so Android routes
    // the HTTPS App Link to the Adyen Payments app (which must be installed
    // and verified for *.adyen.com in its manifest).
    final launched = await launchUrl(
      appLinkUri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      _pending = null;
      throw StateError(
          'url_launcher returned false launching $appLinkUri. '
          'The Adyen Payments Test app may not be installed, or Android could '
          'not resolve the App Link. Install it from Google Play.');
    }

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      _pending = null;
      _log.error('Adyen App Link timed out after ${timeout.inSeconds}s. '
          'The Adyen app did not call our return URL.');
      rethrow;
    }
  }

  /// Redact likely-secret query parameters before logging a URL.
  String _redact(Uri uri) {
    const secretKeys = {'boardingRequestToken', 'boardingToken', 'request'};
    if (!uri.queryParameters.keys.any(secretKeys.contains)) return uri.toString();
    final redacted = Map<String, String>.from(uri.queryParameters);
    for (final k in secretKeys) {
      if (redacted.containsKey(k)) {
        final v = redacted[k]!;
        redacted[k] = v.length > 8 ? '${v.substring(0, 4)}…${v.substring(v.length - 4)}' : '…';
      }
    }
    return uri.replace(queryParameters: redacted).toString();
  }

  /// Stop listening. Called on app shutdown — not usually necessary since the
  /// process dies anyway, but good hygiene for tests.
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    if (_pending != null && !_pending!.isCompleted) {
      _pending!.completeError(StateError('AdyenAppLinkService disposed'));
    }
    _pending = null;
  }
}
