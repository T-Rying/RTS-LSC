import 'dart:convert';

enum ConnectionType { onPremise, saas }

enum DeviceType { phone, tablet }

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
  // POS credentials
  String posUsername;
  String posPassword;
  // Device type
  DeviceType deviceType;

  EnvironmentConfig({
    required this.type,
    this.serverUrl = '',
    this.instance = '',
    this.port = 7048,
    this.tenant = '',
    this.clientId = '',
    this.clientSecret = '',
    this.company = '',
    this.posUsername = '',
    this.posPassword = '',
    required this.deviceType,
  });

  String get displayName => type == ConnectionType.saas ? 'SaaS' : 'On-Premise';

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'serverUrl': serverUrl,
        'instance': instance,
        'port': port,
        'tenant': tenant,
        'clientId': clientId,
        'clientSecret': clientSecret,
        'company': company,
        'posUsername': posUsername,
        'posPassword': posPassword,
        'deviceType': deviceType.name,
      };

  factory EnvironmentConfig.fromJson(Map<String, dynamic> json) {
    return EnvironmentConfig(
      type: json['type'] == 'saas' ? ConnectionType.saas : ConnectionType.onPremise,
      serverUrl: json['serverUrl'] as String? ?? '',
      instance: json['instance'] as String? ?? '',
      port: json['port'] as int? ?? 7048,
      tenant: json['tenant'] as String? ?? '',
      clientId: json['clientId'] as String? ?? '',
      clientSecret: json['clientSecret'] as String? ?? '',
      company: json['company'] as String? ?? '',
      posUsername: json['posUsername'] as String? ?? '',
      posPassword: json['posPassword'] as String? ?? '',
      deviceType: json['deviceType'] == 'tablet' ? DeviceType.tablet : DeviceType.phone,
    );
  }

  String encode() => jsonEncode(toJson());

  static EnvironmentConfig? decode(String? json) {
    if (json == null) return null;
    return EnvironmentConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }
}
