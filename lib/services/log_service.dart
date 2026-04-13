import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' show Share, XFile;

enum LogLevel { debug, info, warn, error }

class LogService {
  static final LogService _instance = LogService._();
  static LogService get instance => _instance;

  LogService._();

  static const int _maxEntries = 500;
  final List<String> _logs = [];
  final _sessionStart = DateTime.now();

  List<String> get logs => List.unmodifiable(_logs);
  int get length => _logs.length;

  String _timestamp() {
    return DateTime.now().toString().substring(0, 23); // yyyy-MM-dd HH:mm:ss.SSS
  }

  String _levelTag(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 'DBG';
      case LogLevel.info:
        return 'INF';
      case LogLevel.warn:
        return 'WRN';
      case LogLevel.error:
        return 'ERR';
    }
  }

  void log(LogLevel level, String message) {
    final entry = '[${_timestamp()}] ${_levelTag(level)} $message';
    _logs.add(entry);
    if (_logs.length > _maxEntries) _logs.removeAt(0);
    if (kDebugMode) debugPrint(entry);
  }

  void debug(String msg) => log(LogLevel.debug, msg);
  void info(String msg) => log(LogLevel.info, msg);
  void warn(String msg) => log(LogLevel.warn, msg);
  void error(String msg) => log(LogLevel.error, msg);

  void clear() => _logs.clear();

  String exportToString() {
    final buf = StringBuffer();
    buf.writeln('=== RTS-LSC Debug Log ===');
    buf.writeln('Session started: $_sessionStart');
    buf.writeln('Exported: ${DateTime.now()}');
    buf.writeln('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    buf.writeln('Entries: ${_logs.length}');
    buf.writeln('========================');
    buf.writeln();
    for (final entry in _logs) {
      buf.writeln(entry);
    }
    return buf.toString();
  }

  Future<File> exportToFile() async {
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final file = File('${dir.path}/rts_lsc_log_$timestamp.txt');
    await file.writeAsString(exportToString());
    return file;
  }

  Future<void> share() async {
    final file = await exportToFile();
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'RTS-LSC Debug Log ${DateTime.now().toString().substring(0, 16)}',
    );
  }
}
