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

DeviceCandidate cand(String id, LinkKind link,
        {int load = 0, int cpu = 8, int ram = 8192, bool gpu = false}) =>
    DeviceCandidate(
      caps: caps(id, cpu: cpu, ram: ram, gpu: gpu),
      link: link,
      load: load,
    );

void main() {
  const balancer = LoadBalancer();
  const light = StepRequirements(minRamMb: 1024);

  group('LoadBalancer (owner-corrected M8 policy)', () {
    test('steps split evenly between this device and a LAN peer', () {
      final decisions = balancer.decideAll(
        steps: List.filled(4, light),
        candidates: [
          cand('phone', LinkKind.local),
          cand('laptop', LinkKind.lan),
        ],
      );
      final targets = decisions
          .map((d) => d.isLocal ? 'phone' : d.targetDeviceId)
          .toList();
      // Equal devices alternate — nothing piles onto one machine.
      expect(targets.where((t) => t == 'phone'), hasLength(2));
      expect(targets.where((t) => t == 'laptop'), hasLength(2));
    });

    test('any device can serve any other — a stronger idle LAN peer '
        'takes the step even when local is eligible', () {
      final decision = balancer.decide(
        requirements: light,
        candidates: [
          cand('phone', LinkKind.local, cpu: 4, ram: 4096),
          cand('laptop', LinkKind.lan, cpu: 16, ram: 32768),
        ],
      );
      expect(decision.targetDeviceId, 'laptop');
    });

    test('load tips the balance: a busy strong device yields to an '
        'idle weaker one in the same tier', () {
      final decision = balancer.decide(
        requirements: light,
        candidates: [
          cand('laptop', LinkKind.lan, cpu: 16, ram: 32768, load: 9),
          cand('tablet', LinkKind.lan, cpu: 4, ram: 4096),
        ],
      );
      expect(decision.targetDeviceId, 'tablet');
    });

    test('internet is the last resort: a weak LAN device beats a '
        'monster over the internet', () {
      final decision = balancer.decide(
        requirements: light,
        candidates: [
          cand('phone', LinkKind.local, cpu: 4, ram: 4096),
          cand('server', LinkKind.internet, cpu: 64, ram: 131072, gpu: true),
        ],
      );
      expect(decision.isLocal, isTrue);
    });

    test('internet serves when only it can satisfy the step', () {
      final decision = balancer.decide(
        requirements: const StepRequirements(needsGpu: true),
        candidates: [
          cand('phone', LinkKind.local),
          cand('server', LinkKind.internet, gpu: true),
        ],
      );
      expect(decision.targetDeviceId, 'server');
      expect(decision.link, LinkKind.internet);
    });

    test('blocked, honestly, when nobody can satisfy the step', () {
      final decision = balancer.decide(
        requirements: const StepRequirements(minRamMb: 999999),
        candidates: [
          cand('phone', LinkKind.local),
          cand('laptop', LinkKind.lan),
        ],
      );
      expect(decision.isBlocked, isTrue);
      expect(decision.unmet.join(), contains('ram'));
    });
  });

  group('classifyHost', () {
    test('loopback is local, LAN ranges are lan, the rest is internet',
        () {
      expect(classifyHost('127.0.0.1'), LinkKind.local);
      expect(classifyHost('localhost'), LinkKind.local);
      expect(classifyHost('192.168.1.20'), LinkKind.lan);
      expect(classifyHost('10.0.0.5'), LinkKind.lan);
      expect(classifyHost('172.16.3.4'), LinkKind.lan);
      expect(classifyHost('100.101.102.103'), LinkKind.internet); // Tailscale
      expect(classifyHost('8.8.8.8'), LinkKind.internet);
      expect(classifyHost('my-server.example.com'), LinkKind.internet);
    });
  });
}
