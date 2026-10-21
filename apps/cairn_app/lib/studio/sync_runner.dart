import 'dart:io';

import 'package:cairn_sync/cairn_sync.dart';

import 'device_identity.dart';
import 'project_store.dart';
import 'skill_store.dart';
import 'sync_service.dart';

/// The outcome of syncing with one paired device, worded so the UI
/// can show it verbatim (header sync button, auto-sync notifications,
/// the Devices section).
class PeerSyncOutcome {
  const PeerSyncOutcome({
    required this.peerName,
    required this.message,
    this.changed = false,
    this.ok = true,
  });

  final String peerName;
  final String message;

  /// True when the sync actually applied something (records, conflict
  /// copies, deletions) — auto-sync only speaks up then.
  final bool changed;
  final bool ok;
}

/// Shared "sync with a paired device" flow used by the Devices UI, the
/// header sync button and the periodic auto-sync, so all three behave
/// identically: build records → mutually-authenticated session →
/// apply the deterministic merge → remember the working host.
class SyncRunner {
  SyncRunner({
    required this.projects,
    required this.skills,
    required this.baseDir,
    required this.identity,
  });

  final ProjectStore projects;
  final SkillStore skills;
  final Directory baseDir;
  final DeviceKeyPair identity;

  SyncCoordinator _coordinator() => SyncCoordinator(
    projects: projects,
    skills: skills,
    baseDir: baseDir,
    deviceId: identity.deviceId,
  );

  Future<SyncApplyReport> syncPeer(PairedDevice peer, String host) async {
    final coordinator = _coordinator();
    final records = await coordinator.buildRecords();
    final result = await syncWithPeer(
      host: host,
      port: 47800,
      local: identity,
      peer: peer,
      localRecords: records,
    );
    final report = await coordinator.applyResult(result);
    // Remember the working host for next time (auto-sync uses it).
    await PairedDevicesStore(baseDir).add(
      PairedDevice(
        identity: peer.identity,
        pairedAtIso: peer.pairedAtIso,
        endpoints: [host],
      ),
    );
    return report;
  }

  static String _peerName(PairedDevice peer) =>
      peer.identity.displayName.isEmpty
      ? peer.identity.deviceId
      : peer.identity.displayName;

  static String _reportText(SyncApplyReport r) =>
      'پروژه: ${r.projectsApplied}، مهارت: ${r.skillsApplied}، '
      'تعارض تازه: ${r.conflictsCreated}، حذف‌شده: ${r.deleted}';

  /// Syncs with every paired device that has a saved address; peers
  /// without one are skipped (the Devices UI is where addresses are
  /// entered). Never throws — failures come back as outcomes.
  Future<List<PeerSyncOutcome>> syncAll() async {
    final paired = await PairedDevicesStore(baseDir).list();
    final outcomes = <PeerSyncOutcome>[];
    for (final peer in paired) {
      if (peer.endpoints.isEmpty) continue;
      final name = _peerName(peer);
      try {
        final report = await syncPeer(peer, peer.endpoints.first);
        final changed =
            report.projectsApplied +
                report.skillsApplied +
                report.conflictsCreated +
                report.deleted >
            0;
        outcomes.add(
          PeerSyncOutcome(
            peerName: name,
            message: _reportText(report),
            changed: changed,
          ),
        );
      } catch (e) {
        outcomes.add(
          PeerSyncOutcome(peerName: name, message: 'ناموفق: $e', ok: false),
        );
      }
    }
    return outcomes;
  }
}
