import 'package:flutter/cupertino.dart';
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
