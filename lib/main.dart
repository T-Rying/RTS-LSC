import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/environment_config.dart';
import 'pages/pos_page.dart';
import 'pages/settings_page.dart';
import 'services/environment_service.dart';
import 'services/log_service.dart';

late EnvironmentService environmentService;

const Color _primaryColor = Color(0xFF003366);

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      LogService.instance.error(
        'Flutter error: ${details.exceptionAsString()}\n${details.stack}',
      );
    };

    final prefs = await SharedPreferences.getInstance();
    environmentService = EnvironmentService(prefs);
    LogService.instance.info('App started');
    runApp(const MyApp());
  }, (error, stack) {
    LogService.instance.error('Uncaught Dart error: $error\n$stack');
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const CupertinoApp(
      title: 'RTS - LS Central',
      theme: CupertinoThemeData(
        primaryColor: _primaryColor,
        brightness: Brightness.light,
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  EnvironmentConfig? _connection;

  @override
  void initState() {
    super.initState();
    _connection = environmentService.getConnection();
  }

  void _refreshConnection() {
    setState(() {
      _connection = environmentService.getConnection();
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('LS Central'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          child: const Icon(CupertinoIcons.gear),
          onPressed: () async {
            await Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (_) => SettingsPage(envService: environmentService),
              ),
            );
            _refreshConnection();
          },
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_connection != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Text(
                    _connection!.type == ConnectionType.saas
                        ? 'SaaS: ${_connection!.tenant}'
                        : 'On-Premise: ${_connection!.serverUrl}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: CupertinoColors.systemGrey,
                    ),
                  ),
                ),
              if (_connection == null)
                const Padding(
                  padding: EdgeInsets.only(bottom: 24),
                  child: Text(
                    'No connection configured — tap the gear icon',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: CupertinoColors.systemOrange,
                    ),
                  ),
                ),
              _ModuleButton(
                icon: CupertinoIcons.creditcard,
                label: 'POS',
                onTap: () {
                  if (_connection == null) {
                    _showAlert('Configure a connection in Settings first');
                    return;
                  }
                  if (_connection!.tenant.isEmpty || _connection!.company.isEmpty) {
                    _showAlert('Tenant and Company are required for POS');
                    return;
                  }
                  Navigator.push(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => PosPage(config: _connection!),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              _ModuleButton(
                icon: CupertinoIcons.cube_box,
                label: 'Mobile Inventory',
                onTap: () {
                  // TODO: Navigate to Mobile Inventory module
                },
              ),
              const SizedBox(height: 16),
              _ModuleButton(
                icon: CupertinoIcons.chart_bar_alt_fill,
                label: 'Hospitality',
                onTap: () {
                  // TODO: Navigate to Hospitality module
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAlert(String message) {
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Missing Configuration'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}

class _ModuleButton extends StatelessWidget {
  const _ModuleButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 90,
        decoration: BoxDecoration(
          color: _primaryColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: CupertinoColors.white),
            const SizedBox(width: 14),
            Text(
              label,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
