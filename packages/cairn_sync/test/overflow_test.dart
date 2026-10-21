import 'dart:async';

import 'package:cairn_sync/cairn_sync.dart';
import 'package:test/test.dart';

PairedDevice paired(DeviceKeyPair other) => PairedDevice(
      identity: DeviceIdentity(
        deviceId: other.deviceId,
        publicKeyBytes: other.publicKeyBytes,
        displayName: 'peer',
      ),
      pairedAtIso: '2026-10-21T00:00:00Z',
    );

void main() {
  group('Overflow protocol', () {
    late DeviceKeyPair phone;
    late DeviceKeyPair pc;

    setUp(() async {
      phone = await DeviceKeyPair.generate();
      pc = await DeviceKeyPair.generate();
    });

    /// Starts a server session on in-memory streams and returns the
    /// connected client + a future completing when the server ends.
    Future<(OverflowClient, Future<void>)> connect({
      bool allowSensitive = false,
    }) async {
      final a2b = StreamController<List<int>>();
      final b2a = StreamController<List<int>>();
      final server = OverflowServerSession(
        local: pc,
        allowedPeers: [paired(phone)],
        allowedToolIds: {'echo', 'train.run'},
        sensitiveToolIds: {'train.run'},
        allowSensitiveRemote: allowSensitive,
        handler: (toolId, args) async => OverflowToolReply(
            ok: true, output: '$toolId:${args['text'] ?? ''}'),
      );
      final serverFuture = server.run(a2b.stream, b2a.sink);
      final client = await OverflowClient.connect(b2a.stream, a2b.sink,
          local: phone, peer: paired(pc));
      return (client, serverFuture);
    }

    test('an allowed tool executes on the peer and returns its result',
        () async {
      final (client, serverFuture) = await connect();
      final reply = await client.invoke('echo', {'text': 'hello'});
      expect(reply.ok, isTrue);
      expect(reply.output, 'echo:hello');
      await client.close();
    });

    test('a tool the peer does not offer is refused by policy', () async {
      final (client, _) = await connect();
      final reply = await client.invoke('shell.run', {'cmd': 'ls'});
      expect(reply.ok, isFalse);
      expect(reply.output, contains('not offered'));
      await client.close();
    });

    test('sensitive tools are refused remotely by default and execute '
        'only when the owner enabled them', () async {
      final (strictClient, _) = await connect();
      final refused = await strictClient.invoke('train.run', {});
      expect(refused.ok, isFalse);
      expect(refused.output, contains('sensitive'));
      await strictClient.close();

      final (openClient, _) = await connect(allowSensitive: true);
      final allowed = await openClient.invoke('train.run', {});
      expect(allowed.ok, isTrue);
      await openClient.close();
    });

    test('an unpaired stranger cannot even complete the handshake',
        () async {
      final stranger = await DeviceKeyPair.generate();
      final a2b = StreamController<List<int>>();
      final b2a = StreamController<List<int>>();
      final server = OverflowServerSession(
        local: pc,
        allowedPeers: [paired(phone)],
        allowedToolIds: {'echo'},
        sensitiveToolIds: const {},
        handler: (_, __) async =>
            const OverflowToolReply(ok: true, output: 'x'),
      );
      // Capture the server's error immediately so it is handled even
      // while the client-side expectation runs first.
      final serverError = server
          .run(a2b.stream, b2a.sink)
          .then<Object?>((_) => null, onError: (Object e) => e);
      await expectLater(
        OverflowClient.connect(b2a.stream, a2b.sink,
            local: stranger, peer: paired(pc)),
        throwsStateError,
      );
      expect(await serverError, isA<StateError>());
    });
  });
}
