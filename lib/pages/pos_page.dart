import 'package:flutter/material.dart';
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
    return 'https://businesscentral.dynamics.com/$tenant/$company';
  }

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            setState(() => _loading = true);
          },
          onPageFinished: (url) {
            setState(() => _loading = false);
            _tryInjectCredentials(url);
          },
        ),
      )
      ..loadRequest(Uri.parse(_posUrl));
  }

  Future<void> _tryInjectCredentials(String url) async {
    if (_credentialsInjected) return;

    final username = widget.config.posUsername;
    final password = widget.config.posPassword;
    if (username.isEmpty || password.isEmpty) return;

    // Escape single quotes in credentials for JS string safety
    final safeUser = username.replaceAll("'", "\\'");
    final safePass = password.replaceAll("'", "\\'");

    // Microsoft Entra ID login: fill email/username field
    if (url.contains('login.microsoftonline.com') || url.contains('login.live.com')) {
      await _controller.runJavaScript('''
        (function() {
          var emailInput = document.querySelector('input[name="loginfmt"]');
          if (emailInput) {
            emailInput.value = '$safeUser';
            emailInput.dispatchEvent(new Event('input', { bubbles: true }));
            // Click the Next button after a short delay
            setTimeout(function() {
              var nextBtn = document.querySelector('input[type="submit"]');
              if (nextBtn) nextBtn.click();
            }, 500);
          }
        })();
      ''');

      // After the page transitions to password step, fill password
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('POS'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _credentialsInjected = false;
              _controller.reload();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
