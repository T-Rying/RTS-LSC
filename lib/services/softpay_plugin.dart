import 'dart:convert';
import 'package:flutter/services.dart';
import 'log_service.dart';

/// Dart wrapper around the SoftPay Android SDK via platform channel.
/// Replaces the old URI scheme approach with proper SDK integration.
class SoftPayPlugin {
  static const _channel = MethodChannel('com.rts.lsc/softpay');
  static final _log = LogService.instance;

  bool _initialized = false;

  /// Initialize the SoftPay client with integrator credentials.
  Future<bool> initialize({
    required String integratorId,
    required String secret,
  }) async {
    try {
      _log.info('SoftPay: initializing with integrator=$integratorId');
      final result = await _channel.invokeMethod('initialize', {
        'integratorId': integratorId,
        'secret': secret,
      });
      _initialized = result == true;
      _log.info('SoftPay: initialized=$_initialized');
      return _initialized;
    } on PlatformException catch (e) {
      _log.error('SoftPay init failed: ${e.code} ${e.message}');
      return false;
    }
  }

  /// Process a purchase transaction.
  /// [amount] is in minor units (e.g. 2000 = 20.00 DKK).
  /// [posReferenceNumber] is an optional reference (typically LS Central's
  /// TransactionId) passed to SoftPay so the SDK can correlate retries and
  /// recoveries on its side. SoftPay strongly recommends always supplying this.
  Future<SoftPayResult> purchase({
    required int amount,
    required String currency,
    String? posReferenceNumber,
  }) async {
    _log.info('SoftPay: purchase amount=$amount currency=$currency ref=$posReferenceNumber');
    return _callTransaction('purchase', {
      'amount': amount,
      'currency': currency,
      if (posReferenceNumber != null && posReferenceNumber.isNotEmpty)
        'posReferenceNumber': posReferenceNumber,
    });
  }

  /// Process a refund transaction.
  Future<SoftPayResult> refund({
    required int amount,
    required String currency,
    String? posReferenceNumber,
  }) async {
    _log.info('SoftPay: refund amount=$amount currency=$currency ref=$posReferenceNumber');
    return _callTransaction('refund', {
      'amount': amount,
      'currency': currency,
      if (posReferenceNumber != null && posReferenceNumber.isNotEmpty)
        'posReferenceNumber': posReferenceNumber,
    });
  }

  /// Cancel a previous transaction by request ID.
  Future<SoftPayResult> cancel({String? requestId}) async {
    _log.info('SoftPay: cancel requestId=$requestId');
    return _callTransaction('cancel', {
      if (requestId != null) 'requestId': requestId,
    });
  }

  /// Dispose the SoftPay client.
  Future<void> dispose() async {
    try {
      await _channel.invokeMethod('dispose');
      _initialized = false;
      _log.info('SoftPay: disposed');
    } catch (e) {
      _log.error('SoftPay dispose error: $e');
    }
  }

  bool get isInitialized => _initialized;

  Future<SoftPayResult> _callTransaction(
    String method,
    Map<String, dynamic> args,
  ) async {
    if (!_initialized) {
      return SoftPayResult(
        success: false,
        errorMessage: 'SoftPay not initialized',
      );
    }

    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(method, args);
      if (result == null) {
        return SoftPayResult(success: false, errorMessage: 'No result from SDK');
      }

      final map = result.map((k, v) => MapEntry(k.toString(), v));
      final success = map['success'] == true;
      final txnMap = map['transaction'] as Map<Object?, Object?>?;

      _log.info('SoftPay: $method result success=$success');

      return SoftPayResult(
        success: success,
        errorCode: map['errorCode'] as int?,
        errorMessage: map['errorMessage'] as String?,
        transaction: txnMap != null
            ? SoftPayTransaction.fromMap(
                txnMap.map((k, v) => MapEntry(k.toString(), v)))
            : null,
      );
    } on PlatformException catch (e) {
      _log.error('SoftPay $method platform error: ${e.code} ${e.message}');
      return SoftPayResult(
        success: false,
        errorMessage: '${e.code}: ${e.message}',
      );
    } catch (e) {
      _log.error('SoftPay $method error: $e');
      return SoftPayResult(success: false, errorMessage: e.toString());
    }
  }
}

class SoftPayResult {
  final bool success;
  final int? errorCode;
  final String? errorMessage;
  final SoftPayTransaction? transaction;

  SoftPayResult({
    required this.success,
    this.errorCode,
    this.errorMessage,
    this.transaction,
  });
}

class SoftPayTransaction {
  final String? requestId;
  final String? state;
  final String? type;
  final int? amount;
  final String? currency;
  final String? cardScheme;
  final String? cardToken;
  final String? auditNumber;
  final String? batchNumber;

  SoftPayTransaction({
    this.requestId,
    this.state,
    this.type,
    this.amount,
    this.currency,
    this.cardScheme,
    this.cardToken,
    this.auditNumber,
    this.batchNumber,
  });

  factory SoftPayTransaction.fromMap(Map<String, dynamic> map) {
    return SoftPayTransaction(
      requestId: map['requestId'] as String?,
      state: map['state'] as String?,
      type: map['type'] as String?,
      amount: (map['amount'] as num?)?.toInt(),
      currency: map['currency'] as String?,
      cardScheme: map['cardScheme'] as String?,
      cardToken: map['cardToken'] as String?,
      auditNumber: map['auditNumber'] as String?,
      batchNumber: map['batchNumber'] as String?,
    );
  }

  /// Convert to LS Central EFT response JSON format.
  /// [clientTransactionId] is the original TransactionId from the LS Central request
  /// that must be echoed back so BC can match request to response.
  String toLsCentralJson({String clientTransactionId = ''}) {
    final amountDecimal = amount != null ? amount! / 100.0 : 0.0;
    return jsonEncode({
      'TransactionType': type ?? 'Purchase',
      'AuthorizationStatus': state == 'COMPLETED' ? 'Approved' : 'Declined',
      'AuthorizationCode': auditNumber ?? '',
      'ResultCode': state == 'COMPLETED' ? 'Success' : 'Error',
      'Message': state == 'COMPLETED' ? 'Transaction approved' : 'Transaction $state',
      'TenderType': cardScheme ?? '',
      'IDs': {
        'TransactionId': clientTransactionId,
        'EFTTransactionId': requestId ?? '',
        'TransactionDateTime': DateTime.now().toIso8601String(),
        'AdditionalId': '',
        'MerchantOrderId': '',
        'BatchNumber': batchNumber ?? '',
      },
      'CardDetails': {
        'CardNumber': cardToken ?? '',
        'CardIssuer': cardScheme ?? '',
      },
      'AmountBreakdown': {
        'TotalAmount': amountDecimal,
        'CurrencyCode': currency ?? 'DKK',
        'CashbackAmount': 0.0,
        'TaxAmount': 0.0,
        'SurchargeAmount': 0.0,
        'TipAmount': 0.0,
      },
    });
  }
}
