import 'dart:convert';
import 'dart:io';

import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_sync/cairn_sync.dart';

import 'project_store.dart';
import 'skill_store.dart';

/// App-side sync bookkeeping (M7): turns the studio's projects and
/// skills into [SyncRecord]s (and back), remembering each entity's
/// version vector / HLC between sessions in `sync_state.json`.
///
/// Rules:
/// - an unchanged entity reuses its stored version (no phantom edits);
/// - a changed payload bumps this device's counter and HLC;
/// - an entity that vanished locally becomes a tombstone record so the
///   deletion can propagate (and be refused if the peer edited it
///   concurrently — see cairn_core's merger);
/// - applying a merge writes records back into the stores; conflict
///   copies become new entities named "… (تعارض)"; deletions move to
///   a trash list the UI keeps for 30 days.
class SyncCoordinator {
  SyncCoordinator({
    required this.projects,
    required this.skills,
    required this.baseDir,
    required this.deviceId,
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final ProjectStore projects;
  final SkillStore skills;
  final Directory baseDir;
  final String deviceId;
  final int Function() _nowMs;

  File get _stateFile => File('${baseDir.path}/sync_state.json');

  // -- state ------------------------------------------------------------

  Future<Map<String, Object?>> _loadState() async {
    if (!await _stateFile.exists()) {
      return {'records': <String, Object?>{}, 'trash': <Object?>[]};
    }
    return (jsonDecode(await _stateFile.readAsString()) as Map)
        .cast<String, Object?>();
  }

  Future<void> _saveState(Map<String, Object?> state) async {
    await baseDir.create(recursive: true);
    final tmp = File('${_stateFile.path}.tmp');
    await tmp.writeAsString(jsonEncode(state), flush: true);
    await tmp.rename(_stateFile.path);
  }

  Map<String, SyncRecord> _storedRecords(Map<String, Object?> state) {
    final raw = (state['records'] as Map?) ?? const {};
    return raw.map((k, v) => MapEntry(
        '$k', SyncRecord.fromJson((v as Map).cast<String, Object?>())));
  }

  List<Map<String, Object?>> _trashOf(Map<String, Object?> state) =>
      ((state['trash'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, Object?>())
          .toList();

  /// The current trash entries (deletions propagated by sync).
  Future<List<Map<String, Object?>>> trash() async =>
      _trashOf(await _loadState());

  Hlc _bumpHlc(Hlc? previous) {
    final now = _nowMs();
    if (previous == null || now > previous.physicalMs) {
      return Hlc(physicalMs: now, logical: 0, deviceId: deviceId);
    }
    return Hlc(
        physicalMs: previous.physicalMs,
        logical: previous.logical + 1,
        deviceId: deviceId);
  }

  // -- record production --------------------------------------------------

  /// Builds the current record set from the stores, updating and
  /// persisting the bookkeeping state.
  Future<List<SyncRecord>> buildRecords() async {
    final state = await _loadState();
    final stored = _storedRecords(state);
    final out = <String, SyncRecord>{};

    final current = <String, (String, Map<String, Object?>)>{
      for (final p in await projects.list()) p.id: ('project', p.toJson()),
      for (final s in await skills.list()) s.id: ('skill', s.toJson()),
    };

    current.forEach((id, entity) {
      final (kind, payload) = entity;
      final previous = stored[id];
      if (previous != null &&
          !previous.tombstone &&
          jsonEncode(previous.payload) == jsonEncode(payload)) {
        out[id] = previous; // unchanged
        return;
      }
      final version = (previous?.version.copy() ?? VersionVector())
        ..increment(deviceId);
      out[id] = SyncRecord(
        entityId: id,
        kind: kind,
        payload: payload,
        version: version,
        updatedAt: _bumpHlc(previous?.updatedAt),
      );
    });

    // Vanished entities become tombstones.
    stored.forEach((id, record) {
      if (!current.containsKey(id)) {
        if (record.tombstone) {
          out[id] = record;
        } else {
          final version = record.version.copy()..increment(deviceId);
          out[id] = SyncRecord(
            entityId: id,
            kind: record.kind,
            payload: record.payload,
            version: version,
            updatedAt: _bumpHlc(record.updatedAt),
            tombstone: true,
          );
        }
      }
    });

    state['records'] = {
      for (final e in out.entries) e.key: e.value.toJson(),
    };
    await _saveState(state);
    return out.values.toList();
  }

  // -- applying merge results ----------------------------------------------

  /// Writes a completed session's outcome into the stores and the
  /// bookkeeping state. Returns a small report for the UI.
  Future<SyncApplyReport> applyResult(SyncSessionResult result) async {
    var projectsApplied = 0;
    var skillsApplied = 0;
    var conflictsCreated = 0;

    Future<void> writeEntity(SyncRecord record, {bool conflict = false}) async {
      var payload = record.payload;
      if (conflict) {
        payload = Map<String, Object?>.of(payload);
        payload['id'] = record.entityId;
        payload['name'] = '${payload['name'] ?? ''} (تعارض)';
      }
      switch (record.kind) {
        case 'project':
          await projects.save(AgentProject.fromJson(payload));
          if (conflict) {
            conflictsCreated++;
          } else {
            projectsApplied++;
          }
        case 'skill':
          await skills.save(Skill.fromJson(payload));
          if (conflict) {
            conflictsCreated++;
          } else {
            skillsApplied++;
          }
      }
    }

    for (final record in result.merged) {
      await writeEntity(record);
    }
    for (final copy in result.conflictCopies) {
      await writeEntity(copy, conflict: true);
    }

    final state = await _loadState();
    final trash = _trashOf(state);
    for (final id in result.deletedIds) {
      final kind = await projects.load(id) != null
          ? 'project'
          : (await skills.load(id) != null ? 'skill' : 'project');
      final name = kind == 'project'
          ? (await projects.load(id))?.name
          : (await skills.load(id))?.name;
      if (kind == 'project') {
        await projects.delete(id);
      } else {
        await skills.delete(id);
      }
      trash.add({
        'entityId': id,
        'kind': kind,
        'name': name ?? id,
        'deletedAtIso': DateTime.fromMillisecondsSinceEpoch(_nowMs())
            .toUtc()
            .toIso8601String(),
      });
    }

    state['records'] = {
      for (final r in result.merged) r.entityId: r.toJson(),
      for (final c in result.conflictCopies) c.entityId: c.toJson(),
    };
    state['trash'] = trash;
    await _saveState(state);

    return SyncApplyReport(
      projectsApplied: projectsApplied,
      skillsApplied: skillsApplied,
      conflictsCreated: conflictsCreated,
      deleted: result.deletedIds.length,
    );
  }
}

/// What one apply did — shown to the user after a sync.
class SyncApplyReport {
  const SyncApplyReport({
    required this.projectsApplied,
    required this.skillsApplied,
    required this.conflictsCreated,
    required this.deleted,
  });

  final int projectsApplied;
  final int skillsApplied;
  final int conflictsCreated;
  final int deleted;
}
