import 'dart:convert';

enum ConnectionType { onPremise, saas }

class EnvironmentConfig {
  ConnectionType type;
  String serverUrl;
  String instance;
  String tenant;
  String company;
  int port;

  EnvironmentConfig({
    required this.type,
    required this.serverUrl,
    this.instance = '',
    this.tenant = '',
    this.company = '',
    this.port = 7048,
  });

  String get displayName => type == ConnectionType.saas ? 'SaaS' : 'On-Premise';

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'serverUrl': serverUrl,
        'instance': instance,
        'tenant': tenant,
        'company': company,
        'port': port,
      };

  factory EnvironmentConfig.fromJson(Map<String, dynamic> json) {
    return EnvironmentConfig(
      type: json['type'] == 'saas' ? ConnectionType.saas : ConnectionType.onPremise,
      serverUrl: json['serverUrl'] as String,
      instance: json['instance'] as String? ?? '',
      tenant: json['tenant'] as String? ?? '',
      company: json['company'] as String? ?? '',
      port: json['port'] as int? ?? 7048,
    );
  }

  String encode() => jsonEncode(toJson());

  static EnvironmentConfig? decode(String? json) {
    if (json == null) return null;
    return EnvironmentConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }
}
