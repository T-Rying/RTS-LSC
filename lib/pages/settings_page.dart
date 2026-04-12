import 'package:flutter/material.dart';
import '../models/environment_config.dart';
import '../services/environment_service.dart';

class SettingsPage extends StatefulWidget {
  final EnvironmentService envService;

  const SettingsPage({super.key, required this.envService});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  EnvironmentConfig? _connection;

  @override
  void initState() {
    super.initState();
    _connection = widget.envService.getConnection();
  }

  void _configureConnection() {
    _showConnectionDialog(_connection);
  }

  void _deleteConnection() async {
    await widget.envService.deleteConnection();
    setState(() => _connection = null);
  }

  void _showConnectionDialog(EnvironmentConfig? existing) {
    var selectedType = existing?.type ?? ConnectionType.onPremise;
    final serverController = TextEditingController(text: existing?.serverUrl ?? '');
    final instanceController = TextEditingController(text: existing?.instance ?? '');
    final tenantController = TextEditingController(text: existing?.tenant ?? '');
    final companyController = TextEditingController(text: existing?.company ?? '');
    final portController = TextEditingController(
      text: existing?.port.toString() ?? '7048',
    );

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing != null ? 'Edit Connection' : 'New Connection'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<ConnectionType>(
                  segments: const [
                    ButtonSegment(
                      value: ConnectionType.onPremise,
                      label: Text('On-Premise'),
                      icon: Icon(Icons.dns),
                    ),
                    ButtonSegment(
                      value: ConnectionType.saas,
                      label: Text('SaaS'),
                      icon: Icon(Icons.cloud),
                    ),
                  ],
                  selected: {selectedType},
                  onSelectionChanged: (selection) {
                    setDialogState(() => selectedType = selection.first);
                  },
                ),
                const SizedBox(height: 16),
                if (selectedType == ConnectionType.onPremise) ...[
                  TextField(
                    controller: serverController,
                    decoration: const InputDecoration(
                      labelText: 'Server Address',
                      hintText: 'e.g. 192.168.1.100 or server.local',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: portController,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      hintText: '7048',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: instanceController,
                    decoration: const InputDecoration(
                      labelText: 'Server Instance',
                      hintText: 'e.g. BC250',
                    ),
                  ),
                ],
                if (selectedType == ConnectionType.saas) ...[
                  TextField(
                    controller: serverController,
                    decoration: const InputDecoration(
                      labelText: 'Environment URL',
                      hintText: 'https://businesscentral.dynamics.com',
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: tenantController,
                    decoration: const InputDecoration(
                      labelText: 'Tenant ID',
                      hintText: 'e.g. your-tenant-id.onmicrosoft.com',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: companyController,
                  decoration: const InputDecoration(
                    labelText: 'Company',
                    hintText: 'e.g. CRONUS International Ltd.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final server = serverController.text.trim();
                if (server.isEmpty) return;

                final config = EnvironmentConfig(
                  type: selectedType,
                  serverUrl: server,
                  instance: instanceController.text.trim(),
                  tenant: tenantController.text.trim(),
                  company: companyController.text.trim(),
                  port: int.tryParse(portController.text.trim()) ?? 7048,
                );

                await widget.envService.saveConnection(config);
                setState(() => _connection = config);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Connection',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            if (_connection == null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Icon(Icons.link_off, size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text(
                        'No connection configured',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _configureConnection,
                        icon: const Icon(Icons.add),
                        label: const Text('Setup Connection'),
                      ),
                    ],
                  ),
                ),
              )
            else
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _connection!.type == ConnectionType.saas
                                ? Icons.cloud
                                : Icons.dns,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _connection!.displayName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: _configureConnection,
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: _deleteConnection,
                          ),
                        ],
                      ),
                      const Divider(),
                      _DetailRow('Server', _connection!.serverUrl),
                      if (_connection!.type == ConnectionType.onPremise) ...[
                        _DetailRow('Port', _connection!.port.toString()),
                        if (_connection!.instance.isNotEmpty)
                          _DetailRow('Instance', _connection!.instance),
                      ],
                      if (_connection!.type == ConnectionType.saas &&
                          _connection!.tenant.isNotEmpty)
                        _DetailRow('Tenant', _connection!.tenant),
                      if (_connection!.company.isNotEmpty)
                        _DetailRow('Company', _connection!.company),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
