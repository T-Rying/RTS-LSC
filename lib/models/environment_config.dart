import 'dart:convert';

class EnvironmentConfig {
  String name;
  String baseUrl;
  String tenant;

  EnvironmentConfig({
    required this.name,
    required this.baseUrl,
    this.tenant = '',
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'baseUrl': baseUrl,
        'tenant': tenant,
      };

  factory EnvironmentConfig.fromJson(Map<String, dynamic> json) {
    return EnvironmentConfig(
      name: json['name'] as String,
      baseUrl: json['baseUrl'] as String,
      tenant: json['tenant'] as String? ?? '',
    );
  }

  static String encodeList(List<EnvironmentConfig> configs) {
    return jsonEncode(configs.map((c) => c.toJson()).toList());
  }

  static List<EnvironmentConfig> decodeList(String json) {
    final list = jsonDecode(json) as List;
    return list.map((e) => EnvironmentConfig.fromJson(e as Map<String, dynamic>)).toList();
  }
}
