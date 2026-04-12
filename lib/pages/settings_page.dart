import 'package:flutter/cupertino.dart';
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
      CupertinoPageRoute(builder: (_) => const QrScannerPage()),
    );
    if (result == null) return;

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

    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (context) => StatefulBuilder(
          builder: (context, setSheetState) => CupertinoPageScaffold(
            navigationBar: CupertinoNavigationBar(
              middle: const Text('API Connection'),
              leading: CupertinoButton(
                padding: EdgeInsets.zero,
                child: const Text('Cancel'),
                onPressed: () => Navigator.pop(context),
              ),
              trailing: CupertinoButton(
                padding: EdgeInsets.zero,
                child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w600)),
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
              ),
            ),
            child: SafeArea(
              child: ListView(
                children: [
                  const _SectionLabel('Used by Mobile Inventory and Hospitality'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: CupertinoSlidingSegmentedControl<ConnectionType>(
                      groupValue: selectedType,
                      children: const {
                        ConnectionType.onPremise: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Text('On-Premise'),
                        ),
                        ConnectionType.saas: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Text('SaaS'),
                        ),
                      },
                      onValueChanged: (value) {
                        if (value != null) {
                          setSheetState(() => selectedType = value);
                        }
                      },
                    ),
                  ),
                  CupertinoListSection.insetGrouped(
                    children: [
                      if (selectedType == ConnectionType.onPremise) ...[
                        CupertinoTextFormFieldRow(
                          controller: serverController,
                          prefix: const _FieldLabel('Server'),
                          placeholder: '192.168.1.100 or server.local',
                        ),
                        CupertinoTextFormFieldRow(
                          controller: portController,
                          prefix: const _FieldLabel('Port'),
                          placeholder: '7048',
                          keyboardType: TextInputType.number,
                        ),
                        CupertinoTextFormFieldRow(
                          controller: instanceController,
                          prefix: const _FieldLabel('Instance'),
                          placeholder: 'e.g. BC250',
                        ),
                      ],
                      if (selectedType == ConnectionType.saas) ...[
                        CupertinoTextFormFieldRow(
                          controller: tenantController,
                          prefix: const _FieldLabel('Tenant ID'),
                          placeholder: 'your-tenant-id.onmicrosoft.com',
                        ),
                        CupertinoTextFormFieldRow(
                          controller: clientIdController,
                          prefix: const _FieldLabel('Client ID'),
                          placeholder: 'Azure AD app client ID',
                        ),
                        CupertinoTextFormFieldRow(
                          controller: clientSecretController,
                          prefix: const _FieldLabel('Secret'),
                          placeholder: 'Azure AD app client secret',
                          obscureText: true,
                        ),
                      ],
                      CupertinoTextFormFieldRow(
                        controller: companyController,
                        prefix: const _FieldLabel('Company'),
                        placeholder: 'CRONUS International Ltd.',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showPosDialog(EnvironmentConfig? existing) {
    final usernameController = TextEditingController(text: existing?.posUsername ?? '');
    final passwordController = TextEditingController(text: existing?.posPassword ?? '');

    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (context) => CupertinoPageScaffold(
          navigationBar: CupertinoNavigationBar(
            middle: const Text('POS Login'),
            leading: CupertinoButton(
              padding: EdgeInsets.zero,
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(context),
            ),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w600)),
              onPressed: () async {
                if (_connection == null) return;

                _connection!.posUsername = usernameController.text.trim();
                _connection!.posPassword = passwordController.text.trim();

                await widget.envService.saveConnection(_connection!);
                setState(() {});
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ),
          child: SafeArea(
            child: ListView(
              children: [
                const _SectionLabel('Used by POS only'),
                CupertinoListSection.insetGrouped(
                  children: [
                    CupertinoTextFormFieldRow(
                      controller: usernameController,
                      prefix: const _FieldLabel('Username'),
                      placeholder: 'POS operator username',
                    ),
                    CupertinoTextFormFieldRow(
                      controller: passwordController,
                      prefix: const _FieldLabel('Password'),
                      placeholder: 'POS operator password',
                      obscureText: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Settings'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          child: const Icon(CupertinoIcons.qrcode_viewfinder),
          onPressed: _scanQrCode,
        ),
      ),
      child: SafeArea(
        child: ListView(
          children: [
            // --- API Connection ---
            CupertinoListSection.insetGrouped(
              header: const Text('API CONNECTION — Mobile Inventory & Hospitality'),
              children: [
                if (_connection == null)
                  CupertinoListTile(
                    leading: const Icon(CupertinoIcons.link, color: CupertinoColors.systemGrey),
                    title: const Text('No connection configured'),
                    subtitle: const Text('Tap to setup'),
                    trailing: const CupertinoListTileChevron(),
                    onTap: _editConnection,
                  )
                else ...[
                  CupertinoListTile(
                    leading: Icon(
                      _connection!.type == ConnectionType.saas
                          ? CupertinoIcons.cloud
                          : CupertinoIcons.desktopcomputer,
                    ),
                    title: Text(_connection!.displayName),
                    subtitle: Text(
                      _connection!.type == ConnectionType.saas
                          ? _connection!.tenant
                          : _connection!.serverUrl,
                    ),
                    trailing: const CupertinoListTileChevron(),
                    onTap: _editConnection,
                  ),
                  if (_connection!.type == ConnectionType.onPremise) ...[
                    _InfoTile('Port', _connection!.port.toString()),
                    if (_connection!.instance.isNotEmpty)
                      _InfoTile('Instance', _connection!.instance),
                  ],
                  if (_connection!.type == ConnectionType.saas) ...[
                    _InfoTile('Client ID', _connection!.clientId),
                    const _InfoTile('Secret', '••••••••'),
                  ],
                  if (_connection!.company.isNotEmpty)
                    _InfoTile('Company', _connection!.company),
                ],
              ],
            ),

            if (_connection != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        child: const Text('Setup Manually'),
                        onPressed: _editConnection,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        child: const Text('Scan QR Code'),
                        onPressed: _scanQrCode,
                      ),
                    ),
                    const SizedBox(width: 8),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      child: const Text(
                        'Delete',
                        style: TextStyle(color: CupertinoColors.destructiveRed),
                      ),
                      onPressed: _deleteConnection,
                    ),
                  ],
                ),
              ),

            if (_connection == null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoButton.filled(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        onPressed: _editConnection,
                        child: const Text('Setup Manually'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CupertinoButton(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        onPressed: _scanQrCode,
                        child: const Text('Scan QR Code'),
                      ),
                    ),
                  ],
                ),
              ),

            // --- Device Type ---
            CupertinoListSection.insetGrouped(
              header: const Text('DEVICE TYPE — POS Layout'),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: _connection == null
                      ? const Text(
                          'Setup a connection first',
                          style: TextStyle(color: CupertinoColors.systemGrey),
                        )
                      : CupertinoSlidingSegmentedControl<DeviceType>(
                          groupValue: _connection!.deviceType,
                          children: const {
                            DeviceType.phone: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Text('Phone'),
                            ),
                            DeviceType.tablet: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Text('Tablet'),
                            ),
                          },
                          onValueChanged: (value) async {
                            if (value == null || _connection == null) return;
                            _connection!.deviceType = value;
                            await widget.envService.saveConnection(_connection!);
                            setState(() {});
                          },
                        ),
                ),
              ],
            ),

            // --- POS Login ---
            CupertinoListSection.insetGrouped(
              header: const Text('POS LOGIN — POS Only'),
              children: [
                if (_connection == null)
                  const CupertinoListTile(
                    title: Text(
                      'Setup a connection first',
                      style: TextStyle(color: CupertinoColors.systemGrey),
                    ),
                  )
                else ...[
                  CupertinoListTile(
                    leading: const Icon(CupertinoIcons.person),
                    title: Text(
                      _connection!.posUsername.isNotEmpty
                          ? _connection!.posUsername
                          : 'Not configured',
                    ),
                    subtitle: _connection!.posUsername.isNotEmpty
                        ? const Text('Password: ••••••••')
                        : const Text('Tap to configure'),
                    trailing: const CupertinoListTileChevron(),
                    onTap: _editPosCredentials,
                  ),
                ],
              ],
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          color: CupertinoColors.systemGrey,
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      child: Text(text),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  const _InfoTile(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      title: Text(label),
      additionalInfo: Text(value),
    );
  }
}
