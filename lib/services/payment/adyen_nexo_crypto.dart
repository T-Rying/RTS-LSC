import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// NEXO Terminal API encryption primitives for the Adyen Payments App
/// local-integration flow. Mirrors Adyen's "Protect payments" spec
/// (docs.adyen.com/point-of-sale/design-your-integration/choose-your-
/// architecture/local/protect):
///
/// * Derive `hmac_key` (32 B), `cipher_key` (32 B) and a reference IV
///   (16 B) from the shared passphrase via PBKDF2-HMAC-SHA1 with salt
///   `AdyenNexoV1Salt` and 4000 rounds — 80 bytes total.
/// * For each message, generate a fresh 16-byte `nonce`. The AES-CBC
///   IV is `derived_iv XOR nonce`. Encrypt the plaintext (the inner
///   JSON) with AES-256-CBC + PKCS#7 padding.
/// * HMAC the **plaintext** (not the ciphertext) with `hmac_key` using
///   HMAC-SHA256. Goes into the `SecurityTrailer.Hmac` field.
///
/// Decryption is symmetric: same nonce from the trailer, same derived
/// material, verify HMAC after decrypting to catch tampering.
class AdyenNexoCrypto {
  /// Fixed salt per Adyen's crypto spec. The length (15 bytes, no NUL
  /// terminator) matters — some libraries pad.
  static final Uint8List _salt =
      Uint8List.fromList(utf8.encode('AdyenNexoV1Salt'));
  static const int _pbkdf2Rounds = 4000;
  static const int _derivedKeyLength = 80;

  final Uint8List hmacKey;
  final Uint8List cipherKey;
  final Uint8List referenceIv;

  AdyenNexoCrypto._({
    required this.hmacKey,
    required this.cipherKey,
    required this.referenceIv,
  });

  /// Derive the three crypto keys from the shared passphrase.
  /// Cache the result per-passphrase if you call this hot — PBKDF2 at
  /// 4000 rounds is ~10 ms on a mid-range Android device.
  factory AdyenNexoCrypto.fromPassphrase(String passphrase) {
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA1Digest(), 64))
      ..init(Pbkdf2Parameters(_salt, _pbkdf2Rounds, _derivedKeyLength));
    final derived = pbkdf2.process(Uint8List.fromList(utf8.encode(passphrase)));
    return AdyenNexoCrypto._(
      hmacKey: Uint8List.fromList(derived.sublist(0, 32)),
      cipherKey: Uint8List.fromList(derived.sublist(32, 64)),
      referenceIv: Uint8List.fromList(derived.sublist(64, 80)),
    );
  }

  /// Encrypt [plaintext] (raw UTF-8 of the inner SaleToPOI JSON) with
  /// AES-256-CBC. Returns the ciphertext and the 16-byte nonce used —
  /// caller copies the nonce into the SecurityTrailer.
  NexoEncryptResult encrypt(Uint8List plaintext, {Random? random}) {
    final nonce = _randomBytes(16, random);
    final iv = _xor(referenceIv, nonce);
    final cipher = PaddedBlockCipher('AES/CBC/PKCS7')
      ..init(
        true,
        PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
          ParametersWithIV<KeyParameter>(KeyParameter(cipherKey), iv),
          null,
        ),
      );
    final ciphertext = cipher.process(plaintext);
    return NexoEncryptResult(ciphertext: ciphertext, nonce: nonce);
  }

  /// Decrypt [ciphertext] using the same `nonce` that came back in the
  /// response's SecurityTrailer. Caller must still verify the HMAC
  /// against the resulting plaintext before trusting it.
  Uint8List decrypt(Uint8List ciphertext, Uint8List nonce) {
    if (nonce.length != 16) {
      throw ArgumentError('NEXO nonce must be 16 bytes, got ${nonce.length}');
    }
    final iv = _xor(referenceIv, nonce);
    final cipher = PaddedBlockCipher('AES/CBC/PKCS7')
      ..init(
        false,
        PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
          ParametersWithIV<KeyParameter>(KeyParameter(cipherKey), iv),
          null,
        ),
      );
    return cipher.process(ciphertext);
  }

  /// HMAC-SHA256 of [message] (the plaintext — spec says to sign the
  /// original, not the ciphertext). Returns the raw digest; caller
  /// Base64-encodes it for the SecurityTrailer.
  Uint8List hmac(Uint8List message) {
    final mac = HMac(SHA256Digest(), 64)..init(KeyParameter(hmacKey));
    return mac.process(message);
  }

  /// Constant-time-ish verification of an HMAC digest. Not truly
  /// constant-time but close enough — NEXO responses aren't an attacker-
  /// chosen oracle.
  bool verifyHmac(Uint8List message, Uint8List expected) {
    final actual = hmac(message);
    if (actual.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual[i] ^ expected[i];
    }
    return diff == 0;
  }

  static Uint8List _xor(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      throw ArgumentError('xor length mismatch: ${a.length} vs ${b.length}');
    }
    final out = Uint8List(a.length);
    for (var i = 0; i < a.length; i++) {
      out[i] = a[i] ^ b[i];
    }
    return out;
  }

  static Uint8List _randomBytes(int len, [Random? random]) {
    final r = random ?? Random.secure();
    final out = Uint8List(len);
    for (var i = 0; i < len; i++) {
      out[i] = r.nextInt(256);
    }
    return out;
  }
}

class NexoEncryptResult {
  final Uint8List ciphertext;
  final Uint8List nonce;
  NexoEncryptResult({required this.ciphertext, required this.nonce});
}
