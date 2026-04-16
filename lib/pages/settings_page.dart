import 'package:flutter/cupertino.dart';
import '../models/environment_config.dart';
import '../services/environment_service.dart';
import 'qr_scanner_page.dart';

const Color _primaryColor = Color(0xFF003366);

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

  void _deleteConnection() async {
    await widget.envService.deleteConnection();
    setState(() => _connection = null);
  }

  void _showConnectionDialog() {
    var selectedType = _connection?.type ?? ConnectionType.onPremise;
    final serverController = TextEditingController(text: _connection?.serverUrl ?? '');
    final instanceController = TextEditingController(text: _connection?.instance ?? '');
    final portController = TextEditingController(text: _connection?.port.toString() ?? '7048');
    final tenantController = TextEditingController(text: _connection?.tenant ?? '');
    final clientIdController = TextEditingController(text: _connection?.clientId ?? '');
    final clientSecretController = TextEditingController(text: _connection?.clientSecret ?? '');
    final companyController = TextEditingController(text: _connection?.company ?? '');
    final companyNameController = TextEditingController(text: _connection?.companyName ?? '');

    showCupertinoModalPopup(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => _Sheet(
          title: 'API Connection',
          onSave: () async {
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
              companyName: companyNameController.text.trim(),
              posUsername: _connection?.posUsername ?? '',
              posPassword: _connection?.posPassword ?? '',
              deviceType: _connection?.deviceType ?? DeviceType.phone,
            );
            await widget.envService.saveConnection(config);
            setState(() => _connection = config);
            if (context.mounted) Navigator.pop(context);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Used by Mobile Inventory & Hospitality',
                  style: TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)),
              const SizedBox(height: 12),
              CupertinoSlidingSegmentedControl<ConnectionType>(
                groupValue: selectedType,
                children: const {
                  ConnectionType.onPremise: Text('On-Premise'),
                  ConnectionType.saas: Text('SaaS'),
                },
                onValueChanged: (v) {
                  if (v != null) setDialogState(() => selectedType = v);
                },
              ),
              const SizedBox(height: 16),
              if (selectedType == ConnectionType.onPremise) ...[
                _Field(controller: serverController, placeholder: 'Server Address'),
                _Field(controller: portController, placeholder: 'Port', keyboard: TextInputType.number),
                _Field(controller: instanceController, placeholder: 'Server Instance'),
                _Field(controller: companyController, placeholder: 'Company'),
              ],
              if (selectedType == ConnectionType.saas) ...[
                _Field(controller: tenantController, placeholder: 'Tenant ID'),
                _Field(controller: clientIdController, placeholder: 'Client ID'),
                _Field(controller: clientSecretController, placeholder: 'Client Secret', obscure: true),
                _Field(controller: companyController, placeholder: 'Environment'),
                _Field(controller: companyNameController, placeholder: 'Company'),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showMobileInventoryDialog() {
    final storeNoController = TextEditingController(text: _connection?.storeNo ?? '');

    showCupertinoModalPopup(
      context: context,
      builder: (context) => _Sheet(
        title: 'Mobile Inventory',
        onSave: () async {
          if (_connection == null) return;
          _connection!.storeNo = storeNoController.text.trim();
          await widget.envService.saveConnection(_connection!);
          setState(() {});
          if (context.mounted) Navigator.pop(context);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Used for Mobile Inventory data replication',
                style: TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)),
            const SizedBox(height: 12),
            _Field(controller: storeNoController, placeholder: 'Store No.'),
          ],
        ),
      ),
    );
  }

  void _showSoftPayDialog() {
    final integratorIdController =
        TextEditingController(text: _connection?.softPayIntegratorId ?? '');
    final credentialsController =
        TextEditingController(text: _connection?.softPayCredentials ?? '');

    showCupertinoModalPopup(
      context: context,
      builder: (context) => _Sheet(
        title: 'SoftPay',
        onSave: () async {
          if (_connection == null) return;
          _connection!.softPayIntegratorId = integratorIdController.text.trim();
          _connection!.softPayCredentials = credentialsController.text.trim();
          await widget.envService.saveConnection(_connection!);
          setState(() {});
          if (context.mounted) Navigator.pop(context);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('SoftPay payment terminal credentials',
                style: TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)),
            const SizedBox(height: 12),
            _Field(controller: integratorIdController, placeholder: 'Integrator ID'),
            _Field(controller: credentialsController, placeholder: 'Credentials', obscure: true),
          ],
        ),
      ),
    );
  }

  void _showPosDialog() {
    final usernameController = TextEditingController(text: _connection?.posUsername ?? '');
    final passwordController = TextEditingController(text: _connection?.posPassword ?? '');

    showCupertinoModalPopup(
      context: context,
      builder: (context) => _Sheet(
        title: 'POS Login',
        onSave: () async {
          if (_connection == null) return;
          _connection!.posUsername = usernameController.text.trim();
          _connection!.posPassword = passwordController.text.trim();
          await widget.envService.saveConnection(_connection!);
          setState(() {});
          if (context.mounted) Navigator.pop(context);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Used by POS only',
                style: TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)),
            const SizedBox(height: 12),
            _Field(controller: usernameController, placeholder: 'Username'),
            _Field(controller: passwordController, placeholder: 'Password', obscure: true),
          ],
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
          padding: const EdgeInsets.all(20),
          children: [
            // --- API Connection ---
            _SectionTitle('API Connection', 'Mobile Inventory & Hospitality'),
            const SizedBox(height: 8),
            if (_connection == null)
              _Card(
                child: Column(
                  children: [
                    const Icon(CupertinoIcons.link, size: 40, color: CupertinoColors.systemGrey),
                    const SizedBox(height: 8),
                    const Text('No connection configured',
                        style: TextStyle(color: CupertinoColors.systemGrey)),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: CupertinoButton.filled(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            onPressed: _showConnectionDialog,
                            child: const Text('Setup Manually', style: TextStyle(fontSize: 14)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: CupertinoButton(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            onPressed: _scanQrCode,
                            child: const Text('Scan QR Code', style: TextStyle(fontSize: 14)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _connection!.type == ConnectionType.saas
                              ? CupertinoIcons.cloud
                              : CupertinoIcons.desktopcomputer,
                          color: _primaryColor,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(_connection!.displayName,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minSize: 0,
                          onPressed: _showConnectionDialog,
                          child: const Icon(CupertinoIcons.pencil, size: 20),
                        ),
                        const SizedBox(width: 12),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minSize: 0,
                          onPressed: _deleteConnection,
                          child: const Icon(CupertinoIcons.trash, size: 20, color: CupertinoColors.destructiveRed),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_connection!.type == ConnectionType.onPremise) ...[
                      _DetailText('${_connection!.serverUrl}:${_connection!.port}'),
                      if (_connection!.instance.isNotEmpty) _DetailText('Instance: ${_connection!.instance}'),
                    ],
                    if (_connection!.type == ConnectionType.saas) ...[
                      _DetailText(_connection!.tenant),
                      _DetailText('Client ID: ${_connection!.clientId}'),
                      if (_connection!.company.isNotEmpty) _DetailText('Environment: ${_connection!.company}'),
                      if (_connection!.companyName.isNotEmpty) _DetailText('Company: ${_connection!.companyName}'),
                    ],
                    if (_connection!.type == ConnectionType.onPremise &&
                        _connection!.company.isNotEmpty)
                      _DetailText('Company: ${_connection!.company}'),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            // --- Device Type ---
            _SectionTitle('Device Type', 'POS layout'),
            const SizedBox(height: 8),
            _Card(
              child: _connection == null
                  ? const Text('Setup a connection first',
                      style: TextStyle(color: CupertinoColors.systemGrey))
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

            const SizedBox(height: 24),

            // --- Mobile Inventory ---
            _SectionTitle('Mobile Inventory', 'Store No.'),
            const SizedBox(height: 8),
            if (_connection == null)
              _Card(
                child: const Text('Setup a connection first',
                    style: TextStyle(color: CupertinoColors.systemGrey)),
              )
            else
              GestureDetector(
                onTap: _showMobileInventoryDialog,
                child: _Card(
                  child: Row(
                    children: [
                      const Icon(CupertinoIcons.cube_box, color: _primaryColor, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        _connection!.storeNo.isNotEmpty
                            ? 'Store No.: ${_connection!.storeNo}'
                            : 'Not configured — tap to setup',
                        style: TextStyle(
                          color: _connection!.storeNo.isNotEmpty ? null : CupertinoColors.systemGrey,
                        ),
                      ),
                      const Spacer(),
                      const Icon(CupertinoIcons.chevron_forward, size: 16, color: CupertinoColors.systemGrey3),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // --- SoftPay ---
            _SectionTitle('SoftPay', 'Payment terminal'),
            const SizedBox(height: 8),
            if (_connection == null)
              _Card(
                child: const Text('Setup a connection first',
                    style: TextStyle(color: CupertinoColors.systemGrey)),
              )
            else
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(CupertinoIcons.creditcard, color: _primaryColor, size: 20),
                        const SizedBox(width: 10),
                        const Text('Enable SoftPay'),
                        const Spacer(),
                        CupertinoSwitch(
                          value: _connection!.softPayEnabled,
                          activeTrackColor: _primaryColor,
                          onChanged: (value) async {
                            _connection!.softPayEnabled = value;
                            await widget.envService.saveConnection(_connection!);
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                    if (_connection!.softPayEnabled) ...[
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: _showSoftPayDialog,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_connection!.softPayIntegratorId.isNotEmpty) ...[
                              _DetailText('Integrator ID: ${_connection!.softPayIntegratorId}'),
                              const _DetailText('Credentials: ••••••••'),
                            ] else
                              const Text('Tap to configure Integrator ID & Credentials',
                                  style: TextStyle(color: CupertinoColors.systemGrey, fontSize: 13)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Spacer(),
                                const Icon(CupertinoIcons.chevron_forward,
                                    size: 16, color: CupertinoColors.systemGrey3),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

            const SizedBox(height: 24),

            // --- POS Login ---
            _SectionTitle('POS Login', 'POS only'),
            const SizedBox(height: 8),
            if (_connection == null)
              _Card(
                child: const Text('Setup a connection first',
                    style: TextStyle(color: CupertinoColors.systemGrey)),
              )
            else
              GestureDetector(
                onTap: _showPosDialog,
                child: _Card(
                  child: Row(
                    children: [
                      const Icon(CupertinoIcons.person, color: _primaryColor, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        _connection!.posUsername.isNotEmpty
                            ? '${_connection!.posUsername}  ••••••••'
                            : 'Not configured — tap to setup',
                        style: TextStyle(
                          color: _connection!.posUsername.isNotEmpty ? null : CupertinoColors.systemGrey,
                        ),
                      ),
                      const Spacer(),
                      const Icon(CupertinoIcons.chevron_forward, size: 16, color: CupertinoColors.systemGrey3),
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

// --- Shared widgets ---

class _SectionTitle extends StatelessWidget {
  final String title;
  final String badge;
  const _SectionTitle(this.title, this.badge);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: CupertinoColors.systemGrey5,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(badge, style: const TextStyle(fontSize: 11, color: CupertinoColors.systemGrey)),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CupertinoColors.systemGrey5),
      ),
      child: child,
    );
  }
}

class _DetailText extends StatelessWidget {
  final String text;
  const _DetailText(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(text, style: const TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)),
    );
  }
}

class _Sheet extends StatelessWidget {
  final String title;
  final VoidCallback onSave;
  final Widget child;

  const _Sheet({required this.title, required this.onSave, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: CupertinoColors.systemBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey4,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      child: const Text('Cancel'),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: onSave,
                      child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String placeholder;
  final bool obscure;
  final TextInputType? keyboard;

  const _Field({
    required this.controller,
    required this.placeholder,
    this.obscure = false,
    this.keyboard,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CupertinoTextField(
        controller: controller,
        placeholder: placeholder,
        obscureText: obscure,
        keyboardType: keyboard,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: CupertinoColors.systemGrey6,
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}
