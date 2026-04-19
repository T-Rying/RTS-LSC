import '../../models/environment_config.dart';
import 'adyen_provider.dart';
import 'payment_provider.dart';
import 'softpay_provider.dart';

/// Build the `PaymentProvider` matching the active config. POS page calls
/// this once during initState and keeps the reference for the page's
/// lifetime.
PaymentProvider buildPaymentProvider(EnvironmentConfig config) {
  switch (config.paymentProvider) {
    case PaymentProviderType.softpay:
      return SoftPayProvider(config);
    case PaymentProviderType.adyen:
      return AdyenProvider(config);
    case PaymentProviderType.none:
      return NullPaymentProvider();
  }
}
