import 'package:shared_preferences/shared_preferences.dart';
import '../models/environment_config.dart';

class EnvironmentService {
  static const _connectionKey = 'connection';

  final SharedPreferences _prefs;

  EnvironmentService(this._prefs);

  EnvironmentConfig? getConnection() {
    final json = _prefs.getString(_connectionKey);
    return EnvironmentConfig.decode(json);
  }

  Future<void> saveConnection(EnvironmentConfig config) async {
    await _prefs.setString(_connectionKey, config.encode());
  }

  Future<void> deleteConnection() async {
    await _prefs.remove(_connectionKey);
  }
}
