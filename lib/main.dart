import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pages/settings_page.dart';
import 'services/environment_service.dart';

late EnvironmentService environmentService;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  environmentService = EnvironmentService(prefs);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RTS - LS Central',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF003366)),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final connection = environmentService.getConnection();

    return Scaffold(
      appBar: AppBar(
        title: const Text('LS Central'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsPage(envService: environmentService),
                ),
              );
              (context as Element).markNeedsBuild();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (connection != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  '${connection.displayName}: ${connection.serverUrl}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            if (connection == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  'No connection configured — tap the settings icon',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.orange[700]),
                ),
              ),
            _ModuleButton(
              icon: Icons.point_of_sale,
              label: 'POS',
              onTap: () {
                // TODO: Navigate to POS module
              },
            ),
            const SizedBox(height: 20),
            _ModuleButton(
              icon: Icons.inventory_2,
              label: 'Mobile Inventory',
              onTap: () {
                // TODO: Navigate to Mobile Inventory module
              },
            ),
            const SizedBox(height: 20),
            _ModuleButton(
              icon: Icons.restaurant_menu,
              label: 'Hospitality',
              onTap: () {
                // TODO: Navigate to Hospitality module
              },
            ),
          ],
        ),
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
    return SizedBox(
      height: 100,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 36),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
