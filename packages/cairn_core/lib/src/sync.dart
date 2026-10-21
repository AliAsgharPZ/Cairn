// Two-way sync core (M7): version vectors, hybrid logical clocks and the
// per-kind merge rules from the approved design (docs/decisions.md):
//
// - projects & skills: a dominating version wins; **concurrent** edits
//   resolve deterministically — the record with the greater HLC stays
//   canonical and the other becomes a conflict copy with a
//   deterministic id, so both devices converge to identical state
//   (a real 3-way merge additionally needs the common base; without one
//   the conflict copy is the decided fallback, never a silent overwrite).
// - journal events: append-only union (deduplicated by event id).
// - settings: per-key last-writer-wins by hybrid logical clock.
// - deletions: tombstones. A dominating tombstone deletes; a tombstone
//   concurrent with an edit loses (the edit resurrects the entity) —
//   deletion must never silently eat a concurrent edit. Deleted entities
//   are reported so the app can keep them in the 30-day trash.

/// Vector-clock comparison outcome.
enum VectorOrder { less, greater, equal, concurrent }

class VersionVector {
  VersionVector([Map<String, int>? counters])
      : counters = counters ?? <String, int>{};

  final Map<String, int> counters;

  int operator [](String deviceId) => counters[deviceId] ?? 0;

  void increment(String deviceId) =>
      counters[deviceId] = this[deviceId] + 1;

  /// Element-wise maximum — the merged vector dominates both inputs.
  VersionVector merge(VersionVector other) {
    final out = Map<String, int>.of(counters);
    other.counters.forEach((k, v) {
      if (v > (out[k] ?? 0)) out[k] = v;
    });
    return VersionVector(out);
  }

  VectorOrder compare(VersionVector other) {
    var less = false, greater = false;
    final keys = {...counters.keys, ...other.counters.keys};
    for (final k in keys) {
      if (this[k] < other[k]) less = true;
      if (this[k] > other[k]) greater = true;
    }
    if (less && greater) return VectorOrder.concurrent;
    if (less) return VectorOrder.less;
    if (greater) return VectorOrder.greater;
    return VectorOrder.equal;
  }

  bool dominates(VersionVector other) {
    final o = compare(other);
    return o == VectorOrder.greater || o == VectorOrder.equal;
  }

  VersionVector copy() => VersionVector(Map.of(counters));

  Map<String, Object?> toJson() => {'counters': counters};

  factory VersionVector.fromJson(Map<String, Object?> json) =>
      VersionVector((json['counters'] as Map?)?.map(
          (k, v) => MapEntry('$k', (v as num).toInt())));

  @override
  String toString() => 'VV$counters';
}

/// Hybrid logical clock timestamp: physical milliseconds plus a logical
/// counter, tie-broken by device id, so timestamps from different devices
/// are totally ordered and a device's clock never goes backwards.
class Hlc implements Comparable<Hlc> {
  const Hlc(
      {required this.physicalMs, required this.logical, required this.deviceId});

  final int physicalMs;
  final int logical;
  final String deviceId;

  /// A fresh timestamp for [deviceId] at wall-clock [physicalMs].
  factory Hlc.now(String deviceId, int physicalMs) =>
      Hlc(physicalMs: physicalMs, logical: 0, deviceId: deviceId);

  /// The next local timestamp strictly after [last].
  static Hlc tick(Hlc last, int physicalMs) {
    if (physicalMs > last.physicalMs) {
      return Hlc(
          physicalMs: physicalMs, logical: 0, deviceId: last.deviceId);
    }
    return Hlc(
        physicalMs: last.physicalMs,
        logical: last.logical + 1,
        deviceId: last.deviceId);
  }

  /// Merge a received remote timestamp: the result is strictly after
  /// both [last] and [remote] on this device.
  static Hlc receive(Hlc last, Hlc remote, int physicalMs) {
    final maxPhysical = [last.physicalMs, remote.physicalMs, physicalMs]
        .reduce((a, b) => a > b ? a : b);
    final int logical;
    if (maxPhysical == last.physicalMs && maxPhysical == remote.physicalMs) {
      logical = (last.logical > remote.logical ? last.logical : remote.logical) + 1;
    } else if (maxPhysical == last.physicalMs) {
      logical = last.logical + 1;
    } else if (maxPhysical == remote.physicalMs) {
      logical = remote.logical + 1;
    } else {
      logical = 0;
    }
    return Hlc(
        physicalMs: maxPhysical, logical: logical, deviceId: last.deviceId);
  }

  @override
  int compareTo(Hlc other) {
    if (physicalMs != other.physicalMs) {
      return physicalMs.compareTo(other.physicalMs);
    }
    if (logical != other.logical) return logical.compareTo(other.logical);
    return deviceId.compareTo(other.deviceId);
  }

  bool operator >(Hlc other) => compareTo(other) > 0;
  bool operator <(Hlc other) => compareTo(other) < 0;
  bool operator >=(Hlc other) => compareTo(other) >= 0;
  bool operator <=(Hlc other) => compareTo(other) <= 0;

  Map<String, Object?> toJson() =>
      {'p': physicalMs, 'l': logical, 'd': deviceId};

  factory Hlc.fromJson(Map<String, Object?> json) => Hlc(
        physicalMs: (json['p'] as num).toInt(),
        logical: (json['l'] as num).toInt(),
        deviceId: json['d'] as String,
      );

  @override
  String toString() => 'Hlc($physicalMs.$logical@$deviceId)';
}

/// One syncable entity snapshot exchanged between paired devices.
class SyncRecord {
  SyncRecord({
    required this.entityId,
    required this.kind,
    required this.payload,
    required this.version,
    required this.updatedAt,
    this.tombstone = false,
  });

  /// Project id, skill id, 'settings', or a journal event id.
  final String entityId;

  /// 'project' | 'skill' | 'settings' | 'journal'
  final String kind;

  /// The entity's JSON. For 'settings': key → {value, hlc} entries.
  final Map<String, Object?> payload;

  final VersionVector version;
  final Hlc updatedAt;
  final bool tombstone;

  Map<String, Object?> toJson() => {
        'entityId': entityId,
        'kind': kind,
        'payload': payload,
        'version': version.toJson(),
        'updatedAt': updatedAt.toJson(),
        'tombstone': tombstone,
      };

  factory SyncRecord.fromJson(Map<String, Object?> json) => SyncRecord(
        entityId: json['entityId'] as String,
        kind: json['kind'] as String,
        payload: (json['payload'] as Map).cast<String, Object?>(),
        version: VersionVector.fromJson(
            (json['version'] as Map).cast<String, Object?>()),
        updatedAt:
            Hlc.fromJson((json['updatedAt'] as Map).cast<String, Object?>()),
        tombstone: json['tombstone'] as bool? ?? false,
      );
}

/// The outcome of merging two devices' record sets.
class SyncMergeResult {
  SyncMergeResult(
      {required this.merged,
      required this.conflictCopies,
      required this.deletedIds});

  /// The canonical records after merging (tombstones excluded).
  final List<SyncRecord> merged;

  /// Remote versions that lost a concurrent edit — kept as new entities
  /// with fresh ids so nothing is silently overwritten.
  final List<SyncRecord> conflictCopies;

  /// Entity ids deleted by dominating tombstones (for the 30-day trash).
  final List<String> deletedIds;
}

/// Merges [local] and [remote] record sets per the rules at the top of
/// this file. Pure and deterministic: the same inputs always produce the
/// same outputs on both devices.
SyncMergeResult mergeSyncRecords({
  required List<SyncRecord> local,
  required List<SyncRecord> remote,
}) {
  final merged = <String, SyncRecord>{};
  final conflictCopies = <SyncRecord>[];
  final deletedIds = <String>[];

  final localById = {for (final r in local) r.entityId: r};
  final remoteById = {for (final r in remote) r.entityId: r};
  final allIds = {...localById.keys, ...remoteById.keys};

  for (final id in allIds) {
    final l = localById[id];
    final r = remoteById[id];

    // Journal: append-only union — presence on either side is enough.
    if ((l?.kind ?? r?.kind) == 'journal') {
      final rec = l ?? r!;
      if (!rec.tombstone) merged[id] = rec;
      continue;
    }

    // Only on one side.
    if (l == null) {
      if (!r!.tombstone) merged[id] = r;
      continue;
    }
    if (r == null) {
      if (!l.tombstone) merged[id] = l;
      continue;
    }

    // Settings: per-key LWW by HLC, regardless of version vectors.
    if (l.kind == 'settings') {
      merged[id] = _mergeSettings(l, r);
      continue;
    }

    // Tombstone handling.
    if (l.tombstone || r.tombstone) {
      final tomb = l.tombstone ? l : r;
      final other = l.tombstone ? r : l;
      if (tomb.version.dominates(other.version)) {
        deletedIds.add(id);
      } else {
        // Concurrent (or older) tombstone vs an edit: the edit survives.
        merged[id] = other;
      }
      continue;
    }

    // Regular entities: version-vector order decides.
    switch (l.version.compare(r.version)) {
      case VectorOrder.equal:
        merged[id] = l.updatedAt >= r.updatedAt ? l : r;
      case VectorOrder.greater:
        merged[id] = l;
      case VectorOrder.less:
        merged[id] = r;
      case VectorOrder.concurrent:
        // Deterministic on BOTH devices: the record with the greater
        // HLC (device-id tiebreak inside Hlc) stays canonical; the other
        // becomes a conflict copy with a deterministic id derived from
        // the entity id + losing device, so both sides mint the SAME
        // copy and repeated syncs converge instead of duplicating.
        final localWins = l.updatedAt >= r.updatedAt;
        final winner = localWins ? l : r;
        final loser = localWins ? r : l;
        final joined = l.version.merge(r.version);
        merged[id] = SyncRecord(
          entityId: winner.entityId,
          kind: winner.kind,
          payload: winner.payload,
          version: joined,
          updatedAt: winner.updatedAt,
        );
        conflictCopies.add(SyncRecord(
          entityId: 'conflict:${loser.entityId}:${loser.updatedAt.deviceId}',
          kind: loser.kind,
          payload: loser.payload,
          version: joined,
          updatedAt: loser.updatedAt,
        ));
    }
  }

  return SyncMergeResult(
    merged: merged.values.toList(),
    conflictCopies: conflictCopies,
    deletedIds: deletedIds,
  );
}

SyncRecord _mergeSettings(SyncRecord a, SyncRecord b) {
  final out = <String, Object?>{};
  final keys = {...a.payload.keys, ...b.payload.keys};
  for (final key in keys) {
    final ea = a.payload[key] as Map?;
    final eb = b.payload[key] as Map?;
    if (ea == null) {
      out[key] = eb;
      continue;
    }
    if (eb == null) {
      out[key] = ea;
      continue;
    }
    final ha = Hlc.fromJson((ea['hlc'] as Map).cast<String, Object?>());
    final hb = Hlc.fromJson((eb['hlc'] as Map).cast<String, Object?>());
    out[key] = ha >= hb ? ea : eb;
  }
  return SyncRecord(
    entityId: a.entityId,
    kind: 'settings',
    payload: out,
    version: a.version.merge(b.version),
    updatedAt: a.updatedAt >= b.updatedAt ? a.updatedAt : b.updatedAt,
  );
}
