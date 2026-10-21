import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// A device's long-term identity: an Ed25519 key pair. The device id is
/// derived from the public key (first 8 bytes of its SHA-256, hex), so
/// it is unforgeable and stable. The private key never leaves the device;
/// the app stores it in the platform secure store — this package only
/// handles the key material as bytes.
class DeviceKeyPair {
  DeviceKeyPair._(this._keyPair, this.publicKeyBytes, this.deviceId);

  final KeyPair _keyPair;

  /// Raw 32-byte Ed25519 public key.
  final Uint8List publicKeyBytes;

  /// 16-hex-char fingerprint of the public key.
  final String deviceId;

  static Future<DeviceKeyPair> generate() async {
    final kp = await Ed25519().newKeyPair();
    return _fromKeyPair(kp);
  }

  /// Rebuilds a key pair from stored seed bytes (the private key material
  /// the app kept in secure storage).
  static Future<DeviceKeyPair> fromSeed(List<int> seed) async {
    final kp = await Ed25519().newKeyPairFromSeed(seed);
    return _fromKeyPair(kp);
  }

  static Future<DeviceKeyPair> _fromKeyPair(KeyPair kp) async {
    final pub = await kp.extractPublicKey();
    final pubBytes = Uint8List.fromList((pub as SimplePublicKey).bytes);
    return DeviceKeyPair._(kp, pubBytes, await deviceIdForPublicKey(pubBytes));
  }

  /// The seed to persist (32 bytes) — handle like a password.
  Future<Uint8List> extractSeed() async {
    final data = await _keyPair.extract();
    return Uint8List.fromList(
        await (data as SimpleKeyPairData).extractPrivateKeyBytes());
  }

  Future<Uint8List> sign(List<int> message) async {
    final sig = await Ed25519().sign(message, keyPair: _keyPair);
    return Uint8List.fromList(sig.bytes);
  }

  static Future<bool> verify(
      List<int> publicKey, List<int> message, List<int> signature) {
    return Ed25519().verify(
      message,
      signature: Signature(signature,
          publicKey:
              SimplePublicKey(publicKey, type: KeyPairType.ed25519)),
    );
  }

  String get publicKeyBase64 => base64Encode(publicKeyBytes);
}

/// The device id for a raw public key: first 8 bytes of SHA-256, hex.
Future<String> deviceIdForPublicKey(List<int> publicKey) async {
  final hash = await Sha256().hash(publicKey);
  return hash.bytes
      .sublist(0, 8)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

/// A public view of a device: everything a peer needs to know.
class DeviceIdentity {
  const DeviceIdentity({
    required this.deviceId,
    required this.publicKeyBytes,
    required this.displayName,
  });

  final String deviceId;
  final Uint8List publicKeyBytes;
  final String displayName;

  Map<String, Object?> toJson() => {
        'deviceId': deviceId,
        'publicKey': base64Encode(publicKeyBytes),
        'displayName': displayName,
      };

  factory DeviceIdentity.fromJson(Map<String, Object?> json) =>
      DeviceIdentity(
        deviceId: json['deviceId'] as String,
        publicKeyBytes: base64Decode(json['publicKey'] as String),
        displayName: json['displayName'] as String? ?? '',
      );
}

/// The Short Authentication String both devices display during pairing:
/// a 6-digit code derived from both public keys and the session nonce.
/// Both sides compute the identical code from the same inputs, so a
/// man-in-the-middle (who cannot know the real keys) produces a
/// different code and is caught by the users comparing digits.
Future<String> computeSas({
  required List<int> publicKeyA,
  required List<int> publicKeyB,
  required List<int> nonce,
}) async {
  // Sort the keys so both sides hash the same byte sequence regardless
  // of who initiated.
  final first = _compareBytes(publicKeyA, publicKeyB) <= 0
      ? publicKeyA
      : publicKeyB;
  final second = identical(first, publicKeyA) ? publicKeyB : publicKeyA;
  final hash = await Sha256().hash([...first, ...second, ...nonce]);
  final v = ByteData.view(Uint8List.fromList(hash.bytes.sublist(0, 4)).buffer)
      .getUint32(0, Endian.big);
  return (v % 1000000).toString().padLeft(6, '0');
}

int _compareBytes(List<int> a, List<int> b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
}

/// Cryptographically secure random bytes (pairing nonces).
Uint8List secureRandomBytes(int length) {
  final rng = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
}
