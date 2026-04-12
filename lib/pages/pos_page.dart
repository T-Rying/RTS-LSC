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
  bool _showDebug = false;
  final List<String> _debugLogs = [];

  String get _posUrl {
    final tenant = Uri.encodeComponent(widget.config.tenant);
    final company = Uri.encodeComponent(widget.config.company);
    final device = widget.config.deviceType == DeviceType.tablet ? 'tablet' : 'phone';
    return 'https://businesscentral.dynamics.com/$tenant/$company/$device';
  }

  void _log(String msg) {
    setState(() {
      _debugLogs.add('[${DateTime.now().toString().substring(11, 19)}] $msg');
      if (_debugLogs.length > 200) _debugLogs.removeAt(0);
    });
  }

  /// JS that captures console.log/warn/error and window.alert, and
  /// scans the page for any AppShell-related globals.
  static const String _debugScript = '''
    (function() {
      if (window._rtslscDebug) return;
      window._rtslscDebug = true;

      // Capture console
      var origLog = console.log, origWarn = console.warn, origErr = console.error;
      console.log = function() {
        var msg = Array.from(arguments).join(' ');
        LSAppShellDebug.postMessage('LOG: ' + msg);
        origLog.apply(console, arguments);
      };
      console.warn = function() {
        var msg = Array.from(arguments).join(' ');
        LSAppShellDebug.postMessage('WARN: ' + msg);
        origWarn.apply(console, arguments);
      };
      console.error = function() {
        var msg = Array.from(arguments).join(' ');
        LSAppShellDebug.postMessage('ERROR: ' + msg);
        origErr.apply(console, arguments);
      };

      // Capture uncaught errors
      window.addEventListener('error', function(e) {
        LSAppShellDebug.postMessage('UNCAUGHT: ' + e.message + ' at ' + e.filename + ':' + e.lineno);
      });

      // Capture alert (likely where the error message shows)
      var origAlert = window.alert;
      window.alert = function(msg) {
        LSAppShellDebug.postMessage('ALERT: ' + msg);
        origAlert.call(window, msg);
      };

      // Scan for AppShell-related globals
      var scan = [];
      var keys = ['LSAppShellDevice', 'LSAppShell', 'SendRequestToAddInEx',
                  'OnResponseFromAddInEx', 'AppShell', 'appShell',
                  'Microsoft', 'NAVDeviceHandler', 'DynamicsNAV'];
      keys.forEach(function(k) {
        if (window[k] !== undefined) scan.push(k + '=' + typeof window[k]);
      });
      if (window.Microsoft && window.Microsoft.Dynamics) {
        scan.push('Microsoft.Dynamics exists');
        if (window.Microsoft.Dynamics.NAV) {
          scan.push('Microsoft.Dynamics.NAV exists');
          var navKeys = Object.keys(window.Microsoft.Dynamics.NAV);
          scan.push('NAV keys: ' + navKeys.join(', '));
        }
      }
      LSAppShellDebug.postMessage('GLOBALS: ' + scan.join(' | '));

      // Scan iframes
      try {
        var frames = document.querySelectorAll('iframe');
        LSAppShellDebug.postMessage('IFRAMES: ' + frames.length + ' found');
      } catch(e) {}

      // Check user agent
      LSAppShellDebug.postMessage('UA: ' + navigator.userAgent);
    })();
  ''';

  /// JS bridge for LSC_DeviceDialog control add-in protocol.
  /// The LSC_DeviceDialog control add-in runs in its own iframe and checks
  /// for window.LSAppShellDevice to detect AppShell. We register it as a
  /// JavaScript channel (addJavascriptInterface) so it's available in ALL
  /// frames before any script runs. This script enriches it with helper
  /// methods for the main frame and provides the SendRequestToAddInEx shim.
  static const String _bridgeScript = '''
    (function() {
      // Provide OnResponseFromAddInEx so Dart can call it to send results back
      if (!window.OnResponseFromAddInEx) {
        window.OnResponseFromAddInEx = function(type, id, success, jsonString) {};
      }

      // Also expose SendRequestToAddInEx on the top-level window as fallback
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
    })();
  ''';

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
      // LSAppShellDevice channel is the key detection mechanism.
      // The LSC_DeviceDialog control add-in (in its own iframe) checks for
      // window.LSAppShellDevice to determine if it's running inside AppShell.
      // Using addJavaScriptChannel (backed by addJavascriptInterface on Android)
      // makes this available in ALL frames before any page script runs.
      ..addJavaScriptChannel(
        'LSAppShellDevice',
        onMessageReceived: _onDeviceMessage,
      )
      ..addJavaScriptChannel(
        'LSAppShellDebug',
        onMessageReceived: (msg) => _log(msg.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() => _loading = true);
            _log('PAGE START: $url');
          },
          onPageFinished: (url) {
            setState(() => _loading = false);
            _log('PAGE DONE: $url');
            // Inject debug first, then bridge
            _controller.runJavaScript(_debugScript);
            if (url.contains('businesscentral.dynamics.com')) {
              _controller.runJavaScript(_bridgeScript);
              _controller.runJavaScript(_disableKeyboardScript);
              _log('Bridge + keyboard scripts injected');
            }
            _tryInjectCredentials(url);
          },
        ),
      )
      ..setOnConsoleMessage((msg) {
        _log('CONSOLE[${msg.level.name}]: ${msg.message}');
      })
      ..loadRequest(Uri.parse(_posUrl));

    _log('Loading: $_posUrl');
  }

  void _onMessage(JavaScriptMessage message) {
    _log('BRIDGE MSG: ${message.message}');
    try {
      final msg = jsonDecode(message.message) as Map<String, dynamic>;
      if (msg['method'] == 'SendRequestToAddInEx') {
        _handleDeviceRequest(
          type: msg['type'] as String,
          id: msg['id'] as String,
          data: msg['data'] as String,
        );
      }
    } catch (e) {
      _log('BRIDGE PARSE ERROR: $e');
    }
  }

  /// Handles messages from the LSAppShellDevice channel.
  /// The LSC_DeviceDialog control add-in uses this to forward device requests
  /// when it detects Host == ###LSAPPSHELL.
  void _onDeviceMessage(JavaScriptMessage message) {
    _log('DEVICE CHANNEL MSG: ${message.message}');
    try {
      final msg = jsonDecode(message.message) as Map<String, dynamic>;
      final method = msg['method'] as String? ?? '';
      if (method == 'SendRequestToAddInEx') {
        _handleDeviceRequest(
          type: msg['type'] as String,
          id: msg['id'] as String,
          data: msg['data'] as String,
        );
      } else {
        // The control add-in may send the request in a different format
        final type = msg['type'] as String? ?? '';
        final id = msg['id'] as String? ?? '';
        final data = msg['data'] as String? ?? message.message;
        if (type.isNotEmpty) {
          _handleDeviceRequest(type: type, id: id, data: data);
        }
      }
    } catch (e) {
      _log('DEVICE CHANNEL PARSE ERROR: $e');
    }
  }

  void _handleDeviceRequest({
    required String type,
    required String id,
    required String data,
  }) {
    _log('DEVICE REQ: type=$type id=$id');
    final json = jsonDecode(data) as Map<String, dynamic>;
    final eftSettings = json['EFTSettings'] as Map<String, dynamic>?;
    final host = eftSettings?['Host'] as String? ?? '';
    _log('  Host=$host');

    final isAppShell = host == '###LSAPPSHELL';
    if (!isAppShell) {
      _log('  Not AppShell host, ignoring');
      return;
    }

    switch (type) {
      case 'StartSession':
        _sendResponseToBC(
          type: 'STARTSESSION', id: id, success: true,
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
        if (type.startsWith('EFT:')) {
          _handleEftRequest(id, json);
        } else {
          _log('  Unknown type: $type');
        }
        break;
    }
  }

  void _handleEftRequest(String id, Map<String, dynamic> json) {
    final command = json['Command'] as String? ?? 'Purchase';
    _log('EFT REQ: command=$command');

    if (!widget.config.softPayEnabled) {
      _sendResponseToBC(
        type: command, id: id, success: false,
        data: 'SoftPay is not enabled in app settings',
      );
      return;
    }

    final amountBreakdown = json['AmountBreakdown'] as Map<String, dynamic>?;
    final totalAmount = amountBreakdown?['TotalAmount'];
    final currencyCode = amountBreakdown?['CurrencyCode'] as String? ?? 'DKK';
    final transactionId = json['TransactionId'] as String? ?? '';

    final amountMinor = totalAmount is num
        ? (totalAmount * 100).round()
        : int.tryParse(totalAmount.toString()) ?? 0;

    _log('  Amount=$totalAmount ($amountMinor minor) $currencyCode ref=$transactionId');

    final params = {
      'integrator_id': widget.config.softPayIntegratorId,
      'credentials': widget.config.softPayCredentials,
      'amount': amountMinor.toString(),
      'currency': currencyCode,
      if (transactionId.isNotEmpty) 'reference': transactionId,
      'callback': 'rtslsc://softpay-callback',
    };

    final uri = Uri(scheme: 'softpay', host: 'payment', queryParameters: params);
    _log('  Launching: $uri');

    launchUrl(uri, mode: LaunchMode.externalApplication).then((launched) {
      if (!launched) {
        _log('  SoftPay launch FAILED');
        _sendResponseToBC(type: command, id: id, success: false, data: 'Could not launch SoftPay app');
      } else {
        _log('  SoftPay launched OK');
      }
    });
  }

  Future<void> _sendResponseToBC({
    required String type,
    required String id,
    required bool success,
    required String data,
  }) async {
    _log('RESPONSE: type=$type id=$id success=$success');
    final escapedData = data.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
    // Deliver to main frame and also try all iframes (control add-in context)
    await _controller.runJavaScript('''
      (function() {
        var args = ['$type', '$id', $success, '$escapedData'];
        // Main frame
        if (window.OnResponseFromAddInEx) {
          try { window.OnResponseFromAddInEx.apply(null, args); } catch(e) {}
        }
        // Control add-in iframes
        try {
          var frames = document.querySelectorAll('iframe');
          for (var i = 0; i < frames.length; i++) {
            try {
              var w = frames[i].contentWindow;
              if (w && w.OnResponseFromAddInEx) {
                w.OnResponseFromAddInEx.apply(null, args);
              }
              // Also try the BC extensibility method in iframes
              if (w && w.Microsoft && w.Microsoft.Dynamics && w.Microsoft.Dynamics.NAV &&
                  w.Microsoft.Dynamics.NAV.InvokeExtensibilityMethod) {
                w.Microsoft.Dynamics.NAV.InvokeExtensibilityMethod(
                  'OnResponseFromAddInEx', args);
              }
            } catch(e) {} // cross-origin frames will throw
          }
        } catch(e) {}
      })();
    ''');
  }

  Future<void> _tryInjectCredentials(String url) async {
    if (_credentialsInjected) return;
    final username = widget.config.posUsername;
    final password = widget.config.posPassword;
    if (username.isEmpty || password.isEmpty) return;

    final safeUser = username.replaceAll("'", "\\'");
    final safePass = password.replaceAll("'", "\\'");

    if (url.contains('login.microsoftonline.com') || url.contains('login.live.com')) {
      _log('Injecting login credentials');
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              child: Icon(
                CupertinoIcons.doc_text,
                color: _showDebug ? CupertinoColors.activeOrange : null,
              ),
              onPressed: () => setState(() => _showDebug = !_showDebug),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              child: const Icon(CupertinoIcons.refresh),
              onPressed: () {
                _credentialsInjected = false;
                _debugLogs.clear();
                _controller.reload();
              },
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  if (_loading)
                    const Center(child: CupertinoActivityIndicator(radius: 16)),
                ],
              ),
            ),
            if (_showDebug)
              Container(
                height: 200,
                color: CupertinoColors.black,
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('Debug Console',
                              style: TextStyle(color: CupertinoColors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                        const Spacer(),
                        CupertinoButton(
                          padding: const EdgeInsets.all(8),
                          minSize: 0,
                          child: const Text('Clear', style: TextStyle(color: CupertinoColors.activeOrange, fontSize: 12)),
                          onPressed: () => setState(() => _debugLogs.clear()),
                        ),
                      ],
                    ),
                    Expanded(
                      child: ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _debugLogs.length,
                        itemBuilder: (_, i) {
                          final log = _debugLogs[_debugLogs.length - 1 - i];
                          Color color = CupertinoColors.systemGrey2;
                          if (log.contains('ERROR') || log.contains('UNCAUGHT') || log.contains('FAILED')) {
                            color = CupertinoColors.systemRed;
                          } else if (log.contains('WARN') || log.contains('ALERT')) {
                            color = CupertinoColors.systemOrange;
                          } else if (log.contains('BRIDGE') || log.contains('DEVICE REQ')) {
                            color = CupertinoColors.systemGreen;
                          }
                          return Text(log, style: TextStyle(color: color, fontSize: 11, fontFamily: 'Courier'));
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
