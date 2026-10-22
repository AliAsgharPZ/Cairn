import 'dart:convert';
import 'dart:io';

import 'package:cairn_sync/cairn_sync.dart';
import 'package:test/test.dart';

void main() {
  _networkClassificationTests();
  group('network info', () {
    test('enumerates LAN addresses without throwing', () async {
      final addresses = await lanIpv4Addresses();
      expect(addresses, isA<List<String>>());
      for (final ip in addresses) {
        expect(InternetAddress.tryParse(ip), isNotNull, reason: ip);
        expect(ip.startsWith('127.'), isFalse, reason: 'loopback leaked: $ip');
      }
    });
  });

  group('peer discovery logic (packet level)', () {
    test('announcements register peers; self and garbage are ignored',
        () async {
      final a = PeerDiscovery(deviceId: 'device-a', displayName: 'Alpha');
      addTearDown(a.close);
      List<int> packet(String id, String name) => utf8.encode(jsonEncode({
            'v': 1,
            'kind': 'announce',
            'deviceId': id,
            'name': name,
            'syncPort': 47800,
            'overflowPort': 47801,
          }));
      a.handlePacket(
          packet('device-b', 'Beta'), InternetAddress('192.168.1.50'));
      a.handlePacket(
          packet('device-a', 'Alpha'), InternetAddress('192.168.1.51'));
      a.handlePacket(utf8.encode('not json'), InternetAddress('192.168.1.52'));
      a.handlePacket(
          packet('device-b', 'Beta Renamed'), InternetAddress('192.168.1.50'));
      expect(a.peers, hasLength(1));
      expect(a.peers.single.deviceId, 'device-b');
      expect(a.peers.single.displayName, 'Beta Renamed');
      expect(a.peers.single.ip, '192.168.1.50');
      expect(a.peers.single.syncEndpoint, '192.168.1.50:47800');
    });
  });

  group('peer discovery (loopback unicast)', () {
    test('two instances see each other and prune after close', () async {
      // The build sandbox silently drops all UDP (send returns 0);
      // GitHub CI runners do not. Skip only when the environment
      // itself cannot move a UDP packet over loopback.
      final probe = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4, 0);
      final probeSent = probe.send(
          utf8.encode('x'), InternetAddress.loopbackIPv4, probe.port);
      probe.close();
      if (probeSent == 0) {
        markTestSkipped('UDP unavailable in this environment');
        return;
      }
      final a = PeerDiscovery(
        deviceId: 'device-a',
        displayName: 'Alpha',
        port: 47913,
        announceEvery: const Duration(milliseconds: 300),
        peerTimeout: const Duration(seconds: 2),
      );
      final b = PeerDiscovery(
        deviceId: 'device-b',
        displayName: 'Beta',
        port: 47914,
        announceEvery: const Duration(milliseconds: 300),
        peerTimeout: const Duration(seconds: 2),
      );
      a.extraTargets.add(InternetAddress.loopbackIPv4);
      b.extraTargets.add(InternetAddress.loopbackIPv4);
      a.extraPorts.add(47914);
      b.extraPorts.add(47913);
      await a.start();
      await b.start();
      addTearDown(() async {
        await a.close();
        await b.close();
      });
      // Poll briefly: UDP on loopback should deliver within a second.
      var seen = <DiscoveredPeer>[];
      for (var i = 0; i < 30 && seen.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        seen = a.peers.where((p) => p.deviceId == 'device-b').toList();
      }
      expect(seen, hasLength(1), reason: 'A never discovered B');
      expect(seen.single.displayName, 'Beta');
      expect(seen.single.ip, '127.0.0.1');
      expect(seen.single.syncPort, 47800);
      // A device never discovers itself.
      expect(a.peers.where((p) => p.deviceId == 'device-a'), isEmpty);
    });
  });

  group('LAN pairing handshake', () {
    test('both sides confirm the same SAS and persist each other',
        () async {
      final alice = await DeviceKeyPair.generate();
      final bob = await DeviceKeyPair.generate();
      PairedDevice? bobSaved;
      String? sasShownToBob;
      final server = LanPairingServer();
      await server.start(
        local: bob,
        displayName: 'Bob PC',
        localEndpoints: () => ['127.0.0.1:47800'],
        onIncoming: (incoming) {
          sasShownToBob = incoming.sas;
          expect(incoming.peerName, 'Alice Phone');
          incoming.accept();
        },
        onPaired: (paired) => bobSaved = paired,
        port: 0,
      );
      addTearDown(server.close);

      String? sasShownToAlice;
      final aliceSaved = await LanPairingClient.pair(
        host: '127.0.0.1',
        port: server.port,
        local: alice,
        displayName: 'Alice Phone',
        localEndpoints: const ['127.0.0.1:47800'],
        confirmSas: (sas, peerName) async {
          sasShownToAlice = sas;
          expect(peerName, 'Bob PC');
          return true;
        },
      );
      expect(aliceSaved.identity.deviceId, bob.deviceId);
      expect(aliceSaved.endpoints, ['127.0.0.1:47800']);
      expect(bobSaved, isNotNull);
      expect(bobSaved!.identity.deviceId, alice.deviceId);
      expect(sasShownToAlice, isNotNull);
      expect(sasShownToAlice, sasShownToBob,
          reason: 'both screens must show the identical SAS');
      expect(sasShownToAlice, matches(RegExp(r'^\d{6}$')));
    });

    test('rejection on the responder side reaches the initiator',
        () async {
      final alice = await DeviceKeyPair.generate();
      final bob = await DeviceKeyPair.generate();
      final server = LanPairingServer();
      await server.start(
        local: bob,
        displayName: 'Bob PC',
        localEndpoints: () => const [],
        onIncoming: (incoming) => incoming.reject(),
        onPaired: (_) => fail('must not pair'),
        port: 0,
      );
      addTearDown(server.close);
      await expectLater(
        LanPairingClient.pair(
          host: '127.0.0.1',
          port: server.port,
          local: alice,
          displayName: 'Alice Phone',
          localEndpoints: const [],
          confirmSas: (_, __) async => true,
        ),
        throwsA(isA<PairingRejectedException>()),
      );
    });

    test('initiator cancelling at the SAS step aborts cleanly', () async {
      final alice = await DeviceKeyPair.generate();
      final bob = await DeviceKeyPair.generate();
      var paired = false;
      final server = LanPairingServer();
      await server.start(
        local: bob,
        displayName: 'Bob PC',
        localEndpoints: () => const [],
        onIncoming: (incoming) => incoming.accept(),
        onPaired: (_) => paired = true,
        port: 0,
      );
      addTearDown(server.close);
      await expectLater(
        LanPairingClient.pair(
          host: '127.0.0.1',
          port: server.port,
          local: alice,
          displayName: 'Alice Phone',
          localEndpoints: const [],
          confirmSas: (_, __) async => false,
        ),
        throwsA(isA<PairingRejectedException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(paired, isFalse);
    });
  });
}

void _networkClassificationTests() {
  group('interface classification (v1.3: mobile data is not a LAN)', () {
    test('cellular interfaces are recognized', () {
      for (final name in [
        'rmnet_data0',
        'rmnet0',
        'ccmni0',
        'pdp_ip0',
        'wwan0',
        'Cellular',
      ]) {
        expect(classifyInterfaceName(name), IfaceKind.cellular,
            reason: name);
      }
    });
    test('wifi and ethernet are LAN', () {
      for (final name in ['wlan0', 'Wi-Fi', 'eth0', 'Ethernet', 'en0']) {
        expect(classifyInterfaceName(name), IfaceKind.lan, reason: name);
      }
    });
    test('tunnels are VPN', () {
      for (final name in ['tun0', 'wg0', 'utun3', 'Tailscale']) {
        expect(classifyInterfaceName(name), IfaceKind.vpn, reason: name);
      }
    });
    test('unknown names are other', () {
      expect(classifyInterfaceName('{9F3A2B10-1111-2222-3333-444455556666}'),
          IfaceKind.other);
      expect(classifyInterfaceName('dummy0'), IfaceKind.other);
    });
  });
}
