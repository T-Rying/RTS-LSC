import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../log_service.dart';
import 'adyen_app_link_service.dart';
import 'adyen_nexo_crypto.dart';

/// Builds, encrypts, sends and parses NEXO Terminal API messages over
/// the Adyen Android Payments app's `/nexo` App Link.
///
/// A SaleToPOIRequest that goes into `/nexo` has three top-level parts:
///
/// * `MessageHeader` — plain-text metadata Adyen uses to route the
///   request: MessageClass/Category/Type, ProtocolVersion 3.0,
///   ServiceID (unique per request), SaleID (identifies this POS),
///   POIID (the boarded installationId).
/// * `NexoBlob` — Base64 of the AES-256-CBC-encrypted inner request
///   body (e.g. `{"PaymentRequest":{…}}` for a card sale).
/// * `SecurityTrailer` — crypto metadata: AdyenCryptoVersion=1,
///   KeyIdentifier+KeyVersion (match what's set up in Adyen CA),
///   Base64(HMAC-SHA256 of inner plaintext), Base64(random 16-byte
///   nonce) — the nonce XOR's with the PBKDF2-derived IV to get the
///   actual AES IV.
///
/// The whole SaleToPOIRequest is then Base64URL-encoded and launched
/// as `https://www.adyen.com/{test/}nexo?request=…&returnUrl=…`.
class AdyenNexo {
  final AdyenNexoCrypto crypto;
  final AdyenAppLinkService appLinks;
  final String appLinkBase; // e.g. 'https://www.adyen.com/test'
  final String keyIdentifier;
  final int keyVersion;
  final String saleId;
  final String poiId; // = Payments app installationId from boarding
  final LogService _log = LogService.instance;

  AdyenNexo({
    required this.crypto,
    required this.appLinks,
    required this.appLinkBase,
    required this.keyIdentifier,
    required this.keyVersion,
    required this.saleId,
    required this.poiId,
  });

  /// Round-trip a NEXO message: build+encrypt → launch `/nexo` →
  /// parse+decrypt the reply. [innerRequest] is the unencrypted body
  /// map (e.g. `{"PaymentRequest": {...}}`) whose single key pairs
  /// with `messageCategory` (e.g. `"Payment"`).
  ///
  /// [serviceId] uniquely identifies this request within the sale
  /// system and MUST be echoed back in the response — caller should
  /// generate a fresh one per call. We use 10 digits by convention.
  ///
  /// Returns the decrypted inner response body (e.g.
  /// `{"PaymentResponse": {...}}`). Throws:
  ///   * [TimeoutException] if the Adyen app doesn't call back.
  ///   * [StateError] on any crypto / parse failure (HMAC mismatch,
  ///     missing fields, etc.) — caller should treat as "unknown
  ///     transaction state" rather than retrying blindly.
  Future<Map<String, dynamic>> roundTrip({
    required String messageCategory,
    required String serviceId,
    required Map<String, dynamic> innerRequest,
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final header = <String, dynamic>{
      'MessageClass': 'Service',
      'MessageCategory': messageCategory,
      'MessageType': 'Request',
      'ServiceID': serviceId,
      'SaleID': saleId,
      'POIID': poiId,
      'ProtocolVersion': '3.0',
    };

    // Per Adyen's reference implementation (adyen-java-api-library
    // TerminalLocalAPI + NexoCrypto), the plaintext that gets
    // encrypted is the ENTIRE unencrypted SaleToPOIRequest JSON —
    // MessageHeader + body — not just the body. The wire envelope
    // duplicates the MessageHeader at the top so Adyen can route
    // without decrypting; they still verify the embedded copy
    // matches after decrypting.
    final saleToPoiInner = <String, dynamic>{
      'MessageHeader': header,
      ...innerRequest,
    };
    final plaintextJson = jsonEncode(<String, dynamic>{
      'SaleToPOIRequest': saleToPoiInner,
    });
    final plaintext = Uint8List.fromList(utf8.encode(plaintextJson));
    final encrypted = crypto.encrypt(plaintext);
    final hmacDigest = crypto.hmac(plaintext);

    final envelope = <String, dynamic>{
      'SaleToPOIRequest': <String, dynamic>{
        'MessageHeader': header,
        'NexoBlob': base64.encode(encrypted.ciphertext),
        'SecurityTrailer': <String, dynamic>{
          'AdyenCryptoVersion': 1,
          'KeyIdentifier': keyIdentifier,
          'KeyVersion': keyVersion,
          'Hmac': base64.encode(hmacDigest),
          'Nonce': base64.encode(encrypted.nonce),
        },
      },
    };

    final envelopeJson = jsonEncode(envelope);
    final requestParam = base64Url
        .encode(utf8.encode(envelopeJson))
        .replaceAll('=', '');
    _log.info('Adyen NEXO: launching /nexo serviceId=$serviceId '
        'category=$messageCategory envelopeBytes=${envelopeJson.length}');

    final url = Uri.parse(
      '$appLinkBase/nexo'
      '?request=$requestParam'
      '&returnUrl=${Uri.encodeQueryComponent(AdyenAppLinkService.returnUrl)}',
    );

    final returnUri = await appLinks.launchAndAwaitReturn(url, timeout: timeout);
    return _parseResponse(returnUri, expectedServiceId: serviceId);
  }

  Map<String, dynamic> _parseResponse(
    Uri returnUri, {
    required String expectedServiceId,
  }) {
    final responseParam = returnUri.queryParameters['response'] ??
        returnUri.queryParameters['request']; // docs are inconsistent
    if (responseParam == null || responseParam.isEmpty) {
      final err = returnUri.queryParameters['error'];
      throw StateError(err != null && err.isNotEmpty
          ? 'NEXO /nexo returned error: $err'
          : 'NEXO /nexo return had no response payload');
    }

    final envelopeJson = utf8.decode(base64Url.decode(base64Url.normalize(responseParam)));
    final envelope = jsonDecode(envelopeJson);
    if (envelope is! Map<String, dynamic>) {
      throw StateError('NEXO response envelope is not a JSON object');
    }
    final saleToPOI = envelope['SaleToPOIResponse'];
    if (saleToPOI is! Map<String, dynamic>) {
      throw StateError('NEXO response missing SaleToPOIResponse');
    }

    final header = saleToPOI['MessageHeader'] as Map<String, dynamic>?;
    if (header?['ServiceID'] != expectedServiceId) {
      throw StateError(
          'NEXO response ServiceID mismatch — expected $expectedServiceId '
          'got ${header?['ServiceID']} (possible replay or stale return)');
    }

    final trailer = saleToPOI['SecurityTrailer'] as Map<String, dynamic>?;
    final blobB64 = saleToPOI['NexoBlob'] as String?;
    if (trailer == null || blobB64 == null) {
      throw StateError('NEXO response missing NexoBlob or SecurityTrailer');
    }

    final nonce = base64.decode(trailer['Nonce'] as String);
    final expectedHmac = base64.decode(trailer['Hmac'] as String);
    final ciphertext = base64.decode(blobB64);

    final plaintext = crypto.decrypt(ciphertext, nonce);
    if (!crypto.verifyHmac(plaintext, expectedHmac)) {
      throw StateError('NEXO response HMAC verification failed — '
          'discarding message (possible tampering or wrong shared key)');
    }

    // Decrypted plaintext is the full
    // `{"SaleToPOIResponse":{"MessageHeader":{...},"PaymentResponse":{...}}}`
    // JSON (mirror of the request shape). Unwrap twice so the caller
    // gets back `{"PaymentResponse": {...}}` to map onto a
    // PaymentResult.
    final decoded = jsonDecode(utf8.decode(plaintext));
    if (decoded is! Map<String, dynamic>) {
      throw StateError('NEXO decrypted payload is not a JSON object');
    }
    final inner = decoded['SaleToPOIResponse'];
    if (inner is! Map<String, dynamic>) {
      throw StateError(
          'NEXO decrypted payload missing SaleToPOIResponse: '
          '${decoded.keys.join(",")}');
    }
    final body = <String, dynamic>{};
    inner.forEach((k, v) {
      if (k == 'MessageHeader') return;
      body[k] = v;
    });
    return body;
  }
}
