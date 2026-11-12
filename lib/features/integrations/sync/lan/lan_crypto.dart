import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';

import '../../../../core/utils/secrets.dart';

// Чистый Dart: ключи устройства и код знакомства для синхронизации по сети.
// Своей криптографии здесь нет: канал — TLS, проверка кода — HMAC-SHA256,
// подлинность запроса — подпись ECDSA ключом сертификата.

/// Сертификат и ключ устройства (TLS) + секрет из первых версий (по сети
/// больше не ходит: устройство подтверждает себя подписью). Хранятся в
/// защищённом хранилище.
class LanIdentity {
  const LanIdentity({
    required this.certPem,
    required this.keyPem,
    required this.token,
  });

  /// Новый ключ P-256 и самоподписанный сертификат на 100 лет: доверие —
  /// не подпись центра, а отпечаток, который соседи запомнили при знакомстве.
  factory LanIdentity.generate() {
    final pair = CryptoUtils.generateEcKeyPair();
    final priv = pair.privateKey as ECPrivateKey;
    final pub = pair.publicKey as ECPublicKey;
    final csr = X509Utils.generateEccCsrPem({'CN': 'Enitor'}, priv, pub);
    return LanIdentity(
      certPem: X509Utils.generateSelfSignedCertificate(priv, csr, 36500),
      keyPem: CryptoUtils.encodeEcPrivateKeyToPem(priv),
      token: generateSecretToken(),
    );
  }

  final String certPem;
  final String keyPem;
  final String token;

  String get fingerprint => certFingerprint(certPem);
  String get tokenHash => lanTokenHash(token);
}

/// SHA-256 от DER сертификата, hex. Так же считается отпечаток сертификата,
/// который сосед показал при соединении ([derFingerprint]).
String certFingerprint(String pem) =>
    derFingerprint(CryptoUtils.getBytesFromPEMString(pem));

String derFingerprint(List<int> der) => sha256.convert(der).toString();

String lanTokenHash(String token) =>
    sha256.convert(utf8.encode(token)).toString();

// ── Подпись запроса ─────────────────────────────────────────────────────────

/// Подпись запроса к соседу с отпечатком [serverFp]. Секрет по сети не
/// ходит, а подпись связана с отпечатком соседа: другому устройству группы
/// сосед её не предъявит (тот сверит со своим отпечатком).
String lanAuthSign(LanIdentity id, String serverFp) =>
    CryptoUtils.ecSignatureToBase64(
      CryptoUtils.ecSign(
        CryptoUtils.ecPrivateKeyFromPem(id.keyPem),
        _authData(id.fingerprint, serverFp),
        algorithmName: 'SHA-256/ECDSA',
      ),
    );

/// Подпись [sig] сделана ключом сертификата [certPem] для [serverFp].
/// Что сертификат принадлежит устройству группы, проверяет вызывающий.
bool lanAuthVerify(String certPem, String serverFp, String sig) {
  try {
    final info = X509Utils.x509CertificateFromPem(certPem)
        .tbsCertificate!
        .subjectPublicKeyInfo
        .bytes!;
    return CryptoUtils.ecVerifyBase64(
      CryptoUtils.ecPublicKeyFromDerBytes(_hex(info)),
      _authData(certFingerprint(certPem), serverFp),
      sig,
      algorithm: 'SHA-256/ECDSA',
    );
  } catch (_) {
    return false;
  }
}

Uint8List _authData(String clientFp, String serverFp) =>
    utf8.encode('enitor-lan-auth-v1\n$clientFp\n$serverFp');

Uint8List _hex(String s) => Uint8List.fromList([
      for (var i = 0; i + 1 < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16),
    ]);

// ── Код знакомства ──────────────────────────────────────────────────────────

/// Алфавит Crockford base32: без I, L, O, U — их не спутать при вводе.
const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// 12 знаков = 60 бит. Короче нельзя: перехвативший обмен перебирает код у
/// себя, и 6 цифр он переберёт за доли секунды, а 60 бит — нет, тем более
/// пока код ещё действует (5 минут).
const kPairCodeLength = 12;

String generatePairCode([Random? random]) {
  final r = random ?? Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < kPairCodeLength; i++)
      _alphabet.codeUnitAt(r.nextInt(_alphabet.length)),
  ]);
}

/// `K7QF3MZPX2RA` → `K7QF-3MZP-X2RA`.
String formatPairCode(String code) => [
      for (var i = 0; i < code.length; i += 4)
        code.substring(i, min(i + 4, code.length)),
    ].join('-');

/// Ввод человека → код или null. Регистр, пробелы и дефисы не важны;
/// O читается как 0, I и L — как 1 (Crockford).
String? normalizePairCode(String input) {
  final s = input
      .toUpperCase()
      .replaceAll(RegExp(r'[\s\-_.]'), '')
      .replaceAll('O', '0')
      .replaceAll(RegExp('[IL]'), '1');
  if (s.length != kPairCodeLength) return null;
  for (final c in s.codeUnits) {
    if (!_alphabet.codeUnits.contains(c)) return null;
  }
  return s;
}

/// Подпись частей сообщения знакомства кодом. Части включают отпечатки
/// обоих сертификатов, какими их видит отправитель: посредник в сети
/// подставил бы свой сертификат, и подпись бы не сошлась.
String pairMac(String code, List<String> parts) {
  final key = Hmac(sha256, utf8.encode('enitor-pair-v1')).convert(
    utf8.encode(code),
  );
  return Hmac(sha256, key.bytes)
      .convert(utf8.encode(parts.join('\n')))
      .toString();
}
