import '../../models/environment_config.dart';
import 'payment_result.dart';

/// Common interface that every payment-provider implementation must satisfy.
///
/// The POS page holds a single `PaymentProvider` reference, chosen from the
/// user's `EnvironmentConfig.paymentProvider` setting at startup. Both the
/// SoftPay and Adyen implementations translate the provider-specific
/// response shape into the shared `PaymentResult` / `PaymentTransaction`.
abstract class PaymentProvider {
  /// Human-readable name for logs ("SoftPay", "Adyen", …).
  String get name;

  /// True once `initialize()` has completed successfully.
  bool get isInitialized;

  /// Perform any first-run setup (SDK init, credential validation, boarding
  /// check). Safe to call multiple times — implementations should no-op if
  /// already initialized.
  ///
  /// Returns true on success. Implementations should log specific failures
  /// (missing credentials, unreachable backend, device not boarded, etc.).
  Future<bool> initialize();

  /// Charge the given amount. [amount] is minor units (e.g. 3400 = 34.00).
  /// [posReferenceNumber] is the LS Central TransactionId, passed through
  /// to the provider so it can correlate retries on its side.
  Future<PaymentResult> purchase({
    required int amount,
    required String currency,
    String? posReferenceNumber,
  });

  /// Refund the given amount. Same minor-unit convention as [purchase].
  Future<PaymentResult> refund({
    required int amount,
    required String currency,
    String? posReferenceNumber,
  });

  /// Void/cancel a previously authorized transaction.
  /// [providerTransactionId] is the provider's own ID (e.g. SoftPay's
  /// requestId, Adyen's POITransactionID) — typically sourced from
  /// `PaymentResult.transaction.providerTransactionId` on the original txn.
  Future<PaymentResult> cancel({String? providerTransactionId});

  /// Tear down SDK state, close channels, drop references. Called when the
  /// POS page is closed or the user switches providers.
  Future<void> dispose();
}

/// Construct the configured `PaymentProvider` from the active environment
/// config. Callers (POS page) use this factory and hold the result for the
/// page's lifetime; they do not need to know which concrete class they got.
///
/// Returns [NullPaymentProvider] if no provider is selected — purchase
/// attempts will fail loudly instead of silently doing nothing.
typedef PaymentProviderFactory = PaymentProvider Function(EnvironmentConfig);

/// Default provider when `paymentProvider == PaymentProvider.none`.
/// Any purchase attempt fails with a clear "no provider selected" error.
class NullPaymentProvider implements PaymentProvider {
  @override
  String get name => 'None';

  @override
  bool get isInitialized => false;

  @override
  Future<bool> initialize() async => false;

  @override
  Future<PaymentResult> purchase({
    required int amount,
    required String currency,
    String? posReferenceNumber,
  }) async =>
      const PaymentResult.declined(
        errorCode: 'NO_PROVIDER',
        errorMessage: 'No payment provider configured. '
            'Select SoftPay or Adyen in Settings.',
      );

  @override
  Future<PaymentResult> refund({
    required int amount,
    required String currency,
    String? posReferenceNumber,
  }) async =>
      const PaymentResult.declined(
        errorCode: 'NO_PROVIDER',
        errorMessage: 'No payment provider configured.',
      );

  @override
  Future<PaymentResult> cancel({String? providerTransactionId}) async =>
      const PaymentResult.declined(
        errorCode: 'NO_PROVIDER',
        errorMessage: 'No payment provider configured.',
      );

  @override
  Future<void> dispose() async {}
}
