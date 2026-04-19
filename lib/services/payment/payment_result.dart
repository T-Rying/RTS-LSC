/// Outcome of a payment/refund/void transaction, independent of provider.
///
/// Both `SoftPayProvider` and `AdyenProvider` map their provider-specific
/// responses into this type so that `pos_page.dart` and the LS Central EFT
/// response builder don't need to know which provider ran.
class PaymentResult {
  /// True = approved/completed. False = declined/error/cancelled.
  final bool success;

  /// Provider-specific error code (e.g. SoftPay's `failure.code` int, or
  /// Adyen's NEXO ErrorCondition string). Null on success.
  final String? errorCode;

  /// Human-readable message for the cashier. On failure, provider
  /// implementations should include the support code (e.g. `T.12500.5001`)
  /// so the UI dialog + log surface the specifics.
  final String? errorMessage;

  /// Provider-specific support code (e.g. SoftPay `failure.supportCode()`
  /// → "T.12500.5001", or Adyen's message reference).
  /// Exposed separately from `errorMessage` so we can show it distinctly
  /// in logs / dialogs.
  final String? supportCode;

  /// Completed transaction details (card info, auth code, audit number).
  /// Null if no transaction object is available (e.g. declined before
  /// any acquirer round-trip).
  final PaymentTransaction? transaction;

  const PaymentResult({
    required this.success,
    this.errorCode,
    this.errorMessage,
    this.supportCode,
    this.transaction,
  });

  const PaymentResult.approved(this.transaction)
      : success = true,
        errorCode = null,
        errorMessage = null,
        supportCode = null;

  const PaymentResult.declined({
    this.errorCode,
    this.errorMessage,
    this.supportCode,
    this.transaction,
  }) : success = false;

  @override
  String toString() =>
      'PaymentResult(success=$success, errorCode=$errorCode, '
      'errorMessage=$errorMessage, supportCode=$supportCode, txn=$transaction)';
}

/// Successful/attempted transaction details. Provider implementations
/// populate as much as they can from their response; unset fields remain null.
///
/// The LS Central EFT response expects `TransactionId`, `EFTTransactionId`,
/// `AuthorizationCode`, `CardDetails.*`, `AmountBreakdown.*` etc.; we keep
/// enough here to build that response in a provider-agnostic way.
class PaymentTransaction {
  /// Provider's own transaction identifier (SoftPay requestId, Adyen
  /// ServiceID). Used by BC as the `EFTTransactionId`.
  final String? providerTransactionId;

  /// Acquirer/issuer authorization code.
  final String? authorizationCode;

  /// Card scheme / tender type (e.g. "VISA", "MASTERCARD").
  final String? cardScheme;

  /// Masked card number or token (never real PAN).
  final String? cardToken;

  /// Acquirer batch number if available.
  final String? batchNumber;

  /// Transaction state string (SoftPay: PROCESSING/COMPLETED/DECLINED/…,
  /// Adyen: similar). Used for diagnostics; the `success` flag on
  /// `PaymentResult` is the authoritative outcome.
  final String? state;

  /// Amount actually processed, in minor units (e.g. 3400 = 34.00).
  /// May differ from the requested amount on partial approval.
  final int? amountMinor;

  /// ISO currency code (DKK, EUR, etc.).
  final String? currencyCode;

  const PaymentTransaction({
    this.providerTransactionId,
    this.authorizationCode,
    this.cardScheme,
    this.cardToken,
    this.batchNumber,
    this.state,
    this.amountMinor,
    this.currencyCode,
  });

  @override
  String toString() => 'PaymentTransaction(id=$providerTransactionId, '
      'state=$state, scheme=$cardScheme, amount=$amountMinor $currencyCode)';
}
