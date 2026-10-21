import 'dart:convert';

import 'package:cairn_sync/cairn_sync.dart';
import 'package:test/test.dart';

void main() {
  group('DeviceKeyPair', () {
    test('sign/verify round-trip; tampered messages fail', () async {
      final kp = await DeviceKeyPair.generate();
      final message = utf8.encode('cairn sync hello');
      final signature = await kp.sign(message);
      expect(
          await DeviceKeyPair.verify(kp.publicKeyBytes, message, signature),
          isTrue);
      expect(
          await DeviceKeyPair.verify(
              kp.publicKeyBytes, utf8.encode('tampered'), signature),
          isFalse);
    });

    test('the device id is stable across a seed restore', () async {
      final kp = await DeviceKeyPair.generate();
      final seed = await kp.extractSeed();
      final restored = await DeviceKeyPair.fromSeed(seed);
      expect(restored.deviceId, kp.deviceId);
      expect(restored.publicKeyBytes, kp.publicKeyBytes);
      expect(kp.deviceId, hasLength(16));
    });
  });

  group('SAS', () {
    test('both sides compute the identical code; inputs matter', () async {
      final a = await DeviceKeyPair.generate();
      final b = await DeviceKeyPair.generate();
      final nonce = secureRandomBytes(16);

      final ab = await computeSas(
          publicKeyA: a.publicKeyBytes,
          publicKeyB: b.publicKeyBytes,
          nonce: nonce);
      final ba = await computeSas(
          publicKeyA: b.publicKeyBytes,
          publicKeyB: a.publicKeyBytes,
          nonce: nonce);
      expect(ab, ba);
      expect(ab, matches(RegExp(r'^\d{6}$')));

      final otherNonce = await computeSas(
          publicKeyA: a.publicKeyBytes,
          publicKeyB: b.publicKeyBytes,
          nonce: secureRandomBytes(16));
      expect(otherNonce, isNot(ab));
    });
  });

  group('Pairing', () {
    test('offer encode/decode round-trip (the QR payload)', () async {
      final kp = await DeviceKeyPair.generate();
      final offer = PairingOffer(
        identity: DeviceIdentity(
          deviceId: kp.deviceId,
          publicKeyBytes: kp.publicKeyBytes,
          displayName: 'Ali Phone',
        ),
        nonce: secureRandomBytes(16),
        endpoints: const ['192.168.1.20:47800'],
      );
      final back = PairingOffer.decode(offer.encode());
      expect(back.identity.deviceId, kp.deviceId);
      expect(back.identity.displayName, 'Ali Phone');
      expect(back.endpoints, ['192.168.1.20:47800']);
      expect(back.nonce, offer.nonce);
    });

    test('a session validates the offer and confirms into a PairedDevice',
        () async {
      final phone = await DeviceKeyPair.generate();
      final pc = await DeviceKeyPair.generate();
      final offer = PairingOffer(
        identity: DeviceIdentity(
          deviceId: pc.deviceId,
          publicKeyBytes: pc.publicKeyBytes,
          displayName: 'Desktop',
        ),
        nonce: secureRandomBytes(16),
      );
      final session = await PairingSession.fromOffer(local: phone, offer: offer);
      expect(session.sas, matches(RegExp(r'^\d{6}$')));
      final paired = session.confirm();
      expect(paired.identity.deviceId, pc.deviceId);
      final roundTrip = PairedDevice.fromJson(paired.toJson());
      expect(roundTrip.identity.deviceId, pc.deviceId);
    });

    test('an offer spoofing another device id is refused', () async {
      final phone = await DeviceKeyPair.generate();
      final pc = await DeviceKeyPair.generate();
      final spoofed = PairingOffer(
        identity: DeviceIdentity(
          deviceId: phone.deviceId, // claims the phone's id…
          publicKeyBytes: pc.publicKeyBytes, // …with the pc's key
          displayName: 'Evil',
        ),
        nonce: secureRandomBytes(16),
      );
      expect(
        () => PairingSession.fromOffer(local: phone, offer: spoofed),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
