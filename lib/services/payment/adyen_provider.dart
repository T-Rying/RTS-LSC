import '../../models/environment_config.dart';
import '../log_service.dart';
import 'payment_provider.dart';
import 'payment_result.dart';

/// Phase A stub. Implements `PaymentProvider` so the settings toggle and
/// POS page wiring can be tested, but every transaction operation returns
/// a clean "not implemented" error. Phase B will add the `/boarded` check,
/// Phase C the actual `/nexo` App-Link payment flow.
///
/// See the Adyen Android Payments app docs at
/// https://docs.adyen.com/point-of-sale/mobile-android/build/payments-app
/// for the full integration model.
class AdyenProvider implements PaymentProvider {
  final EnvironmentConfig config;
  final LogService _log = LogService.instance;

  bool _initialized = false;

  AdyenProvider(this.config);

  @override
  String get name => 'Adyen';

  @override
  bool get isInitialized => _initialized;

  @override
  Future<bool> initialize() async {
    // Phase A: just validate that credentials are present — no network call.
    // Phase B will add the `/boarded` App Link probe.
    final missing = <String>[
      if (config.adyenMerchantAccount.isEmpty) 'merchantAccount',
      if (config.adyenApiKey.isEmpty) 'apiKey',
      if (config.adyenSharedKey.isEmpty) 'sharedKey',
      if (config.adyenStoreId.isEmpty) 'storeId',
      if (config.adyenTerminalId.isEmpty) 'terminalId',
    ];
    if (missing.isNotEmpty) {
      _log.warn('Adyen: missing config: ${missing.join(", ")}');
      _initialized = false;
      return false;
    }
    _log.info('Adyen: config validated (test=${config.adyenTestMode}) — '
        'Phase A stub, transactions not yet wired');
    _initialized = true;
    return true;
  }

  @override
  Future<PaymentResult> purchase({
    required int amount,
    required String currency,
    String? posReferenceNumber,
  }) async {
    _log.warn('Adyen.purchase called — not implemented yet (Phase A stub). '
        'amount=$amount $currency ref=$posReferenceNumber');
    return const PaymentResult.declined(
      errorCode: 'ADYEN_NOT_IMPLEMENTED',
      errorMessage: 'Adyen purchase flow is not wired yet. '
          'Switch to SoftPay in Settings, or wait for Phase C of the Adyen integration.',
    );
  }

  @override
  Future<PaymentResult> refund({
    required int amount,
    required String currency,
    String? posReferenceNumber,
  }) async {
    _log.warn('Adyen.refund called — not implemented yet (Phase A stub)');
    return const PaymentResult.declined(
      errorCode: 'ADYEN_NOT_IMPLEMENTED',
      errorMessage: 'Adyen refund flow is not wired yet.',
    );
  }

  @override
  Future<PaymentResult> cancel({String? providerTransactionId}) async {
    _log.warn('Adyen.cancel called — not implemented yet (Phase A stub)');
    return const PaymentResult.declined(
      errorCode: 'ADYEN_NOT_IMPLEMENTED',
      errorMessage: 'Adyen cancel flow is not wired yet.',
    );
  }

  @override
  Future<void> dispose() async {
    _initialized = false;
  }
}
