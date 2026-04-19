import '../../models/environment_config.dart';
import '../log_service.dart';
import '../softpay_plugin.dart';
import 'payment_provider.dart';
import 'payment_result.dart';

/// Adapter that presents the existing `SoftPayPlugin` (MethodChannel wrapper
/// around the SoftPay AppSwitch SDK) behind the generic `PaymentProvider`
/// interface.
///
/// No SoftPay behaviour changes here — all the Kotlin-side logic
/// (sanitizePosReference, describeFailure, native blocking bridge, etc.)
/// that ships with commits 9ababa5..81b691c is still in play. This class
/// is purely a thin translation layer between shared types and SoftPay-
/// specific types.
class SoftPayProvider implements PaymentProvider {
  final EnvironmentConfig config;
  final SoftPayPlugin _plugin;
  final LogService _log = LogService.instance;

  SoftPayProvider(this.config, {SoftPayPlugin? plugin})
      : _plugin = plugin ?? SoftPayPlugin();

  @override
  String get name => 'SoftPay';

  @override
  bool get isInitialized => _plugin.isInitialized;

  @override
  Future<bool> initialize() async {
    if (config.softPayIntegratorId.isEmpty) {
      _log.warn('SoftPay: no integrator id configured — skipping initialize');
      return false;
    }
    return _plugin.initialize(
      integratorId: config.softPayIntegratorId,
      secret: config.softPayCredentials,
    );
  }

  @override
  Future<PaymentResult> purchase({
    required int amount,
    required String currency,
    String? posReferenceNumber,
  }) async {
    final r = await _plugin.purchase(
      amount: amount,
      currency: currency,
      posReferenceNumber: posReferenceNumber,
    );
    return _mapResult(r);
  }

  @override
  Future<PaymentResult> refund({
    required int amount,
    required String currency,
    String? posReferenceNumber,
  }) async {
    final r = await _plugin.refund(
      amount: amount,
      currency: currency,
      posReferenceNumber: posReferenceNumber,
    );
    return _mapResult(r);
  }

  @override
  Future<PaymentResult> cancel({String? providerTransactionId}) async {
    final r = await _plugin.cancel(requestId: providerTransactionId);
    return _mapResult(r);
  }

  @override
  Future<void> dispose() => _plugin.dispose();

  /// Convert `SoftPayResult` → shared `PaymentResult`.
  PaymentResult _mapResult(SoftPayResult r) {
    final txn = r.transaction;
    final paymentTxn = txn == null
        ? null
        : PaymentTransaction(
            providerTransactionId: txn.requestId,
            authorizationCode: txn.auditNumber,
            cardScheme: txn.cardScheme,
            cardToken: txn.cardToken,
            batchNumber: txn.batchNumber,
            state: txn.state,
            amountMinor: txn.amount,
            currencyCode: txn.currency,
          );

    return PaymentResult(
      success: r.success,
      errorCode: r.errorCode?.toString(),
      errorMessage: r.errorMessage,
      // SoftPay support code is already embedded in errorMessage by the
      // Kotlin plugin (Phase 3, commit 81b691c) — we don't have a separate
      // field in SoftPayResult yet.
      transaction: paymentTxn,
    );
  }
}
