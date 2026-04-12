import 'package:shared_preferences/shared_preferences.dart';
import '../models/environment_config.dart';

class EnvironmentService {
  static const _envsKey = 'environments';
  static const _activeKey = 'active_environment';

  final SharedPreferences _prefs;

  EnvironmentService(this._prefs);

  List<EnvironmentConfig> getEnvironments() {
    final json = _prefs.getString(_envsKey);
    if (json == null) return [];
    return EnvironmentConfig.decodeList(json);
  }

  Future<void> saveEnvironments(List<EnvironmentConfig> envs) async {
    await _prefs.setString(_envsKey, EnvironmentConfig.encodeList(envs));
  }

  String? getActiveEnvironment() => _prefs.getString(_activeKey);

  Future<void> setActiveEnvironment(String name) async {
    await _prefs.setString(_activeKey, name);
  }
}
