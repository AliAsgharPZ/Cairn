// Compute overflow (M8): capability-scored, per-step routing between
// symmetric peer devices. The governing rule (user-corrected design):
// a step runs LOCALLY unless this device cannot satisfy the step's
// hard requirements — only then does it overflow to the best eligible
// paired peer. There is no fixed RAM threshold; requirements are
// declared per step and matched against measured capabilities. If no
// device is eligible, the step is blocked with the unmet requirements
// listed — never silently downgraded.

/// What a device can offer, measured and exchanged between peers.
class DeviceCapabilities {
  const DeviceCapabilities({
    required this.deviceId,
    required this.cpuCores,
    required this.ramMb,
    required this.freeDiskMb,
    this.hasGpu = false,
    this.onBattery = false,
    this.toolIds = const {},
  });

  final String deviceId;
  final int cpuCores;
  final int ramMb;
  final int freeDiskMb;
  final bool hasGpu;
  final bool onBattery;

  /// Tools this device can execute (its registry ids).
  final Set<String> toolIds;

  Map<String, Object?> toJson() => {
        'deviceId': deviceId,
        'cpuCores': cpuCores,
        'ramMb': ramMb,
        'freeDiskMb': freeDiskMb,
        'hasGpu': hasGpu,
        'onBattery': onBattery,
        'toolIds': toolIds.toList(),
      };

  factory DeviceCapabilities.fromJson(Map<String, Object?> json) =>
      DeviceCapabilities(
        deviceId: json['deviceId'] as String,
        cpuCores: (json['cpuCores'] as num).toInt(),
        ramMb: (json['ramMb'] as num).toInt(),
        freeDiskMb: (json['freeDiskMb'] as num).toInt(),
        hasGpu: json['hasGpu'] as bool? ?? false,
        onBattery: json['onBattery'] as bool? ?? false,
        toolIds:
            (json['toolIds'] as List?)?.map((e) => '$e').toSet() ?? const {},
      );
}

/// What one step needs. All fields are hard requirements except the
/// relative cost used for scoring among eligible peers.
class StepRequirements {
  const StepRequirements({
    this.minRamMb = 0,
    this.minCpuCores = 1,
    this.minFreeDiskMb = 0,
    this.needsGpu = false,
    this.requiredToolIds = const {},
    this.workUnits = 1,
  });

  final int minRamMb;
  final int minCpuCores;
  final int minFreeDiskMb;
  final bool needsGpu;
  final Set<String> requiredToolIds;

  /// Relative size of the step (for reporting/scoring only).
  final int workUnits;
}

/// The unmet hard requirements of a step on one device (empty = eligible).
List<String> unmetRequirements(
    StepRequirements req, DeviceCapabilities caps) {
  final unmet = <String>[];
  if (caps.ramMb < req.minRamMb) {
    unmet.add('ram: needs ${req.minRamMb}MB, has ${caps.ramMb}MB');
  }
  if (caps.cpuCores < req.minCpuCores) {
    unmet.add('cpu: needs ${req.minCpuCores} cores, has ${caps.cpuCores}');
  }
  if (caps.freeDiskMb < req.minFreeDiskMb) {
    unmet.add(
        'disk: needs ${req.minFreeDiskMb}MB free, has ${caps.freeDiskMb}MB');
  }
  if (req.needsGpu && !caps.hasGpu) unmet.add('gpu: required, absent');
  for (final tool in req.requiredToolIds) {
    if (!caps.toolIds.contains(tool)) unmet.add('tool: $tool not available');
  }
  return unmet;
}

/// A relative capability score for an ELIGIBLE device — used only to
/// rank eligible peers against each other (never to pull a step away
/// from an eligible local device).
int capabilityScore(DeviceCapabilities caps) {
  var score = caps.cpuCores * 100 + (caps.ramMb ~/ 512) * 10;
  if (caps.hasGpu) score += 500;
  if (caps.onBattery) score -= 200;
  return score;
}

/// Where a step will run, and why.
class RouteDecision {
  const RouteDecision.local(this.reason)
      : targetDeviceId = null,
        unmet = const [];
  const RouteDecision.peer(this.targetDeviceId, this.reason)
      : unmet = const [];
  const RouteDecision.blocked(this.unmet, this.reason)
      : targetDeviceId = null;

  /// Null when the step stays local (or is blocked).
  final String? targetDeviceId;
  final String reason;

  /// For blocked decisions: the requirements no device could meet.
  final List<String> unmet;

  bool get isLocal => targetDeviceId == null && unmet.isEmpty;
  bool get isBlocked => unmet.isNotEmpty;
}

/// The overflow router. Pure and deterministic.
class OverflowRouter {
  const OverflowRouter();

  RouteDecision decide({
    required StepRequirements requirements,
    required DeviceCapabilities local,
    required List<DeviceCapabilities> peers,
  }) {
    final localUnmet = unmetRequirements(requirements, local);
    if (localUnmet.isEmpty) {
      return const RouteDecision.local(
          'local device satisfies the step requirements');
    }

    // Overflow: rank eligible peers by capability score.
    final eligible = [
      for (final peer in peers)
        if (unmetRequirements(requirements, peer).isEmpty) peer,
    ]..sort((a, b) => capabilityScore(b).compareTo(capabilityScore(a)));

    if (eligible.isNotEmpty) {
      final best = eligible.first;
      return RouteDecision.peer(
        best.deviceId,
        'local cannot satisfy (${localUnmet.join('; ')}); '
        'overflow to ${best.deviceId} (score ${capabilityScore(best)})',
      );
    }

    // Nobody can run it: report what the LOCAL device lacked (the
    // actionable list) and say plainly that peers could not either.
    return RouteDecision.blocked(
      localUnmet,
      'no paired device satisfies the step requirements either',
    );
  }
}
