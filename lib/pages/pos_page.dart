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

  /// JS to disable keyboard focus on input fields inside the POS.
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

  /// JS bridge for AppShell communication — only injected on the BC POS page,
  /// not on the login page. LS Central hardware station config must use
  /// ###LSAPPSHELL as Printer Server Host to activate AppShell mode.
  static const String _bridgeScript = '''
    (function() {
      if (window.LSAppShellDevice) return;

      window.LSAppShellDevice = {
        _version: '1.0',
        _platform: 'RTS-LSC',

        isAppShell: function() { return true; },
        getDeviceId: function() { return 'LSAPPSHELL'; },

        sendMessage: function(message) {
          if (window.LSAppShell) {
            window.LSAppShell.postMessage(JSON.stringify(message));
          }
        },

        paymentRequest: function(amount, currency, reference) {
          this.sendMessage({ type: 'paymentRequest', amount: amount, currency: currency, reference: reference || '' });
        },

        paymentReversal: function(amount, currency, reference) {
          this.sendMessage({ type: 'paymentReversal', amount: amount, currency: currency, reference: reference || '' });
        },

        openUrl: function(url) {
          this.sendMessage({ type: 'openUrl', url: url });
        },

        printReceipt: function(data) {
          this.sendMessage({ type: 'printReceipt', data: data });
        }
      };

      if (!window.Microsoft) window.Microsoft = {};
      if (!window.Microsoft.Dynamics) window.Microsoft.Dynamics = {};
      if (!window.Microsoft.Dynamics.NAV) window.Microsoft.Dynamics.NAV = {};
      var origMethod = window.Microsoft.Dynamics.NAV.InvokeExtensibilityMethod;
      window.Microsoft.Dynamics.NAV.InvokeExtensibilityMethod = function(method, args) {
        if (window.LSAppShell) {
          window.LSAppShell.postMessage(JSON.stringify({ type: 'extensibility', method: method, args: args }));
        }
        if (origMethod) origMethod.call(this, method, args);
      };
    })();
  ''';

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'LSAppShell',
        onMessageReceived: _onAppShellMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() => _loading = true);
          },
          onPageFinished: (url) {
            setState(() => _loading = false);
            // Only inject bridge on BC pages, not login pages
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

  void _onAppShellMessage(JavaScriptMessage message) {
    try {
      final msg = jsonDecode(message.message) as Map<String, dynamic>;
      final type = msg['type'] as String?;

      switch (type) {
        case 'paymentRequest':
        case 'paymentReversal':
          _handlePaymentRequest(msg);
          break;
        case 'openUrl':
          final url = msg['url'] as String?;
          if (url != null) launchUrl(Uri.parse(url));
          break;
        case 'extensibility':
          _handleExtensibility(msg);
          break;
      }
    } catch (_) {}
  }

  void _handlePaymentRequest(Map<String, dynamic> msg) {
    if (!widget.config.softPayEnabled) {
      _sendPaymentResult(success: false, error: 'SoftPay is not enabled');
      return;
    }

    final amount = msg['amount'];
    final currency = msg['currency'] as String? ?? 'DKK';
    final reference = msg['reference'] as String? ?? '';
    final amountMinor = amount is int ? amount : int.tryParse(amount.toString()) ?? 0;

    final params = {
      'integrator_id': widget.config.softPayIntegratorId,
      'credentials': widget.config.softPayCredentials,
      'amount': amountMinor.toString(),
      'currency': currency,
      if (reference.isNotEmpty) 'reference': reference,
      'callback': 'rtslsc://softpay-callback',
    };

    final uri = Uri(
      scheme: 'softpay',
      host: 'payment',
      queryParameters: params,
    );

    launchUrl(uri, mode: LaunchMode.externalApplication).then((launched) {
      if (!launched) {
        _sendPaymentResult(success: false, error: 'Could not launch SoftPay');
      }
    });
  }

  void _handleExtensibility(Map<String, dynamic> msg) {
    final method = msg['method'] as String?;
    final args = msg['args'] as List<dynamic>?;

    if (method != null && method.toLowerCase().contains('payment') && args != null) {
      _handlePaymentRequest({
        'amount': args.isNotEmpty ? args[0] : 0,
        'currency': args.length > 1 ? args[1] : 'DKK',
        'reference': args.length > 2 ? args[2] : '',
      });
    }
  }

  void _sendPaymentResult({required bool success, String error = ''}) {
    final safeError = error.replaceAll("'", "\\'");
    _controller.runJavaScript(
      "window.LSAppShellDevice && window.LSAppShellDevice.onPaymentComplete && "
      "window.LSAppShellDevice.onPaymentComplete($success, '$safeError');",
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
