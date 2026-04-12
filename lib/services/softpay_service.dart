import 'package:url_launcher/url_launcher.dart';
import '../models/environment_config.dart';

class SoftPayService {
  final EnvironmentConfig config;

  SoftPayService(this.config);

  /// Launches SoftPay app to process a payment.
  /// [amount] is in minor units (e.g. 1000 = 10.00 in the currency).
  /// [currency] is the ISO 4217 currency code (e.g. 'DKK', 'EUR').
  /// [reference] is an optional transaction reference from LS Central.
  Future<bool> requestPayment({
    required int amount,
    required String currency,
    String? reference,
  }) async {
    if (!config.softPayEnabled ||
        config.softPayIntegratorId.isEmpty ||
        config.softPayCredentials.isEmpty) {
      return false;
    }

    final params = {
      'integrator_id': config.softPayIntegratorId,
      'credentials': config.softPayCredentials,
      'amount': amount.toString(),
      'currency': currency,
      if (reference != null) 'reference': reference,
      'callback': 'rtslsc://softpay-callback',
    };

    final uri = Uri(
      scheme: 'softpay',
      host: 'payment',
      queryParameters: params,
    );

    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }
}
