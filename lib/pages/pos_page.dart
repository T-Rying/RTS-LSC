import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/environment_config.dart';
import '../services/log_service.dart';
import '../services/softpay_plugin.dart';

class PosPage extends StatefulWidget {
  final EnvironmentConfig config;

  const PosPage({super.key, required this.config});

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  late final WebViewController _controller;
  final _log = LogService.instance;
  final _softPay = SoftPayPlugin();
  SoftPayTransaction? _lastTransaction;
  bool _loading = true;
  bool _credentialsInjected = false;
  bool _showDebug = false;

  String get _posUrl {
    final tenant = Uri.encodeComponent(widget.config.tenant);
    final company = Uri.encodeComponent(widget.config.company);
    final device = widget.config.deviceType == DeviceType.tablet ? 'tablet' : 'phone';
    return 'https://businesscentral.dynamics.com/$tenant/$company/$device';
  }

  /// JS that captures console, errors, network failures, alerts, and globals.
  static const String _debugScript = '''
    (function() {
      if (window._rtslscDebug) return;
      window._rtslscDebug = true;

      var D = function(msg) {
        try { LSAppShellDebug.postMessage(msg); } catch(e) {}
      };

      // Capture console
      var origLog = console.log, origWarn = console.warn, origErr = console.error;
      console.log = function() {
        D('LOG: ' + Array.from(arguments).join(' '));
        origLog.apply(console, arguments);
      };
      console.warn = function() {
        D('WARN: ' + Array.from(arguments).join(' '));
        origWarn.apply(console, arguments);
      };
      console.error = function() {
        D('ERROR: ' + Array.from(arguments).join(' '));
        origErr.apply(console, arguments);
      };

      // Capture uncaught errors with full stack
      window.addEventListener('error', function(e) {
        var msg = e.message || 'Unknown error';
        if (e.filename) msg += ' at ' + e.filename + ':' + e.lineno + ':' + e.colno;
        if (e.error && e.error.stack) msg += '\\nStack: ' + e.error.stack;
        D('UNCAUGHT: ' + msg);
      });

      // Capture unhandled promise rejections
      window.addEventListener('unhandledrejection', function(e) {
        var reason = e.reason;
        var msg = 'Promise rejected: ';
        if (reason instanceof Error) {
          msg += reason.message + (reason.stack ? '\\nStack: ' + reason.stack : '');
        } else {
          try { msg += JSON.stringify(reason); } catch(ex) { msg += String(reason); }
        }
        D('REJECTION: ' + msg);
      });

      // Capture alert / confirm / prompt
      var origAlert = window.alert;
      window.alert = function(msg) {
        D('ALERT: ' + msg);
        origAlert.call(window, msg);
      };
      var origConfirm = window.confirm;
      window.confirm = function(msg) {
        D('CONFIRM: ' + msg);
        return origConfirm.call(window, msg);
      };

      // Wrap fetch to log failures
      var origFetch = window.fetch;
      if (origFetch) {
        window.fetch = function() {
          var url = arguments[0];
          if (typeof url === 'object' && url.url) url = url.url;
          return origFetch.apply(this, arguments).then(function(resp) {
            if (!resp.ok) D('FETCH FAIL: ' + resp.status + ' ' + resp.statusText + ' ' + url);
            return resp;
          }).catch(function(err) {
            D('FETCH ERROR: ' + err.message + ' ' + url);
            throw err;
          });
        };
      }

      // Wrap XMLHttpRequest to log failures
      var origXhrOpen = XMLHttpRequest.prototype.open;
      var origXhrSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function(method, url) {
        this._rtslsc_url = method + ' ' + url;
        return origXhrOpen.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send = function() {
        var xhr = this;
        xhr.addEventListener('error', function() {
          D('XHR ERROR: ' + (xhr._rtslsc_url || 'unknown'));
        });
        xhr.addEventListener('load', function() {
          if (xhr.status >= 400) {
            D('XHR FAIL: ' + xhr.status + ' ' + (xhr._rtslsc_url || 'unknown'));
          }
        });
        return origXhrSend.apply(this, arguments);
      };

      // Scan for AppShell-related globals
      var scan = [];
      var keys = ['inAppShell', 'LSAppShellWebPOS', 'LSAppShell', 'LSAppShellAuth',
                  'SendRequestToAddInEx', 'OnResponseFromAddInEx',
                  'Microsoft', 'DynamicsNAV'];
      keys.forEach(function(k) {
        if (window[k] !== undefined) scan.push(k + '=' + typeof window[k]);
      });
      D('GLOBALS: ' + scan.join(' | '));

      // Scan iframes
      try {
        var frames = document.querySelectorAll('iframe');
        D('IFRAMES: ' + frames.length + ' found');
      } catch(e) {}

      D('UA: ' + navigator.userAgent);
    })();
  ''';

  /// JS bridge that makes the BC web client believe it's running inside the
  /// real LS AppShell. Decompilation of the real AppShell APK revealed:
  ///
  /// 1. window.inAppShell = true  — the primary detection flag
  /// 2. window.LSAppShellWebPOS   — native interface (addJavascriptInterface)
  ///    with methods: PostMessage, Request, Purchase, Refund, Void, Print,
  ///    CameraBarcodeScanner, OpenDrawer, IsDrawerOpened, GetLastTransaction
  /// 3. window.LSAppShellAuth     — secondary interface for auth HTML processing
  /// 4. window.AppshellInformation — JSON config string
  static const String _bridgeScript = '''
    (function() {
      // Primary AppShell detection flag
      window.inAppShell = true;

      var D = function(msg) {
        try { LSAppShellDebug.postMessage('[BRIDGE] ' + msg); } catch(e) {}
      };

      // Provide OnResponseFromAddInEx so Dart can call it to send results back
      if (!window.OnResponseFromAddInEx) {
        window.OnResponseFromAddInEx = function(type, id, success, jsonString) {};
      }

      // Expose SendRequestToAddInEx on the top-level window as fallback
      window.SendRequestToAddInEx = function(type, id, jsonString) {
        D('SendRequestToAddInEx called: type=' + type + ' id=' + id);
        if (window.LSAppShell) {
          LSAppShell.postMessage(JSON.stringify({
            "method": "SendRequestToAddInEx",
            "type": type,
            "id": id,
            "data": jsonString
          }));
        }
      };

      // The LSC_DeviceDialog control add-in uses LSAppShellAPIClass which
      // calls window.top.LSAppShell.request(type, id, json). Flutter's
      // addJavaScriptChannel only provides postMessage(). We add the
      // methods the control add-in expects.
      function patchLSAppShell(w) {
        var obj = w.LSAppShell;
        if (!obj || obj._rtslsc_patched) return;
        obj._rtslsc_patched = true;

        var send = function(method, args) {
          D('LSAppShell.' + method + '(' + Array.prototype.slice.call(args).map(function(a) {
            return typeof a === 'string' ? a.substring(0, 200) : String(a);
          }).join(', ') + ')');
          try {
            obj.postMessage(JSON.stringify({
              "method": method,
              "args": Array.prototype.slice.call(args)
            }));
          } catch(e) { D('LSAppShell postMessage error: ' + e); }
          return '{}';
        };

        // The control add-in calls LSAppShell.request(type, id, json)
        obj.request = function() { return send('request', arguments); };
        obj.Request = function() { return send('Request', arguments); };
        obj.PostMessage = function(msg) { return send('PostMessage', arguments); };
        obj.Purchase = function() { return send('Purchase', arguments); };
        obj.Refund = function() { return send('Refund', arguments); };
        obj.Void = function() { return send('Void', arguments); };
        obj.Print = function() { return send('Print', arguments); };
        obj.CameraBarcodeScanner = function() { return send('CameraBarcodeScanner', arguments); };
        obj.cameraBarcodeScanner = function() { return send('cameraBarcodeScanner', arguments); };
        obj.OpenDrawer = function() { return send('OpenDrawer', arguments); };
        obj.IsDrawerOpened = function() { return send('IsDrawerOpened', arguments); };
        obj.GetLastTransaction = function() { return send('GetLastTransaction', arguments); };
        D('patched LSAppShell in frame');
      }
      patchLSAppShell(window);

      // PascalCase method aliases for LSAppShellWebPOS.
      // The real AppShell's addJavascriptInterface exposes PascalCase methods
      // (PostMessage, Request, Purchase, etc.) that return String synchronously.
      // Flutter's addJavaScriptChannel only provides lowercase postMessage().
      function patchAppShellInterface(w) {
        var obj = w.LSAppShellWebPOS;
        if (!obj || obj._rtslsc_patched) return;
        obj._rtslsc_patched = true;

        var send = function(method, args) {
          D('LSAppShellWebPOS.' + method + '(' + Array.prototype.slice.call(args).map(function(a) {
            return typeof a === 'string' ? a.substring(0, 200) : String(a);
          }).join(', ') + ')');
          try {
            obj.postMessage(JSON.stringify({
              "method": method,
              "args": Array.prototype.slice.call(args)
            }));
          } catch(e) { D('postMessage error: ' + e); }
          return '{}';
        };

        obj.PostMessage = function(msg) { return send('PostMessage', arguments); };
        obj.Request = function() { return send('Request', arguments); };
        obj.Purchase = function() { return send('Purchase', arguments); };
        obj.Refund = function() { return send('Refund', arguments); };
        obj.Void = function() { return send('Void', arguments); };
        obj.Print = function() { return send('Print', arguments); };
        obj.CameraBarcodeScanner = function() { return send('CameraBarcodeScanner', arguments); };
        obj.cameraBarcodeScanner = function() { return send('cameraBarcodeScanner', arguments); };
        obj.OpenDrawer = function() { return send('OpenDrawer', arguments); };
        obj.IsDrawerOpened = function() { return send('IsDrawerOpened', arguments); };
        obj.GetLastTransaction = function() { return send('GetLastTransaction', arguments); };
        D('patched LSAppShellWebPOS in frame');
      }

      patchAppShellInterface(window);

      // Deep-scan ALL iframes including nested ones
      function deepPatchAllFrames() {
        function walk(w) {
          try {
            w.inAppShell = true;
            patchLSAppShell(w);
            patchAppShellInterface(w);
            for (var i = 0; i < w.frames.length; i++) {
              try { walk(w.frames[i]); } catch(e) {}
            }
          } catch(e) {} // cross-origin
        }
        walk(window);
      }
      deepPatchAllFrames();

      // MutationObserver for new iframes
      try {
        new MutationObserver(function() { deepPatchAllFrames(); })
          .observe(document.body || document.documentElement,
                   { childList: true, subtree: true });
      } catch(e) {}

      // Periodic scan as safety net — BC creates control add-in iframes
      // dynamically and they may not trigger MutationObserver reliably.
      setInterval(deepPatchAllFrames, 1000);
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

  /// Injects error/console capture into ALL iframes including dynamically
  /// created control add-in frames. Uses both MutationObserver and periodic
  /// scanning since BC's dialog framework may create iframes in ways that
  /// don't trigger mutation events.
  static const String _iframeDebugScript = '''
    (function() {
      var D = function(msg) {
        try { window.LSAppShellDebug.postMessage('[IFR] ' + msg); } catch(e) {}
      };

      function hookWindow(w, depth) {
        try {
          if (w._rtslscDebug) return;
          w._rtslscDebug = true;
          var tag = depth > 0 ? '[IFR-L' + depth + '] ' : '[IFR] ';
          var Df = function(msg) {
            try { window.LSAppShellDebug.postMessage(tag + msg); } catch(e) {}
          };
          w.addEventListener('error', function(e) {
            var msg = (e.message || 'error') + (e.filename ? ' at ' + e.filename + ':' + e.lineno : '');
            if (e.error && e.error.stack) msg += ' Stack: ' + e.error.stack;
            Df('UNCAUGHT: ' + msg);
          });
          w.addEventListener('unhandledrejection', function(e) {
            var r = e.reason;
            Df('REJECTION: ' + (r instanceof Error ? r.message + (r.stack || '') : String(r)));
          });
          var oc = w.console;
          if (oc) {
            var origErr = oc.error;
            oc.error = function() {
              Df('ERROR: ' + Array.from(arguments).join(' '));
              if (origErr) origErr.apply(oc, arguments);
            };
            var origWarn = oc.warn;
            oc.warn = function() {
              Df('WARN: ' + Array.from(arguments).join(' '));
              if (origWarn) origWarn.apply(oc, arguments);
            };
            var origLog = oc.log;
            oc.log = function() {
              Df('LOG: ' + Array.from(arguments).join(' '));
              if (origLog) origLog.apply(oc, arguments);
            };
          }
          var origAlert = w.alert;
          w.alert = function(msg) { Df('ALERT: ' + msg); if (origAlert) origAlert.call(w, msg); };
          Df('debug hooks installed (depth=' + depth + ')');
        } catch(e) {} // cross-origin
      }

      function deepScanFrames() {
        function walk(w, depth) {
          try {
            hookWindow(w, depth);
            for (var i = 0; i < w.frames.length; i++) {
              try { walk(w.frames[i], depth + 1); } catch(e) {}
            }
          } catch(e) {}
        }
        // Start from top and walk all frames
        walk(window, 0);
      }
      deepScanFrames();

      // MutationObserver
      try {
        new MutationObserver(function() { deepScanFrames(); })
          .observe(document.body || document.documentElement, { childList: true, subtree: true });
      } catch(e) {}

      // Periodic scan every 500ms — catches BC dialog iframes
      setInterval(deepScanFrames, 500);
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
      // LSAppShellWebPOS is the native interface name used by the real LS AppShell
      // (found by decompiling the official APK). The LSC_DeviceDialog control
      // add-in calls methods on window.LSAppShellWebPOS (PostMessage, Request,
      // Purchase, etc.) to communicate with the host app.
      // addJavaScriptChannel makes this available in ALL frames via addJavascriptInterface.
      ..addJavaScriptChannel(
        'LSAppShellWebPOS',
        onMessageReceived: _onDeviceMessage,
      )
      ..addJavaScriptChannel(
        'LSAppShellDebug',
        onMessageReceived: (msg) => _onDebugMessage(msg.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() => _loading = true);
            _log.info('PAGE START: $url');
            // Inject bridge on EVERY page start — critical for the EFT dialog
            // which opens as a new page/window and needs the PascalCase method
            // aliases on LSAppShellWebPOS before the control add-in loads.
            _controller.runJavaScript(_bridgeScript);
          },
          onPageFinished: (url) {
            setState(() => _loading = false);
            _log.info('PAGE DONE: $url');
            // Re-inject everything on page finish (belt and suspenders)
            _controller.runJavaScript(_debugScript);
            _controller.runJavaScript(_bridgeScript);
            if (url.contains('businesscentral.dynamics.com')) {
              _controller.runJavaScript(_disableKeyboardScript);
              _controller.runJavaScript(_iframeDebugScript);
              _log.debug('Bridge + keyboard + iframe debug scripts injected');
            }
            _tryInjectCredentials(url);
          },
        ),
      )
      ..setOnConsoleMessage((msg) {
        _log.debug('CONSOLE[${msg.level.name}]: ${msg.message}');
      })
      ..loadRequest(Uri.parse(_posUrl));

    _log.info('Loading: $_posUrl');
    _initSoftPay();
  }

  Future<void> _initSoftPay() async {
    if (!widget.config.softPayEnabled) {
      _log.debug('SoftPay not enabled, skipping init');
      return;
    }
    await _softPay.initialize(
      integratorId: widget.config.softPayIntegratorId,
      secret: widget.config.softPayCredentials,
    );
  }

  void _onDebugMessage(String msg) {
    setState(() {}); // trigger rebuild so debug console shows new entries
    if (msg.startsWith('ERROR:') || msg.startsWith('UNCAUGHT:') || msg.startsWith('REJECTION:')) {
      _log.error('JS $msg');
    } else if (msg.startsWith('WARN:') || msg.startsWith('ALERT:') || msg.startsWith('CONFIRM:')) {
      _log.warn('JS $msg');
    } else if (msg.startsWith('FETCH FAIL:') || msg.startsWith('FETCH ERROR:') ||
               msg.startsWith('XHR FAIL:') || msg.startsWith('XHR ERROR:')) {
      _log.error('JS $msg');
    } else {
      _log.debug('JS $msg');
    }
  }

  void _onMessage(JavaScriptMessage message) {
    _log.info('BRIDGE MSG: ${message.message}');
    try {
      final msg = jsonDecode(message.message) as Map<String, dynamic>;
      final method = msg['method'] as String? ?? '';

      if (method == 'SendRequestToAddInEx') {
        _handleDeviceRequest(
          type: msg['type'] as String,
          id: msg['id'] as String,
          data: msg['data'] as String,
        );
      } else if (method == 'request' || method == 'Request') {
        // LSAppShellAPIClass calls LSAppShell.Request(type, jsonData) with 2 args.
        // args[0] = type (e.g. "StartSession", "Purchase", "GetLastTransaction")
        // args[1] = JSON string with EFTSettings, Command, AmountBreakdown, etc.
        final args = msg['args'] as List<dynamic>? ?? [];
        final type = args.isNotEmpty ? args[0].toString() : '';
        final jsonData = args.length > 1 ? args[1].toString() : '{}';
        // Extract Command and TransactionId from JSON.
        // LS Central uses EFTJobID = "RequestType:TransactionId" as the
        // correlation ID that must be echoed back in OnResponseFromAddInEx.
        String resolvedType = type;
        String correlationId = type;
        try {
          final parsed = jsonDecode(jsonData) as Map<String, dynamic>;
          final command = parsed['Command'] as String?;
          final txnId = parsed['TransactionId'] as String? ?? '';
          if (command != null && command.isNotEmpty) {
            resolvedType = command;
          }
          // Build correlation ID matching LS Central's EFTJobID format
          correlationId = txnId.isNotEmpty
              ? '$resolvedType:$txnId'
              : resolvedType;
        } catch (_) {}
        _handleDeviceRequest(
          type: resolvedType,
          id: correlationId,
          data: jsonData,
        );
      } else if (method == 'PostMessage') {
        // Generic PostMessage — try to parse as device request
        final args = msg['args'] as List<dynamic>? ?? [];
        if (args.isNotEmpty) {
          try {
            final inner = jsonDecode(args[0].toString()) as Map<String, dynamic>;
            _handleDeviceRequest(
              type: inner['type'] as String? ?? inner['method'] as String? ?? '',
              id: inner['id'] as String? ?? '',
              data: args[0].toString(),
            );
          } catch (_) {
            _log.debug('PostMessage payload not a device request: ${args[0]}');
          }
        }
      } else {
        _log.debug('Unknown LSAppShell method: $method');
      }
    } catch (e) {
      _log.error('BRIDGE PARSE ERROR: $e');
    }
  }

  /// Handles messages from the LSAppShellDevice channel.
  /// The LSC_DeviceDialog control add-in uses this to forward device requests
  /// when it detects Host == ###LSAPPSHELL.
  void _onDeviceMessage(JavaScriptMessage message) {
    _log.info('DEVICE CHANNEL MSG: ${message.message}');
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
        final type = msg['type'] as String? ?? '';
        final id = msg['id'] as String? ?? '';
        final data = msg['data'] as String? ?? message.message;
        if (type.isNotEmpty) {
          _handleDeviceRequest(type: type, id: id, data: data);
        }
      }
    } catch (e) {
      _log.error('DEVICE CHANNEL PARSE ERROR: $e');
    }
  }

  void _handleDeviceRequest({
    required String type,
    required String id,
    required String data,
  }) {
    _log.info('DEVICE REQ: type=$type id=$id');
    Map<String, dynamic> json;
    try {
      json = jsonDecode(data) as Map<String, dynamic>;
    } catch (e) {
      _log.error('  Failed to parse request data: $e');
      return;
    }

    // EFTSettings may be at top level or nested
    final eftSettings = json['EFTSettings'] as Map<String, dynamic>? ?? json;
    final host = eftSettings['Host'] as String? ?? '';
    _log.debug('  Host=$host');

    final isAppShell = host == '###LSAPPSHELL';
    if (!isAppShell) {
      _log.debug('  Not AppShell host, ignoring');
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
      case 'GetLastTransaction':
        _handleGetLastTransaction(id, json);
        break;
      case 'EFT:REQUEST':
        _handleEftRequest(id, json);
        break;
      case 'Purchase':
      case 'Refund':
      case 'Void':
      case 'PreAuth':
      case 'FinalizePreAuth':
        _handleEftRequest(id, json);
        break;
      default:
        if (type.startsWith('EFT:')) {
          _handleEftRequest(id, json);
        } else {
          _log.warn('  Unknown type: $type');
        }
        break;
    }
  }

  /// Handle GetLastTransaction — BC asks for the last EFT transaction
  /// to retrieve the EFT transaction ID for receipts, etc.
  void _handleGetLastTransaction(String id, Map<String, dynamic> json) {
    _log.info('GetLastTransaction requested');
    if (_lastTransaction != null) {
      final transactionId = json['TransactionId'] as String? ?? '';
      _sendResponseToBC(
        type: 'GetLastTransaction', id: id, success: true,
        data: _lastTransaction!.toLsCentralJson(clientTransactionId: transactionId),
      );
    } else {
      _sendResponseToBC(
        type: 'GetLastTransaction', id: id, success: false,
        data: 'No previous transaction',
      );
    }
  }

  Future<void> _handleEftRequest(String id, Map<String, dynamic> json) async {
    final command = json['Command'] as String? ?? 'Purchase';
    _log.info('EFT REQ: command=$command');

    if (!widget.config.softPayEnabled) {
      _sendResponseToBC(
        type: command, id: id, success: false,
        data: 'SoftPay is not enabled in app settings',
      );
      return;
    }

    if (!_softPay.isInitialized) {
      _log.warn('SoftPay not initialized, attempting init...');
      await _initSoftPay();
      if (!_softPay.isInitialized) {
        _sendResponseToBC(
          type: command, id: id, success: false,
          data: 'SoftPay SDK failed to initialize',
        );
        return;
      }
    }

    final amountBreakdown = json['AmountBreakdown'] as Map<String, dynamic>?;
    final totalAmount = amountBreakdown?['TotalAmount'];
    final currencyCode = amountBreakdown?['CurrencyCode'] as String? ?? 'DKK';
    final transactionId = json['TransactionId'] as String? ?? '';

    final amountMinor = totalAmount is num
        ? (totalAmount * 100).round()
        : int.tryParse(totalAmount.toString()) ?? 0;

    _log.info('  Amount=$totalAmount ($amountMinor minor) $currencyCode ref=$transactionId');

    SoftPayResult result;
    switch (command) {
      case 'Purchase':
      case 'PreAuth':
      case 'FinalizePreAuth':
        result = await _softPay.purchase(amount: amountMinor, currency: currencyCode);
        break;
      case 'Refund':
        result = await _softPay.refund(amount: amountMinor, currency: currencyCode);
        break;
      case 'Void':
        final origTxnIds = json['OriginalTransactionIds'] as Map<String, dynamic>?;
        final origRequestId = origTxnIds?['EFTTransactionId'] as String?;
        result = await _softPay.cancel(requestId: origRequestId);
        break;
      default:
        result = await _softPay.purchase(amount: amountMinor, currency: currencyCode);
        break;
    }

    if (result.success && result.transaction != null) {
      _lastTransaction = result.transaction;
      _log.info('  SoftPay $command OK: ${result.transaction!.state}');
      _sendResponseToBC(
        type: command,
        id: id,
        success: true,
        data: result.transaction!.toLsCentralJson(clientTransactionId: transactionId),
      );
    } else {
      final errorMsg = result.errorMessage ?? 'Transaction failed';
      _log.error('  SoftPay $command FAILED: $errorMsg');
      _sendResponseToBC(
        type: command,
        id: id,
        success: false,
        data: errorMsg,
      );
    }
  }

  Future<void> _sendResponseToBC({
    required String type,
    required String id,
    required bool success,
    required String data,
  }) async {
    _log.info('RESPONSE: type=$type id=$id success=$success');
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
      _log.info('Injecting login credentials');
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
              child: const Icon(CupertinoIcons.paperplane),
              onPressed: () => _log.share(),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              child: const Icon(CupertinoIcons.refresh),
              onPressed: () {
                _credentialsInjected = false;
                _log.clear();
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
                          onPressed: () => setState(() => _log.clear()),
                        ),
                      ],
                    ),
                    Expanded(
                      child: ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _log.length,
                        itemBuilder: (_, i) {
                          final logs = _log.logs;
                          final entry = logs[logs.length - 1 - i];
                          Color color = CupertinoColors.systemGrey2;
                          if (entry.contains('ERR ') || entry.contains('ERROR') || entry.contains('UNCAUGHT') || entry.contains('FAILED')) {
                            color = CupertinoColors.systemRed;
                          } else if (entry.contains('WRN ') || entry.contains('WARN') || entry.contains('ALERT')) {
                            color = CupertinoColors.systemOrange;
                          } else if (entry.contains('BRIDGE') || entry.contains('DEVICE REQ') || entry.contains('DEVICE CHANNEL')) {
                            color = CupertinoColors.systemGreen;
                          }
                          return Text(entry, style: TextStyle(color: color, fontSize: 11, fontFamily: 'Courier'));
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
