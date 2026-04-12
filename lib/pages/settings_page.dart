import 'package:flutter/material.dart';
import '../models/environment_config.dart';
import '../services/environment_service.dart';
import 'qr_scanner_page.dart';

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

  void _editConnection() {
    _showConnectionDialog(_connection);
  }

  void _editPosCredentials() {
    _showPosDialog(_connection);
  }

  void _deleteConnection() async {
    await widget.envService.deleteConnection();
    setState(() => _connection = null);
  }

  void _scanQrCode() async {
    final result = await Navigator.push<EnvironmentConfig>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerPage()),
    );
    if (result == null) return;

    // Preserve existing POS credentials if present
    if (_connection != null) {
      result.posUsername = _connection!.posUsername;
      result.posPassword = _connection!.posPassword;
    }

    await widget.envService.saveConnection(result);
    setState(() => _connection = result);
  }

  void _showConnectionDialog(EnvironmentConfig? existing) {
    var selectedType = existing?.type ?? ConnectionType.onPremise;
    final serverController = TextEditingController(text: existing?.serverUrl ?? '');
    final instanceController = TextEditingController(text: existing?.instance ?? '');
    final portController = TextEditingController(
      text: existing?.port.toString() ?? '7048',
    );
    final tenantController = TextEditingController(text: existing?.tenant ?? '');
    final clientIdController = TextEditingController(text: existing?.clientId ?? '');
    final clientSecretController = TextEditingController(text: existing?.clientSecret ?? '');
    final companyController = TextEditingController(text: existing?.company ?? '');

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('API Connection'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Used by Mobile Inventory and Hospitality',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
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
                    controller: tenantController,
                    decoration: const InputDecoration(
                      labelText: 'Tenant ID',
                      hintText: 'e.g. your-tenant-id.onmicrosoft.com',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: clientIdController,
                    decoration: const InputDecoration(
                      labelText: 'Client ID',
                      hintText: 'Azure AD app client ID',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: clientSecretController,
                    decoration: const InputDecoration(
                      labelText: 'Client Secret',
                      hintText: 'Azure AD app client secret',
                    ),
                    obscureText: true,
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
                if (selectedType == ConnectionType.onPremise) {
                  if (serverController.text.trim().isEmpty) return;
                } else {
                  if (tenantController.text.trim().isEmpty ||
                      clientIdController.text.trim().isEmpty ||
                      clientSecretController.text.trim().isEmpty) return;
                }

                final config = EnvironmentConfig(
                  type: selectedType,
                  serverUrl: serverController.text.trim(),
                  instance: instanceController.text.trim(),
                  port: int.tryParse(portController.text.trim()) ?? 7048,
                  tenant: tenantController.text.trim(),
                  clientId: clientIdController.text.trim(),
                  clientSecret: clientSecretController.text.trim(),
                  company: companyController.text.trim(),
                  posUsername: existing?.posUsername ?? '',
                  posPassword: existing?.posPassword ?? '',
                  deviceType: existing?.deviceType ?? DeviceType.phone,
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

  void _showPosDialog(EnvironmentConfig? existing) {
    final usernameController = TextEditingController(text: existing?.posUsername ?? '');
    final passwordController = TextEditingController(text: existing?.posPassword ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('POS Login'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Used by POS only',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  hintText: 'POS operator username',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  hintText: 'POS operator password',
                ),
                obscureText: true,
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
              if (_connection == null) return;

              _connection!.posUsername = usernameController.text.trim();
              _connection!.posPassword = passwordController.text.trim();

              await widget.envService.saveConnection(_connection!);
              setState(() {});
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan QR Code',
            onPressed: _scanQrCode,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- API Connection section ---
          _SectionHeader(
            icon: Icons.api,
            title: 'API Connection',
            subtitle: 'Mobile Inventory & Hospitality',
          ),
          const SizedBox(height: 8),
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
                      onPressed: _editConnection,
                      icon: const Icon(Icons.add),
                      label: const Text('Setup Manually'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _scanQrCode,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan QR Code'),
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.colorScheme.primary, width: 2),
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
                          color: theme.colorScheme.primary,
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
                          onPressed: _editConnection,
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: _deleteConnection,
                        ),
                      ],
                    ),
                    const Divider(),
                    if (_connection!.type == ConnectionType.onPremise) ...[
                      _DetailRow('Server', _connection!.serverUrl),
                      _DetailRow('Port', _connection!.port.toString()),
                      if (_connection!.instance.isNotEmpty)
                        _DetailRow('Instance', _connection!.instance),
                    ],
                    if (_connection!.type == ConnectionType.saas) ...[
                      _DetailRow('Tenant', _connection!.tenant),
                      _DetailRow('Client ID', _connection!.clientId),
                      const _DetailRow('Secret', '••••••••'),
                    ],
                    if (_connection!.company.isNotEmpty)
                      _DetailRow('Company', _connection!.company),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 24),

          // --- Device Type section ---
          _SectionHeader(
            icon: Icons.devices,
            title: 'Device Type',
            subtitle: 'POS layout',
          ),
          const SizedBox(height: 8),
          if (_connection == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Setup an API connection first',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
              ),
            )
          else
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.colorScheme.primary, width: 2),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SegmentedButton<DeviceType>(
                  segments: const [
                    ButtonSegment(
                      value: DeviceType.phone,
                      label: Text('Phone'),
                      icon: Icon(Icons.smartphone),
                    ),
                    ButtonSegment(
                      value: DeviceType.tablet,
                      label: Text('Tablet'),
                      icon: Icon(Icons.tablet),
                    ),
                  ],
                  selected: {_connection!.deviceType},
                  onSelectionChanged: (selection) async {
                    _connection!.deviceType = selection.first;
                    await widget.envService.saveConnection(_connection!);
                    setState(() {});
                  },
                ),
              ),
            ),

          const SizedBox(height: 24),

          // --- POS Login section ---
          _SectionHeader(
            icon: Icons.point_of_sale,
            title: 'POS Login',
            subtitle: 'POS only',
          ),
          const SizedBox(height: 8),
          if (_connection == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Setup an API connection first',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
              ),
            )
          else
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: _connection!.posUsername.isNotEmpty
                    ? BorderSide(color: theme.colorScheme.primary, width: 2)
                    : BorderSide.none,
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.person, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          _connection!.posUsername.isNotEmpty
                              ? _connection!.posUsername
                              : 'Not configured',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _connection!.posUsername.isNotEmpty
                                ? null
                                : Colors.grey,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: _editPosCredentials,
                        ),
                      ],
                    ),
                    if (_connection!.posUsername.isNotEmpty) ...[
                      const Divider(),
                      _DetailRow('Username', _connection!.posUsername),
                      const _DetailRow('Password', '••••••••'),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[700]),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ),
      ],
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
