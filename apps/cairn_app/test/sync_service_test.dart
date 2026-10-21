import 'dart:io';

import 'package:cairn_app/studio/project_store.dart';
import 'package:cairn_app/studio/skill_store.dart';
import 'package:cairn_app/studio/sync_service.dart';
import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_sync/cairn_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SyncCoordinator', () {
    late Directory tmp;
    late ProjectStore projects;
    late SkillStore skills;
    var clock = 1000;
    late SyncCoordinator coordinator;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('cairn_sync_coord_test');
      projects = ProjectStore(tmp);
      skills = SkillStore(tmp);
      clock = 1000;
      coordinator = SyncCoordinator(
        projects: projects,
        skills: skills,
        baseDir: tmp,
        deviceId: 'phone',
        nowMs: () => clock,
      );
    });

    tearDown(() async {
      await tmp.delete(recursive: true);
    });

    test('buildRecords versions new entities and stays stable when '
        'nothing changed', () async {
      await projects.createProject('Alpha');
      var records = await coordinator.buildRecords();
      expect(records, hasLength(1));
      expect(records.single.kind, 'project');
      expect(records.single.version['phone'], 1);

      records = await coordinator.buildRecords();
      expect(records.single.version['phone'], 1); // no phantom bump
    });

    test('editing an entity bumps its version; deleting tombstones it',
        () async {
      final project = await projects.createProject('Alpha');
      await coordinator.buildRecords();

      final editedJson = Map<String, Object?>.of(project.toJson())
        ..['name'] = 'Alpha 2';
      await projects.save(AgentProject.fromJson(editedJson));
      clock = 2000;
      var records = await coordinator.buildRecords();
      expect(records.single.version['phone'], 2);
      expect(records.single.payload['name'], 'Alpha 2');

      await projects.delete(project.id);
      clock = 3000;
      records = await coordinator.buildRecords();
      expect(records.single.tombstone, isTrue);
      expect(records.single.version['phone'], 3);
    });

    test('applyResult writes merged records, conflict copies and '
        'deletions into the stores', () async {
      final mine = await projects.createProject('Mine');
      await coordinator.buildRecords();

      SyncRecord remote(String id, String name, int at) => SyncRecord(
            entityId: id,
            kind: 'project',
            payload: AgentProject(name: name, id: id).toJson(),
            version: VersionVector({'pc': 1}),
            updatedAt: Hlc(physicalMs: at, logical: 0, deviceId: 'pc'),
          );

      final result = SyncSessionResult(
        merged: [remote('remote-1', 'From PC', 5000)],
        conflictCopies: [
          SyncRecord(
            entityId: 'conflict:${mine.id}:pc',
            kind: 'project',
            payload: mine.toJson(),
            version: VersionVector({'phone': 1, 'pc': 1}),
            updatedAt: Hlc(physicalMs: 4000, logical: 0, deviceId: 'pc'),
          ),
        ],
        deletedIds: [mine.id],
        peerRecordCount: 2,
      );

      final report = await coordinator.applyResult(result);
      expect(report.projectsApplied, 1);
      expect(report.conflictsCreated, 1);
      expect(report.deleted, 1);

      final names = (await projects.list()).map((p) => p.name).toList();
      expect(names, contains('From PC'));
      expect(names, contains('Mine (تعارض)'));
      expect(names, isNot(contains('Mine')));
      final trash = await coordinator.trash();
      expect(trash.single['entityId'], mine.id);
    });
  });
}
