import 'dart:async';

import 'package:flutter/cupertino.dart';
import '../models/environment_config.dart';
import '../services/environment_service.dart';
import '../services/payment/adyen_provider.dart';
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

  // Adyen boarding probe state — driven by `_showAdyenBoardingResult` /
  // `_checkAdyenBoardingStatus` below. Only populated after the user taps
  // "Check boarding status" in the Adyen credentials sheet.
  bool _adyenCheckingBoarding = false;
  bool _adyenCompletingBoarding = false;
  String? _adyenBoardingStatus; // human-readable, e.g. "Boarded: ID=..." or "Not boarded"
  String? _adyenBoardingError;

  /// Mirror of the cached Adyen state so the "Complete boarding" button
  /// survives app restarts: populated in initState from the provider's
  /// SharedPreferences cache, refreshed after each Check / Complete.
  bool _adyenHasBoardingToken = false;
  bool _adyenIsBoarded = false;

  @override
  void initState() {
    super.initState();
    _connection = widget.envService.getConnection();
    _loadCachedAdyenBoardingState();
  }

  Future<void> _loadCachedAdyenBoardingState() async {
    final conn = _connection;
    if (conn == null) return;
    if (conn.adyenMerchantAccount.isEmpty || conn.adyenStoreId.isEmpty) return;
    final provider = AdyenProvider(conn);
    final ok = await provider.initialize();
    if (!ok || !mounted) return;
    setState(() {
      _adyenIsBoarded = provider.isBoarded;
      _adyenHasBoardingToken = provider.lastBoardingRequestToken.isNotEmpty;
      if (_adyenIsBoarded && _adyenBoardingStatus == null) {
        _adyenBoardingStatus =
            'Boarded (installationId: ${provider.installationId})';
      } else if (_adyenHasBoardingToken && _adyenBoardingStatus == null) {
        _adyenBoardingStatus = 'Boarding token cached — tap '
            '"Complete boarding" to finish pairing this device.';
      }
    });
  }

  /// Launch the Adyen /boarded App Link probe and update the UI with the
  /// result. Safe to call repeatedly. If the Adyen Payments Test app isn't
  /// installed, the error banner will point the user at the install step.
  Future<void> _checkAdyenBoardingStatus() async {
    final conn = _connection;
    if (conn == null) return;

    setState(() {
      _adyenCheckingBoarding = true;
      _adyenBoardingStatus = null;
      _adyenBoardingError = null;
    });

    try {
      final provider = AdyenProvider(conn);
      final ok = await provider.initialize();
      if (!ok) {
        setState(() {
          _adyenCheckingBoarding = false;
          _adyenBoardingError = 'Cannot run probe — fill in Merchant account '
              'and Store ID first.';
        });
        return;
      }
      final boarded = await provider.checkBoardingStatus();
      setState(() {
        _adyenCheckingBoarding = false;
        _adyenIsBoarded = boarded;
        _adyenHasBoardingToken =
            provider.lastBoardingRequestToken.isNotEmpty;
        _adyenBoardingStatus = boarded
            ? 'Boarded (installationId: ${provider.installationId})'
            : _adyenHasBoardingToken
                ? 'Not boarded yet — boardingRequestToken received. Tap '
                    '"Complete boarding" to finish pairing this device.'
                : 'Not boarded yet and no boardingRequestToken returned. '
                    'Check that the Adyen Payments app role is enabled on '
                    'your API key.';
      });
    } on TimeoutException {
      setState(() {
        _adyenCheckingBoarding = false;
        _adyenBoardingError = 'Timed out waiting for the Adyen app to return. '
            'Make sure the Adyen Payments Test app is installed and able to '
            'open https://www.adyen.com/test/... links.';
      });
    } on StateError catch (e) {
      setState(() {
        _adyenCheckingBoarding = false;
        _adyenBoardingError = e.message;
      });
    } catch (e) {
      setState(() {
        _adyenCheckingBoarding = false;
        _adyenBoardingError = 'Probe failed: $e';
      });
    }
  }

  /// Launch the Adyen /board App Link with the cached boardingRequestToken
  /// to finish pairing this device with the merchant account. Only useful
  /// after a /boarded probe has returned a token.
  Future<void> _completeAdyenBoarding() async {
    final conn = _connection;
    if (conn == null) return;

    setState(() {
      _adyenCompletingBoarding = true;
      _adyenBoardingStatus = null;
      _adyenBoardingError = null;
    });

    try {
      final provider = AdyenProvider(conn);
      final ok = await provider.initialize();
      if (!ok) {
        setState(() {
          _adyenCompletingBoarding = false;
          _adyenBoardingError = 'Cannot complete boarding — fill in Merchant '
              'account and Store ID first.';
        });
        return;
      }
      final boarded = await provider.completeBoarding();
      setState(() {
        _adyenCompletingBoarding = false;
        _adyenIsBoarded = boarded;
        _adyenHasBoardingToken =
            provider.lastBoardingRequestToken.isNotEmpty;
        _adyenBoardingStatus = boarded
            ? 'Boarded (installationId: ${provider.installationId})'
            : 'Boarding did not complete. The Adyen app returned '
                'boarded=false — re-run "Check boarding status" to get a '
                'fresh token and try again.';
      });
    } on TimeoutException {
      setState(() {
        _adyenCompletingBoarding = false;
        _adyenBoardingError = 'Timed out waiting for the Adyen app to return. '
            'Make sure the Adyen Payments Test app is installed and able to '
            'open https://www.adyen.com/test/... links.';
      });
    } on StateError catch (e) {
      setState(() {
        _adyenCompletingBoarding = false;
        _adyenBoardingError = e.message;
      });
    } catch (e) {
      setState(() {
        _adyenCompletingBoarding = false;
        _adyenBoardingError = 'Complete boarding failed: $e';
      });
    }
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

  void _showAdyenDialog() {
    final merchantController =
        TextEditingController(text: _connection?.adyenMerchantAccount ?? '');
    final apiKeyController =
        TextEditingController(text: _connection?.adyenApiKey ?? '');
    final sharedKeyController =
        TextEditingController(text: _connection?.adyenSharedKey ?? '');
    final storeIdController =
        TextEditingController(text: _connection?.adyenStoreId ?? '');
    final terminalIdController =
        TextEditingController(text: _connection?.adyenTerminalId ?? '');
    final keyIdentifierController =
        TextEditingController(text: _connection?.adyenKeyIdentifier ?? '');
    final keyVersionController = TextEditingController(
        text: (_connection?.adyenKeyVersion ?? 0) > 0
            ? '${_connection!.adyenKeyVersion}'
            : '');
    final saleIdController =
        TextEditingController(text: _connection?.adyenSaleId ?? 'RTS-LSC');
    var testMode = _connection?.adyenTestMode ?? true;

    showCupertinoModalPopup(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => _Sheet(
          title: 'Adyen',
          onSave: () async {
            if (_connection == null) return;
            _connection!.adyenMerchantAccount = merchantController.text.trim();
            _connection!.adyenApiKey = apiKeyController.text.trim();
            _connection!.adyenSharedKey = sharedKeyController.text.trim();
            _connection!.adyenStoreId = storeIdController.text.trim();
            _connection!.adyenTerminalId = terminalIdController.text.trim();
            _connection!.adyenKeyIdentifier =
                keyIdentifierController.text.trim();
            _connection!.adyenKeyVersion =
                int.tryParse(keyVersionController.text.trim()) ?? 0;
            final enteredSaleId = saleIdController.text.trim();
            _connection!.adyenSaleId =
                enteredSaleId.isEmpty ? 'RTS-LSC' : enteredSaleId;
            _connection!.adyenTestMode = testMode;
            await widget.envService.saveConnection(_connection!);
            setState(() {});
            if (context.mounted) Navigator.pop(context);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                  'Adyen Android Payments app credentials. '
                  'Obtain these from your Adyen Customer Area.',
                  style: TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Test environment'),
                  const Spacer(),
                  CupertinoSwitch(
                    value: testMode,
                    activeTrackColor: _primaryColor,
                    onChanged: (v) => setDialogState(() => testMode = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const SizedBox(height: 4),
              const Text('Account',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.systemGrey)),
              _Field(controller: merchantController, placeholder: 'Merchant account'),
              _Field(controller: apiKeyController, placeholder: 'API key', obscure: true),
              _Field(controller: storeIdController, placeholder: 'Store ID'),
              _Field(controller: terminalIdController, placeholder: 'Terminal ID (POI ID)'),
              const SizedBox(height: 10),
              const Text('NEXO shared secret (Phase C)',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.systemGrey)),
              const Text(
                  'From Customer Area → In-person payments → Terminal API keys '
                  '→ your shared secret. All three are needed for /nexo '
                  'transactions.',
                  style: TextStyle(
                      fontSize: 11,
                      color: CupertinoColors.systemGrey)),
              const SizedBox(height: 4),
              _Field(
                  controller: sharedKeyController,
                  placeholder: 'Passphrase (shared secret value)',
                  obscure: true),
              _Field(
                  controller: keyIdentifierController,
                  placeholder: 'Key identifier (e.g. "this")'),
              _Field(
                  controller: keyVersionController,
                  placeholder: 'Key version (number)'),
              const SizedBox(height: 10),
              const Text('POS identity',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.systemGrey)),
              _Field(
                  controller: saleIdController,
                  placeholder: 'Sale system ID (default RTS-LSC)'),
            ],
          ),
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

            // --- Payment Provider ---
            _SectionTitle('Payment Provider', 'Card payment integration'),
            const SizedBox(height: 8),
            if (_connection == null)
              _Card(
                child: const Text('Setup a connection first',
                    style: TextStyle(color: CupertinoColors.systemGrey)),
              )
            else
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: const [
                        Icon(CupertinoIcons.creditcard,
                            color: _primaryColor, size: 20),
                        SizedBox(width: 10),
                        Text('Provider'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    CupertinoSlidingSegmentedControl<PaymentProviderType>(
                      groupValue: _connection!.paymentProvider,
                      children: const {
                        PaymentProviderType.none: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Text('None'),
                        ),
                        PaymentProviderType.softpay: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Text('SoftPay'),
                        ),
                        PaymentProviderType.adyen: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Text('Adyen'),
                        ),
                      },
                      onValueChanged: (value) async {
                        if (value == null) return;
                        _connection!.paymentProvider = value;
                        await widget.envService.saveConnection(_connection!);
                        setState(() {});
                      },
                    ),
                    if (_connection!.paymentProvider ==
                        PaymentProviderType.softpay) ...[
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: _showSoftPayDialog,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_connection!.softPayIntegratorId.isNotEmpty) ...[
                              _DetailText(
                                  'Integrator ID: ${_connection!.softPayIntegratorId}'),
                              const _DetailText('Credentials: ••••••••'),
                            ] else
                              const Text(
                                  'Tap to configure Integrator ID & Credentials',
                                  style: TextStyle(
                                      color: CupertinoColors.systemGrey,
                                      fontSize: 13)),
                            const SizedBox(height: 8),
                            Row(
                              children: const [
                                Spacer(),
                                Icon(CupertinoIcons.chevron_forward,
                                    size: 16, color: CupertinoColors.systemGrey3),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ] else if (_connection!.paymentProvider ==
                        PaymentProviderType.adyen) ...[
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: _showAdyenDialog,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_connection!.adyenMerchantAccount.isNotEmpty) ...[
                              _DetailText('Merchant: ${_connection!.adyenMerchantAccount}'),
                              _DetailText('Store: ${_connection!.adyenStoreId}'),
                              if (_connection!.adyenTerminalId.isNotEmpty)
                                _DetailText('Terminal: ${_connection!.adyenTerminalId}')
                              else
                                const _DetailText(
                                    'Terminal: (assigned after boarding)'),
                              _DetailText(
                                  'Environment: ${_connection!.adyenTestMode ? "Test" : "Production"}'),
                              const _DetailText('API Key: ••••••••'),
                              const _DetailText('Shared Key: ••••••••'),
                            ] else
                              const Text(
                                  'Tap to configure Adyen credentials',
                                  style: TextStyle(
                                      color: CupertinoColors.systemGrey,
                                      fontSize: 13)),
                            const SizedBox(height: 8),
                            Row(
                              children: const [
                                Spacer(),
                                Icon(CupertinoIcons.chevron_forward,
                                    size: 16, color: CupertinoColors.systemGrey3),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      // Boarding status + "Check" button — only useful once
                      // at least the merchant account & store ID are set.
                      if (_connection!.adyenMerchantAccount.isNotEmpty &&
                          _connection!.adyenStoreId.isNotEmpty) ...[
                        Row(
                          children: [
                            const Icon(CupertinoIcons.checkmark_shield,
                                color: _primaryColor, size: 18),
                            const SizedBox(width: 8),
                            const Text('Boarding status',
                                style: TextStyle(fontWeight: FontWeight.w500)),
                            const Spacer(),
                            CupertinoButton(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              color: _primaryColor,
                              onPressed: _adyenCheckingBoarding
                                  ? null
                                  : _checkAdyenBoardingStatus,
                              child: _adyenCheckingBoarding
                                  ? const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CupertinoActivityIndicator(
                                            color: CupertinoColors.white),
                                        SizedBox(width: 8),
                                        Text('Checking…',
                                            style: TextStyle(
                                                color: CupertinoColors.white)),
                                      ],
                                    )
                                  : const Text('Check',
                                      style: TextStyle(
                                          color: CupertinoColors.white)),
                            ),
                          ],
                        ),
                        if (_adyenHasBoardingToken && !_adyenIsBoarded) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(CupertinoIcons.link,
                                  color: _primaryColor, size: 18),
                              const SizedBox(width: 8),
                              const Text('Complete boarding',
                                  style: TextStyle(fontWeight: FontWeight.w500)),
                              const Spacer(),
                              CupertinoButton(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                color: _primaryColor,
                                onPressed: (_adyenCompletingBoarding ||
                                        _adyenCheckingBoarding ||
                                        _connection!.adyenApiKey.isEmpty)
                                    ? null
                                    : _completeAdyenBoarding,
                                child: _adyenCompletingBoarding
                                    ? const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          CupertinoActivityIndicator(
                                              color: CupertinoColors.white),
                                          SizedBox(width: 8),
                                          Text('Pairing…',
                                              style: TextStyle(
                                                  color:
                                                      CupertinoColors.white)),
                                        ],
                                      )
                                    : const Text('Pair',
                                        style: TextStyle(
                                            color: CupertinoColors.white)),
                              ),
                            ],
                          ),
                          if (_connection!.adyenApiKey.isEmpty) ...[
                            const SizedBox(height: 4),
                            const Text(
                              'API key required — the app exchanges the '
                              'boardingRequestToken at the Adyen Management '
                              'API before launching /board.',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: CupertinoColors.systemGrey),
                            ),
                          ],
                        ],
                        if (_adyenBoardingStatus != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            _adyenBoardingStatus!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: _primaryColor,
                            ),
                          ),
                        ],
                        if (_adyenBoardingError != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            _adyenBoardingError!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: CupertinoColors.destructiveRed,
                            ),
                          ),
                        ],
                      ],
                      const SizedBox(height: 6),
                      const Text(
                          'Phase B: boarded-probe works. Transactions still '
                          'return "not implemented" until Phase C (Terminal API '
                          'encryption + /nexo App Link).',
                          style: TextStyle(
                              fontSize: 11,
                              color: CupertinoColors.systemGrey,
                              fontStyle: FontStyle.italic)),
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
