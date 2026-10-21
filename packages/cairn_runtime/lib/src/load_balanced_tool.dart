import 'package:cairn_core/cairn_core.dart';

import 'tool_registry.dart';

/// Assignment counts for one run, shared by every balanced tool, so
/// the [LoadBalancer] sees the whole run's spread — steps in a run
/// execute sequentially, so "load" here means steps already given
/// to each device in this run (that is what makes step 2 go to the
/// other device after step 1 stayed home).
class LoadTracker {
  final Map<String, int> _assigned = {};

  int of(String deviceId) => _assigned[deviceId] ?? 0;

  void recordAssignment(String deviceId) =>
      _assigned[deviceId] = of(deviceId) + 1;
}

/// Supplies the current candidates (local device + reachable paired
/// peers), with [LoadTracker] counts already applied.
typedef BalancedCandidates = Future<List<DeviceCandidate>> Function();

/// Executes one invocation of a tool on a chosen peer device.
typedef RemoteToolExecutor = Future<ToolResult> Function(
    String deviceId, Map<String, Object?> input);

/// A tool that may run here or on a paired peer, decided per call by
/// the [LoadBalancer] (multi-directional overflow with load
/// balancing): any device may serve any other, steps split across
/// the capable devices on the local network first, and the internet
/// is the last resort. Approval gates and policy checks happen in
/// the orchestrator before this runs, and the executing peer
/// re-validates against its own policy — a refusal comes back as a
/// normal failed [ToolResult].
class LoadBalancedTool extends Tool {
  LoadBalancedTool({
    required this.inner,
    required this.localDeviceId,
    required this.candidates,
    required this.executeRemote,
    required this.tracker,
    this.balancer = const LoadBalancer(),
  });

  /// The local implementation (also the metadata source).
  final Tool inner;
  final String localDeviceId;
  final BalancedCandidates candidates;
  final RemoteToolExecutor executeRemote;
  final LoadTracker tracker;
  final LoadBalancer balancer;

  @override
  String get id => inner.id;

  @override
  String get description => inner.description;

  @override
  bool get sensitive => inner.sensitive;

  @override
  bool get requiresNetwork => inner.requiresNetwork;

  @override
  Future<ToolResult> run(
      Map<String, Object?> input, ToolContext context) async {
    final List<DeviceCandidate> cands;
    try {
      cands = await candidates();
    } catch (_) {
      // Routing information unavailable (e.g. a peer probe failed at
      // the call site): executing locally is real execution, not a
      // fallback fiction.
      return inner.run(input, context);
    }
    final decision = balancer.decide(
      requirements: StepRequirements(requiredToolIds: {inner.id}),
      candidates: cands,
    );
    if (decision.isBlocked) {
      return ToolResult.failure(
          'No device can run ${inner.id}: ${decision.unmet.join('; ')}');
    }
    if (decision.isLocal) {
      tracker.recordAssignment(localDeviceId);
      return inner.run(input, context);
    }
    final target = decision.targetDeviceId!;
    tracker.recordAssignment(target);
    return executeRemote(target, input);
  }
}
