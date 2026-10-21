import 'dart:convert';
import 'dart:typed_data';

import 'identity.dart';

/// What a QR code (or a pasted link) carries during pairing: the
/// initiating device's identity, a fresh session nonce and reachability
/// hints. The responder displays the SAS computed from this offer and
/// its own identity; the initiator displays the same code; the users
/// pair only if the codes match on both screens.
class PairingOffer {
  PairingOffer({
    required this.identity,
    required this.nonce,
    this.endpoints = const [],
  });

  static const int offerVersion = 1;

  final DeviceIdentity identity;
  final Uint8List nonce;

  /// Reachability hints, e.g. '192.168.1.20:47800' (LAN) or a Tailscale
  /// address. Hints only — trust comes from the keys, never the network.
  final List<String> endpoints;

  String encode() => jsonEncode({
        'v': offerVersion,
        'identity': identity.toJson(),
        'nonce': base64Encode(nonce),
        'endpoints': endpoints,
      });

  factory PairingOffer.decode(String text) {
    final json = (jsonDecode(text) as Map).cast<String, Object?>();
    final v = (json['v'] as num?)?.toInt() ?? 0;
    if (v != offerVersion) {
      throw FormatException('unsupported pairing offer version: $v');
    }
    return PairingOffer(
      identity: DeviceIdentity.fromJson(
          (json['identity'] as Map).cast<String, Object?>()),
      nonce: base64Decode(json['nonce'] as String),
      endpoints:
          (json['endpoints'] as List?)?.map((e) => '$e').toList() ?? const [],
    );
  }
}

/// A device this device has paired with — persisted by the app and used
/// to authenticate sync sessions.
class PairedDevice {
  const PairedDevice({
    required this.identity,
    required this.pairedAtIso,
    this.endpoints = const [],
  });

  final DeviceIdentity identity;
  final String pairedAtIso;
  final List<String> endpoints;

  Map<String, Object?> toJson() => {
        'identity': identity.toJson(),
        'pairedAt': pairedAtIso,
        'endpoints': endpoints,
      };

  factory PairedDevice.fromJson(Map<String, Object?> json) => PairedDevice(
        identity: DeviceIdentity.fromJson(
            (json['identity'] as Map).cast<String, Object?>()),
        pairedAtIso: json['pairedAt'] as String? ?? '',
        endpoints:
            (json['endpoints'] as List?)?.map((e) => '$e').toList() ?? const [],
      );
}

/// The pairing flow for one side. Validates the offer (its claimed
/// device id must actually derive from its public key — an offer cannot
/// spoof another device's id), computes the SAS for display, and yields
/// the [PairedDevice] to persist once the user confirms the codes match.
class PairingSession {
  PairingSession._({required this.local, required this.offer, required this.sas});

  final DeviceKeyPair local;
  final PairingOffer offer;

  /// The 6-digit code to show the user for comparison.
  final String sas;

  static Future<PairingSession> fromOffer({
    required DeviceKeyPair local,
    required PairingOffer offer,
  }) async {
    final claimedId =
        await deviceIdForPublicKey(offer.identity.publicKeyBytes);
    if (claimedId != offer.identity.deviceId) {
      throw const FormatException(
          'pairing offer device id does not match its public key');
    }
    final sas = await computeSas(
      publicKeyA: local.publicKeyBytes,
      publicKeyB: offer.identity.publicKeyBytes,
      nonce: offer.nonce,
    );
    return PairingSession._(local: local, offer: offer, sas: sas);
  }

  /// Called after the user confirms both screens show the same SAS.
  PairedDevice confirm() => PairedDevice(
        identity: offer.identity,
        pairedAtIso: DateTime.now().toUtc().toIso8601String(),
        endpoints: offer.endpoints,
      );
}
