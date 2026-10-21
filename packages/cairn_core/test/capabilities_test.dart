import 'package:cairn_core/cairn_core.dart';
import 'package:test/test.dart';

DeviceCapabilities caps(
  String id, {
  int cpu = 8,
  int ram = 8192,
  int disk = 20000,
  bool gpu = false,
  bool battery = false,
  Set<String> tools = const {},
}) =>
    DeviceCapabilities(
      deviceId: id,
      cpuCores: cpu,
      ramMb: ram,
      freeDiskMb: disk,
      hasGpu: gpu,
      onBattery: battery,
      toolIds: tools,
    );

void main() {
  group('OverflowRouter', () {
    const router = OverflowRouter();

    test('an eligible local device keeps the step — no gratuitous '
        'overflow even to a stronger peer', () {
      final decision = router.decide(
        requirements: const StepRequirements(minRamMb: 4096),
        local: caps('phone', ram: 6144),
        peers: [caps('pc', ram: 32768, cpu: 16, gpu: true)],
      );
      expect(decision.isLocal, isTrue);
      expect(decision.targetDeviceId, isNull);
    });

    test('insufficient local RAM overflows to the eligible peer', () {
      final decision = router.decide(
        requirements: const StepRequirements(minRamMb: 16384),
        local: caps('phone', ram: 6144),
        peers: [caps('pc', ram: 32768)],
      );
      expect(decision.targetDeviceId, 'pc');
      expect(decision.reason, contains('ram'));
    });

    test('a missing tool overflows; among eligible peers the higher '
        'score wins', () {
      final decision = router.decide(
        requirements:
            const StepRequirements(requiredToolIds: {'train.run'}),
        local: caps('phone', tools: {}),
        peers: [
          caps('pc-weak', cpu: 4, ram: 8192, tools: {'train.run'}),
          caps('pc-strong', cpu: 16, ram: 32768, gpu: true, tools: {'train.run'}),
        ],
      );
      expect(decision.targetDeviceId, 'pc-strong');
    });

    test('GPU requirement: local without GPU overflows to a GPU peer',
        () {
      final decision = router.decide(
        requirements: const StepRequirements(needsGpu: true),
        local: caps('phone', gpu: false),
        peers: [caps('pc', gpu: true)],
      );
      expect(decision.targetDeviceId, 'pc');
    });

    test('when nobody is eligible the step is blocked with the unmet '
        'requirements — never silently downgraded', () {
      final decision = router.decide(
        requirements: const StepRequirements(
            minRamMb: 65536, requiredToolIds: {'train.run'}),
        local: caps('phone', ram: 6144),
        peers: [caps('pc', ram: 32768, tools: {})],
      );
      expect(decision.isBlocked, isTrue);
      expect(decision.unmet.join(' '), contains('ram'));
      expect(decision.unmet.join(' '), contains('train.run'));
    });

    test('capabilities JSON round-trip (what peers exchange)', () {
      final original = caps('pc',
          cpu: 12, ram: 16384, gpu: true, tools: {'fs.read', 'train.run'});
      final back = DeviceCapabilities.fromJson(original.toJson());
      expect(back.deviceId, 'pc');
      expect(back.cpuCores, 12);
      expect(back.hasGpu, isTrue);
      expect(back.toolIds, {'fs.read', 'train.run'});
    });
  });
}
