import 'dart:convert';

enum ConnectionType { onPremise, saas }

enum DeviceType { phone, tablet }

/// Which payment provider is active for card transactions.
/// Only one can be active at a time; the POS page builds the corresponding
/// `PaymentProviderType` at startup based on this value.
enum PaymentProviderType { none, softpay, adyen }

class EnvironmentConfig {
  ConnectionType type;
  // On-Premise fields
  String serverUrl;
  String instance;
  int port;
  // SaaS fields
  String tenant;
  String clientId;
  String clientSecret;
  // Shared
  String company;
  String companyName;
  // Mobile Inventory
  String storeNo;
  // POS credentials
  String posUsername;
  String posPassword;
  // Device type
  DeviceType deviceType;
  // Payment provider selection
  PaymentProviderType paymentProvider;
  // SoftPay credentials (only used when paymentProvider == softpay)
  String softPayIntegratorId;
  String softPayCredentials;
  // Adyen credentials (only used when paymentProvider == adyen)
  // Obtain from your Adyen Customer Area. See the docs at
  // https://docs.adyen.com/point-of-sale/mobile-android/build/payments-app
  String adyenMerchantAccount;
  String adyenApiKey;
  String adyenSharedKey;
  String adyenStoreId;
  String adyenTerminalId;
  // true = sandbox (use https://www.adyen.com/test/...); false = production.
  bool adyenTestMode;

  EnvironmentConfig({
    required this.type,
    this.serverUrl = '',
    this.instance = '',
    this.port = 7048,
    this.tenant = '',
    this.clientId = '',
    this.clientSecret = '',
    this.company = '',
    this.companyName = '',
    this.storeNo = '',
    this.posUsername = '',
    this.posPassword = '',
    required this.deviceType,
    this.paymentProvider = PaymentProviderType.none,
    this.softPayIntegratorId = '',
    this.softPayCredentials = '',
    this.adyenMerchantAccount = '',
    this.adyenApiKey = '',
    this.adyenSharedKey = '',
    this.adyenStoreId = '',
    this.adyenTerminalId = '',
    this.adyenTestMode = true,
  });

  String get displayName => type == ConnectionType.saas ? 'SaaS' : 'On-Premise';

  /// Backwards-compat getter. Existing call sites check `.softPayEnabled`;
  /// this keeps them compiling until the payment-abstraction refactor lands
  /// everywhere. Prefer `paymentProvider == PaymentProviderType.softpay`.
  bool get softPayEnabled => paymentProvider == PaymentProviderType.softpay;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'serverUrl': serverUrl,
        'instance': instance,
        'port': port,
        'tenant': tenant,
        'clientId': clientId,
        'clientSecret': clientSecret,
        'company': company,
        'companyName': companyName,
        'storeNo': storeNo,
        'posUsername': posUsername,
        'posPassword': posPassword,
        'deviceType': deviceType.name,
        'paymentProvider': paymentProvider.name,
        'softPayIntegratorId': softPayIntegratorId,
        'softPayCredentials': softPayCredentials,
        'adyenMerchantAccount': adyenMerchantAccount,
        'adyenApiKey': adyenApiKey,
        'adyenSharedKey': adyenSharedKey,
        'adyenStoreId': adyenStoreId,
        'adyenTerminalId': adyenTerminalId,
        'adyenTestMode': adyenTestMode,
      };

  factory EnvironmentConfig.fromJson(Map<String, dynamic> json) {
    // Migrate the legacy `softPayEnabled: bool` field → `paymentProvider` enum.
    PaymentProviderType provider;
    final providerName = json['paymentProvider'] as String?;
    if (providerName != null) {
      provider = PaymentProviderType.values.firstWhere(
        (p) => p.name == providerName,
        orElse: () => PaymentProviderType.none,
      );
    } else if (json['softPayEnabled'] == true) {
      provider = PaymentProviderType.softpay;
    } else {
      provider = PaymentProviderType.none;
    }

    return EnvironmentConfig(
      type: json['type'] == 'saas' ? ConnectionType.saas : ConnectionType.onPremise,
      serverUrl: json['serverUrl'] as String? ?? '',
      instance: json['instance'] as String? ?? '',
      port: json['port'] as int? ?? 7048,
      tenant: json['tenant'] as String? ?? '',
      clientId: json['clientId'] as String? ?? '',
      clientSecret: json['clientSecret'] as String? ?? '',
      company: json['company'] as String? ?? '',
      companyName: json['companyName'] as String? ?? '',
      storeNo: json['storeNo'] as String? ?? '',
      posUsername: json['posUsername'] as String? ?? '',
      posPassword: json['posPassword'] as String? ?? '',
      deviceType: json['deviceType'] == 'tablet' ? DeviceType.tablet : DeviceType.phone,
      paymentProvider: provider,
      softPayIntegratorId: json['softPayIntegratorId'] as String? ?? '',
      softPayCredentials: json['softPayCredentials'] as String? ?? '',
      adyenMerchantAccount: json['adyenMerchantAccount'] as String? ?? '',
      adyenApiKey: json['adyenApiKey'] as String? ?? '',
      adyenSharedKey: json['adyenSharedKey'] as String? ?? '',
      adyenStoreId: json['adyenStoreId'] as String? ?? '',
      adyenTerminalId: json['adyenTerminalId'] as String? ?? '',
      adyenTestMode: json['adyenTestMode'] as bool? ?? true,
    );
  }

  String encode() => jsonEncode(toJson());

  static EnvironmentConfig? decode(String? json) {
    if (json == null) return null;
    return EnvironmentConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }
}
