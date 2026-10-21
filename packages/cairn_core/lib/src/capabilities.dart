// Compute overflow (M8, owner-corrected 2026-10-21): multi-directional
// load balancing between symmetric peer devices. Any device may serve
// any other; steps are SPLIT across the capable devices instead of
// piling onto one. The governing rules:
//  1. Hard requirements gate eligibility — a device that cannot
//     satisfy a step never gets it (no fixed RAM threshold; if nobody
//     is eligible the step is blocked with the unmet requirements
//     listed, never silently downgraded).
//  2. Link priority: this device itself, then the local network,
//     then the internet (e.g. a Tailscale route) LAST — a nearer tier
//     wins unless it cannot satisfy the step at all.
//  3. Inside the best eligible tier, steps spread evenly: the pick is
//     the device with the highest capability score per unit of load
//     already assigned in this run, so consecutive steps alternate
//     instead of stacking on the strongest machine.

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

/// A relative capability score for an ELIGIBLE device — the
/// balancer divides it by assigned load to spread steps evenly.
int capabilityScore(DeviceCapabilities caps) {
  var score = caps.cpuCores * 100 + (caps.ramMb ~/ 512) * 10;
  if (caps.hasGpu) score += 500;
  if (caps.onBattery) score -= 200;
  return score;
}

/// How a device is reached, in the owner's priority order: the device
/// itself, the local network, then the internet — always last.
enum LinkKind { local, lan, internet }

/// Classifies a peer endpoint host into a [LinkKind]: loopback is
/// local; private LAN ranges are lan; everything else — including
/// Tailscale's 100.64.0.0/10 range and public addresses — counts as
/// internet (it leaves the local network, so it is the last resort).
LinkKind classifyHost(String host) {
  final h = host.trim().toLowerCase();
  if (h == 'localhost' || h == '::1') return LinkKind.local;
  final parts = h.split('.');
  if (parts.length == 4) {
    final nums = parts.map(int.tryParse).toList();
    if (nums.every((n) => n != null)) {
      final a = nums[0]!, b = nums[1]!;
      if (a == 127) return LinkKind.local;
      if (a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168)) {
        return LinkKind.lan;
      }
      return LinkKind.internet;
    }
  }
  return LinkKind.internet;
}

/// One device that could take a step: its capabilities, how it is
/// reached, and how much load this run has already given it.
class DeviceCandidate {
  const DeviceCandidate({
    required this.caps,
    required this.link,
    this.load = 0,
  });

  final DeviceCapabilities caps;
  final LinkKind link;

  /// Steps already assigned to this device in the current run (or
  /// currently in flight) — the balancer spreads against this.
  final int load;
}

/// Where a step will run, and why.
class RouteDecision {
  const RouteDecision.local(this.reason, {this.link = LinkKind.local})
      : targetDeviceId = null,
        unmet = const [];
  const RouteDecision.peer(this.targetDeviceId, this.reason, {this.link})
      : unmet = const [];
  const RouteDecision.blocked(this.unmet, this.reason)
      : targetDeviceId = null,
        link = null;

  /// Null when the step stays local (or is blocked).
  final String? targetDeviceId;
  final String reason;

  /// The link tier of the chosen device (null when blocked).
  final LinkKind? link;

  /// For blocked decisions: the requirements no device could meet.
  final List<String> unmet;

  bool get isLocal => targetDeviceId == null && unmet.isEmpty;
  bool get isBlocked => unmet.isNotEmpty;
}

/// The multi-directional load balancer. Pure and deterministic.
class LoadBalancer {
  const LoadBalancer();

  RouteDecision decide({
    required StepRequirements requirements,
    required List<DeviceCandidate> candidates,
  }) {
    final eligible = <DeviceCandidate>[];
    List<String>? requesterUnmet;
    for (final c in candidates) {
      final unmet = unmetRequirements(requirements, c.caps);
      if (c.link == LinkKind.local && requesterUnmet == null) {
        requesterUnmet = unmet;
      }
      if (unmet.isEmpty) eligible.add(c);
    }
    if (eligible.isEmpty) {
      return RouteDecision.blocked(
        requesterUnmet ??
            (candidates.isEmpty
                ? const ['no candidate devices']
                : unmetRequirements(requirements, candidates.first.caps)),
        'no device satisfies the step requirements',
      );
    }

    // Priority tiers: the local network (this device + LAN peers)
    // first, the internet last — a step leaves the local network only
    // when nothing on it can satisfy the step. Inside the best tier,
    // spread evenly: highest capability per unit of assigned load.
    int tierOf(DeviceCandidate c) =>
        c.link == LinkKind.internet ? 1 : 0;
    var bestTier = 1;
    for (final c in eligible) {
      if (tierOf(c) < bestTier) bestTier = tierOf(c);
    }
    final pool = [
      for (final c in eligible)
        if (tierOf(c) == bestTier) c,
    ]..sort((a, b) {
        final ea = capabilityScore(a.caps) / (1 + a.load);
        final eb = capabilityScore(b.caps) / (1 + b.load);
        if (eb != ea) return eb.compareTo(ea);
        final byScore =
            capabilityScore(b.caps).compareTo(capabilityScore(a.caps));
        if (byScore != 0) return byScore;
        if (a.load != b.load) return a.load.compareTo(b.load);
        return a.caps.deviceId.compareTo(b.caps.deviceId);
      });
    final winner = pool.first;
    final tierName = bestTier == 0 ? 'local network' : 'internet';
    final reason = 'tier $tierName; load-balanced pick '
        '${winner.caps.deviceId} (score ${capabilityScore(winner.caps)}, '
        'load ${winner.load}) among ${pool.length} eligible in tier';
    if (winner.link == LinkKind.local) {
      return RouteDecision.local(reason, link: winner.link);
    }
    return RouteDecision.peer(winner.caps.deviceId, reason,
        link: winner.link);
  }

  /// Plans a whole batch: each decision feeds its assignment back as
  /// load for the next, so the batch spreads evenly by construction.
  List<RouteDecision> decideAll({
    required List<StepRequirements> steps,
    required List<DeviceCandidate> candidates,
  }) {
    final loads = <String, int>{
      for (final c in candidates) c.caps.deviceId: c.load,
    };
    final decisions = <RouteDecision>[];
    for (final step in steps) {
      final current = [
        for (final c in candidates)
          DeviceCandidate(
            caps: c.caps,
            link: c.link,
            load: loads[c.caps.deviceId] ?? c.load,
          ),
      ];
      final decision = decide(requirements: step, candidates: current);
      decisions.add(decision);
      final target = decision.isLocal
          ? current
              .where((c) => c.link == LinkKind.local)
              .map((c) => c.caps.deviceId)
              .firstOrNull
          : decision.targetDeviceId;
      if (target != null) loads[target] = (loads[target] ?? 0) + 1;
    }
    return decisions;
  }
}
