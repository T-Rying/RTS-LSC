import 'dart:convert';

import 'package:flutter/services.dart';

import '../log_service.dart';

/// Kotlin → Dart MethodChannel handler for the Adyen `/nexo` dispatch.
///
/// LS Central's JS bridge calls `LSAppShell.request("Purchase", json)`
/// synchronously; that lands in Kotlin's `SoftPayPlugin.processRequest`
/// which, when `activeProvider == "adyen"`, invokes the channel here
/// instead of the SoftPay SDK. We route the call to the POS page's
/// active `AdyenProvider`, build an LS-Central-compatible response
/// JSON string, and return it — Kotlin then releases the JS latch so
/// LS Central unblocks and gets a "real" response.
///
/// The handler is set by the POS page when it mounts (and cleared on
/// dispose) so calls that arrive while the page isn't active get a
/// clean "not ready" error rather than crashing.
class AdyenNativeBridge {
  static final AdyenNativeBridge instance = AdyenNativeBridge._();
  AdyenNativeBridge._();

  static const String _channelName = 'com.rts.lsc/adyen-dispatch';
  static const MethodChannel _channel = MethodChannel(_channelName);

  final LogService _log = LogService.instance;

  /// Closure set by the POS page. Takes the parsed LS Central payload
  /// (the JSON object that came through `LSAppShell.request`) and
  /// returns the LS Central response JSON string (shape documented in
  /// `_toLsCentralJson` — ResultCode/AuthorizationStatus/IDs/etc.).
  Future<String> Function(String command, Map<String, dynamic> json)? _handler;

  bool _started = false;

  /// Register the Kotlin-side call handler. Safe to call repeatedly —
  /// subsequent calls just swap the active [handler].
  void start({
    required Future<String> Function(String command, Map<String, dynamic> json) handler,
  }) {
    _handler = handler;
    if (_started) return;
    _channel.setMethodCallHandler(_onCall);
    _started = true;
    _log.info('AdyenNativeBridge: listening on $_channelName');
  }

  /// Forget the current handler. Calls arriving after this return an
  /// error response rather than hitting a stale closure that might
  /// reference a disposed state.
  void stop() {
    _handler = null;
    _log.info('AdyenNativeBridge: handler cleared');
  }

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method != 'dispatchPayment') {
      throw MissingPluginException('Unknown method: ${call.method}');
    }
    final handler = _handler;
    if (handler == null) {
      _log.warn('AdyenNativeBridge: dispatchPayment with no handler');
      return _errorResponse('Adyen handler not registered '
          '(POS page may not be mounted).');
    }

    final args = call.arguments as Map<Object?, Object?>;
    final command = args['command'] as String? ?? 'Purchase';
    final jsonText = args['json'] as String? ?? '{}';
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(jsonText);
      json = decoded is Map<String, dynamic>
          ? decoded
          : Map<String, dynamic>.from(decoded as Map);
    } catch (e) {
      _log.error('AdyenNativeBridge: bad JSON from Kotlin: $e');
      return _errorResponse('Malformed Adyen request JSON: $e');
    }

    try {
      return await handler(command, json);
    } catch (e) {
      _log.error('AdyenNativeBridge: handler threw: $e');
      return _errorResponse('Adyen dispatch handler error: $e');
    }
  }

  static String _errorResponse(String message) => jsonEncode({
        'ResultCode': 'Error',
        'AuthorizationStatus': 'Declined',
        'Message': message,
        'IDs': {'TransactionId': '', 'EFTTransactionId': ''},
        'AmountBreakdown': {'TotalAmount': 0, 'CurrencyCode': 'DKK'},
      });
}
