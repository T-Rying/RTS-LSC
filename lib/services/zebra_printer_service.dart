import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

import 'log_service.dart';

/// Minimal representation of a networked Zebra printer.
class ZebraPrinter {
  final String name;
  final String host;
  final int port;

  const ZebraPrinter({required this.name, required this.host, required this.port});

  Map<String, dynamic> toJson() => {'name': name, 'host': host, 'port': port};

  factory ZebraPrinter.fromJson(Map<String, dynamic> j) => ZebraPrinter(
        name: j['name'] as String? ?? '',
        host: j['host'] as String? ?? '',
        port: (j['port'] as num?)?.toInt() ?? 9100,
      );

  @override
  bool operator ==(Object other) =>
      other is ZebraPrinter && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);
}

/// Discovers Zebra printers via mDNS and prints ZPL to them on port 9100.
///
/// Uses the standard printer service types advertised by Link-OS
/// firmware: `_pdl-datastream._tcp` (raw 9100 / IPP RAW) and
/// `_printer._tcp` (LPR). Any SRV record found under those types is
/// reported as a candidate — the user picks one in the UI.
class ZebraPrinterService {
  static const _printServiceTypes = <String>[
    '_pdl-datastream._tcp.local',
    '_printer._tcp.local',
  ];

  final _log = LogService.instance;

  Future<List<ZebraPrinter>> discover({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final client = MDnsClient(rawDatagramSocketFactory: _datagramSocketFactory);
    final found = <ZebraPrinter>{};
    try {
      await client.start();
      _log.info('ZebraPrinterService: starting mDNS scan');

      for (final serviceType in _printServiceTypes) {
        final ptrStream = client
            .lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(serviceType))
            .timeout(timeout, onTimeout: (sink) => sink.close());

        await for (final ptr in ptrStream) {
          final srvStream = client.lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName),
          );
          await for (final srv in srvStream) {
            final ipStream = client.lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target),
            );
            await for (final ip in ipStream) {
              final printer = ZebraPrinter(
                name: _prettyName(ptr.domainName),
                host: ip.address.address,
                port: srv.port,
              );
              if (found.add(printer)) {
                _log.info(
                  'ZebraPrinterService: discovered ${printer.name} @ ${printer.host}:${printer.port}',
                );
              }
            }
          }
        }
      }
    } catch (e, st) {
      _log.error('ZebraPrinterService: discovery failed: $e\n$st');
      rethrow;
    } finally {
      client.stop();
    }

    return found.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<void> printZpl(
    ZebraPrinter printer,
    String zpl, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    _log.info(
      'ZebraPrinterService: sending ${zpl.length} bytes of ZPL to '
      '${printer.host}:${printer.port}',
    );
    Socket? socket;
    try {
      socket = await Socket.connect(printer.host, printer.port, timeout: timeout);
      socket.add(utf8.encode(zpl));
      await socket.flush();
    } finally {
      await socket?.close();
    }
  }

  Future<void> printTestLabel(ZebraPrinter printer) {
    const zpl =
        '^XA^CF0,50^FO50,50^FDRTS-LSC Test^FS^CF0,30^FO50,120^FDPrinter OK^FS^XZ';
    return printZpl(printer, zpl);
  }

  static String _prettyName(String fqdn) {
    final first = fqdn.split('.').first;
    return first.isEmpty ? fqdn : first;
  }

  static Future<RawDatagramSocket> _datagramSocketFactory(
    dynamic host,
    int port, {
    bool reuseAddress = true,
    bool reusePort = false,
    int ttl = 255,
  }) {
    return RawDatagramSocket.bind(
      host,
      port,
      reuseAddress: reuseAddress,
      reusePort: reusePort,
      ttl: ttl,
    );
  }
}
