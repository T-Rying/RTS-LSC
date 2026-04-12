import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/environment_config.dart';

class PosPage extends StatefulWidget {
  final EnvironmentConfig config;

  const PosPage({super.key, required this.config});

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _credentialsInjected = false;

  String get _posUrl {
    final tenant = Uri.encodeComponent(widget.config.tenant);
    final company = Uri.encodeComponent(widget.config.company);
    final device = widget.config.deviceType == DeviceType.tablet ? 'tablet' : 'phone';
    return 'https://businesscentral.dynamics.com/$tenant/$company/$device';
  }

  /// JS bridge that intercepts the LSC_DeviceDialog control add-in calls.
  /// LS Central calls SendRequestToAddInEx(type, id, json) from its web client.
  /// We override it to forward to our Flutter LSAppShell JS channel.
  /// We also provide OnResponseFromAddInEx so we can call it from Dart.
  static const String _bridgeScript = '''
    (function() {
      window.SendRequestToAddInEx = function(type, id, jsonString) {
        if (window.LSAppShell) {
          LSAppShell.postMessage(JSON.stringify({
            "method": "SendRequestToAddInEx",
            "type": type,
            "id": id,
            "data": jsonString
          }));
        }
      };

      if (!window.OnResponseFromAddInEx) {
        window.OnResponseFromAddInEx = function(type, id, success, jsonString) {
          // BC picks this up via the LSC_DeviceDialog control add-in
        };
      }
    })();
  ''';

  /// JS to suppress the on-screen keyboard on POS input fields.
  static const String _disableKeyboardScript = '''
    (function() {
      document.addEventListener('focusin', function(e) {
        if (e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA')) {
          e.target.setAttribute('readonly', 'readonly');
          setTimeout(function() { e.target.removeAttribute('readonly'); }, 100);
        }
      }, true);
    })();
  ''';

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'LSAppShell',
        onMessageReceived: _onMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() => _loading = true);
          },
          onPageFinished: (url) {
            setState(() => _loading = false);
            if (url.contains('businesscentral.dynamics.com')) {
              _controller.runJavaScript(_bridgeScript);
              _controller.runJavaScript(_disableKeyboardScript);
            }
            _tryInjectCredentials(url);
          },
        ),
      )
      ..loadRequest(Uri.parse(_posUrl));
  }

  /// Handle incoming messages from the LSC_DeviceDialog control add-in.
  void _onMessage(JavaScriptMessage message) {
    try {
      final msg = jsonDecode(message.message) as Map<String, dynamic>;
      if (msg['method'] == 'SendRequestToAddInEx') {
        _handleDeviceRequest(
          type: msg['type'] as String,
          id: msg['id'] as String,
          data: msg['data'] as String,
        );
      }
    } catch (_) {}
  }

  /// Route device requests based on type.
  void _handleDeviceRequest({
    required String type,
    required String id,
    required String data,
  }) {
    final json = jsonDecode(data) as Map<String, dynamic>;
    final eftSettings = json['EFTSettings'] as Map<String, dynamic>?;
    final host = eftSettings?['Host'] as String? ?? '';
    final isAppShell = host == '###LSAPPSHELL';

    // Only handle locally if configured for AppShell
    if (!isAppShell) return;

    switch (type) {
      case 'StartSession':
        _sendResponseToBC(
          type: 'STARTSESSION',
          id: id,
          success: true,
          data: '{"SessionResponse":"StartingSessionSuccessful"}',
        );
        break;

      case 'FinishSession':
        _sendResponseToBC(type: 'FINISHSESSION', id: id, success: true, data: '{}');
        break;

      case 'CloseAddIn':
        _sendResponseToBC(type: 'CLOSEADDIN', id: id, success: true, data: '{}');
        break;

      case 'EFT:REQUEST':
        _handleEftRequest(id, json);
        break;

      default:
        // Legacy: EFT:PURCHASE, EFT:REFUND, EFT:VOID
        if (type.startsWith('EFT:')) {
          _handleEftRequest(id, json);
        }
        break;
    }
  }

  /// Handle EFT payment requests by routing to SoftPay.
  void _handleEftRequest(String id, Map<String, dynamic> json) {
    if (!widget.config.softPayEnabled) {
      _sendResponseToBC(
        type: json['Command'] as String? ?? 'Purchase',
        id: id,
        success: false,
        data: 'SoftPay is not enabled in app settings',
      );
      return;
    }

    final amountBreakdown = json['AmountBreakdown'] as Map<String, dynamic>?;
    final totalAmount = amountBreakdown?['TotalAmount'];
    final currencyCode = amountBreakdown?['CurrencyCode'] as String? ?? 'DKK';
    final transactionId = json['TransactionId'] as String? ?? '';
    final command = json['Command'] as String? ?? 'Purchase';

    // Convert to minor units (cents/øre)
    final amountMinor = totalAmount is num
        ? (totalAmount * 100).round()
        : int.tryParse(totalAmount.toString()) ?? 0;

    final params = {
      'integrator_id': widget.config.softPayIntegratorId,
      'credentials': widget.config.softPayCredentials,
      'amount': amountMinor.toString(),
      'currency': currencyCode,
      if (transactionId.isNotEmpty) 'reference': transactionId,
      'callback': 'rtslsc://softpay-callback',
    };

    final uri = Uri(
      scheme: 'softpay',
      host: 'payment',
      queryParameters: params,
    );

    launchUrl(uri, mode: LaunchMode.externalApplication).then((launched) {
      if (!launched) {
        _sendResponseToBC(
          type: command,
          id: id,
          success: false,
          data: 'Could not launch SoftPay app',
        );
      }
      // SoftPay will callback via rtslsc://softpay-callback with the result.
      // TODO: Handle the callback and send the response back to BC.
    });
  }

  /// Send a response back to LS Central via the OnResponseFromAddInEx bridge.
  Future<void> _sendResponseToBC({
    required String type,
    required String id,
    required bool success,
    required String data,
  }) async {
    final escapedData = data
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'");
    await _controller.runJavaScript(
      "window.OnResponseFromAddInEx('$type', '$id', $success, '$escapedData');",
    );
  }

  Future<void> _tryInjectCredentials(String url) async {
    if (_credentialsInjected) return;

    final username = widget.config.posUsername;
    final password = widget.config.posPassword;
    if (username.isEmpty || password.isEmpty) return;

    final safeUser = username.replaceAll("'", "\\'");
    final safePass = password.replaceAll("'", "\\'");

    if (url.contains('login.microsoftonline.com') || url.contains('login.live.com')) {
      await _controller.runJavaScript('''
        (function() {
          var emailInput = document.querySelector('input[name="loginfmt"]');
          if (emailInput) {
            emailInput.value = '$safeUser';
            emailInput.dispatchEvent(new Event('input', { bubbles: true }));
            setTimeout(function() {
              var nextBtn = document.querySelector('input[type="submit"]');
              if (nextBtn) nextBtn.click();
            }, 500);
          }
        })();
      ''');

      await Future.delayed(const Duration(seconds: 2));
      await _controller.runJavaScript('''
        (function() {
          var passInput = document.querySelector('input[name="passwd"]');
          if (passInput) {
            passInput.value = '$safePass';
            passInput.dispatchEvent(new Event('input', { bubbles: true }));
            setTimeout(function() {
              var signInBtn = document.querySelector('input[type="submit"]');
              if (signInBtn) signInBtn.click();
            }, 500);
          }
        })();
      ''');

      _credentialsInjected = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('POS'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          child: const Icon(CupertinoIcons.refresh),
          onPressed: () {
            _credentialsInjected = false;
            _controller.reload();
          },
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loading)
              const Center(child: CupertinoActivityIndicator(radius: 16)),
          ],
        ),
      ),
    );
  }
}
