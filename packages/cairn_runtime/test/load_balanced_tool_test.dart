import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:test/test.dart';

class _LocalTool extends Tool {
  int calls = 0;
  @override
  String get id => 'test.work';
  @override
  String get description => 'Does work.';
  @override
  bool get sensitive => false;
  @override
  Future<ToolResult> run(
      Map<String, Object?> input, ToolContext context) async {
    calls++;
    return ToolResult.success('local result');
  }
}

DeviceCapabilities _caps(String id, {int cpu = 8}) => DeviceCapabilities(
      deviceId: id,
      cpuCores: cpu,
      ramMb: 8192,
      freeDiskMb: 20000,
      toolIds: const {'test.work'},
    );

void main() {
  test('consecutive calls alternate between local and a LAN peer',
      () async {
    final tracker = LoadTracker();
    final local = _LocalTool();
    final remoteCalls = <String>[];
    final tool = LoadBalancedTool(
      inner: local,
      localDeviceId: 'phone',
      tracker: tracker,
      candidates: () async => [
        DeviceCandidate(
          caps: _caps('phone'),
          link: LinkKind.local,
          load: tracker.of('phone'),
        ),
        DeviceCandidate(
          caps: _caps('laptop'),
          link: LinkKind.lan,
          load: tracker.of('laptop'),
        ),
      ],
      executeRemote: (deviceId, input) async {
        remoteCalls.add(deviceId);
        return ToolResult.success('remote result');
      },
    );
    const context = ToolContext(
        projectId: 'p', agentId: 'a', taskId: 't');
    final r1 = await tool.run(const {}, context);
    final r2 = await tool.run(const {}, context);
    final r3 = await tool.run(const {}, context);
    final r4 = await tool.run(const {}, context);
    // Even split over 4 calls, results really executed somewhere.
    expect(local.calls, 2);
    expect(remoteCalls, ['laptop', 'laptop']);
    expect([r1.output, r2.output, r3.output, r4.output],
        containsAll(['local result', 'remote result']));
    expect(tracker.of('phone'), 2);
    expect(tracker.of('laptop'), 2);
  });

  test('fails honestly when no device offers the tool', () async {
    final tracker = LoadTracker();
    final tool = LoadBalancedTool(
      inner: _LocalTool(),
      localDeviceId: 'phone',
      tracker: tracker,
      candidates: () async => [
        DeviceCandidate(
          caps: const DeviceCapabilities(
            deviceId: 'phone',
            cpuCores: 8,
            ramMb: 8192,
            freeDiskMb: 20000,
            toolIds: {},
          ),
          link: LinkKind.local,
        ),
      ],
      executeRemote: (deviceId, input) async =>
          ToolResult.success('never reached'),
    );
    final result = await tool.run(
        const {}, const ToolContext(projectId: 'p', agentId: 'a', taskId: 't'));
    expect(result.ok, isFalse);
    expect(result.output, contains('No device can run'));
  });
}
