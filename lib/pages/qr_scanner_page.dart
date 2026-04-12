import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/environment_config.dart';

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _hasScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    _hasScanned = true;

    try {
      final json = jsonDecode(barcode.rawValue!) as Map<String, dynamic>;
      final config = EnvironmentConfig.fromJson(json);
      Navigator.pop(context, config);
    } catch (_) {
      setState(() => _hasScanned = false);
      showCupertinoDialog(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('Invalid QR Code'),
          content: const Text('Expected a valid connection configuration.'),
          actions: [
            CupertinoDialogAction(
              child: const Text('OK'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Scan QR Code'),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Point your camera at a connection QR code',
                style: TextStyle(
                  fontSize: 14,
                  color: CupertinoColors.systemGrey,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
