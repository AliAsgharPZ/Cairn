import 'package:cairn_core/cairn_core.dart';
import 'package:test/test.dart';

VersionVector vv(Map<String, int> m) => VersionVector(m);
Hlc hlc(int p, int l, String d) => Hlc(physicalMs: p, logical: l, deviceId: d);

SyncRecord record(
  String id, {
  String kind = 'project',
  Map<String, Object?> payload = const {'name': 'x'},
  Map<String, int> version = const {},
  Hlc? at,
  bool tombstone = false,
}) =>
    SyncRecord(
      entityId: id,
      kind: kind,
      payload: payload,
      version: VersionVector(Map.of(version)),
      updatedAt: at ?? hlc(1000, 0, 'phone'),
      tombstone: tombstone,
    );

void main() {
  group('VersionVector', () {
    test('increment, merge and comparison algebra', () {
      final a = vv({'phone': 1});
      final b = vv({'phone': 1, 'pc': 2});
      expect(a.compare(b), VectorOrder.less);
      expect(b.compare(a), VectorOrder.greater);
      expect(a.compare(vv({'phone': 1})), VectorOrder.equal);

      final c = vv({'phone': 2});
      final d = vv({'pc': 1});
      expect(c.compare(d), VectorOrder.concurrent);

      final merged = c.merge(d);
      expect(merged['phone'], 2);
      expect(merged['pc'], 1);
      expect(merged.dominates(c), isTrue);
      expect(merged.dominates(d), isTrue);
    });

    test('JSON round-trip', () {
      final back = VersionVector.fromJson(vv({'a': 3, 'b': 1}).toJson());
      expect(back['a'], 3);
      expect(back['b'], 1);
      expect(back['missing'], 0);
    });
  });

  group('Hlc', () {
    test('tick never goes backwards', () {
      final t0 = Hlc.now('phone', 1000);
      final t1 = Hlc.tick(t0, 900); // wall clock went backwards
      expect(t1.physicalMs, 1000);
      expect(t1.logical, 1);
      final t2 = Hlc.tick(t1, 2000);
      expect(t2.physicalMs, 2000);
      expect(t2.logical, 0);
    });

    test('receive is strictly after both clocks', () {
      final local = hlc(1000, 5, 'phone');
      final remote = hlc(1000, 9, 'pc');
      final merged = Hlc.receive(local, remote, 1000);
      expect(merged > local, isTrue);
      expect(merged.logical, 10);
      expect(merged.deviceId, 'phone');
    });
  });

  group('mergeSyncRecords', () {
    test('a dominating remote version wins; a dominating local one too',
        () {
      final older = record('p1', payload: {'name': 'old'}, version: {'phone': 1});
      final newer = record('p1',
          payload: {'name': 'new'}, version: {'phone': 2}, at: hlc(2000, 0, 'phone'));
      var result = mergeSyncRecords(local: [older], remote: [newer]);
      expect(result.merged.single.payload['name'], 'new');
      result = mergeSyncRecords(local: [newer], remote: [older]);
      expect(result.merged.single.payload['name'], 'new');
      expect(result.conflictCopies, isEmpty);
    });

    test('concurrent project edits resolve deterministically by HLC', () {
      final localRec =
          record('p1', payload: {'name': 'phone edit'}, version: {'phone': 1});
      final remoteRec = record('p1',
          payload: {'name': 'pc edit'},
          version: {'pc': 1},
          at: hlc(1500, 0, 'pc'));
      final result = mergeSyncRecords(local: [localRec], remote: [remoteRec]);
      // The pc edit has the greater HLC (1500 > 1000): it is canonical on
      // BOTH devices, and the phone edit becomes the conflict copy with
      // a deterministic id.
      expect(result.merged.single.payload['name'], 'pc edit');
      expect(result.conflictCopies, hasLength(1));
      expect(result.conflictCopies.single.payload['name'], 'phone edit');
      expect(result.conflictCopies.single.entityId, 'conflict:p1:phone');
      // The merged record carries the joined version vector.
      expect(result.merged.single.version['phone'], 1);
      expect(result.merged.single.version['pc'], 1);
      // Symmetry: swapping local/remote yields the same canonical state.
      final swapped = mergeSyncRecords(local: [remoteRec], remote: [localRec]);
      expect(swapped.merged.single.payload['name'], 'pc edit');
      expect(swapped.conflictCopies.single.entityId, 'conflict:p1:phone');
    });

    test('journal records union by event id without duplication', () {
      final e1 = record('ev1', kind: 'journal', payload: {'kind': 'a'});
      final e2 = record('ev2', kind: 'journal', payload: {'kind': 'b'});
      final result = mergeSyncRecords(local: [e1], remote: [e1, e2]);
      expect(result.merged.map((r) => r.entityId), containsAll(['ev1', 'ev2']));
      expect(result.merged, hasLength(2));
    });

    test('settings merge per key by HLC', () {
      Map<String, Object?> entry(Object v, Hlc at) =>
          {'value': v, 'hlc': at.toJson()};
      final localRec = record('settings',
          kind: 'settings',
          payload: {
            'theme': entry('dark', hlc(3000, 0, 'phone')),
            'lang': entry('fa', hlc(1000, 0, 'phone')),
          },
          version: {'phone': 1});
      final remoteRec = record('settings',
          kind: 'settings',
          payload: {
            'theme': entry('light', hlc(2000, 0, 'pc')),
            'lang': entry('en', hlc(4000, 0, 'pc')),
          },
          version: {'pc': 1});
      final result =
          mergeSyncRecords(local: [localRec], remote: [remoteRec]);
      final settings = result.merged.single.payload;
      expect((settings['theme'] as Map)['value'], 'dark'); // phone is newer
      expect((settings['lang'] as Map)['value'], 'en'); // pc is newer
    });

    test('a dominating tombstone deletes; a concurrent one does not', () {
      final edit = record('p1', version: {'phone': 1});
      final tombNew = record('p1',
          version: {'phone': 2}, tombstone: true, at: hlc(2000, 0, 'phone'));
      var result = mergeSyncRecords(local: [edit], remote: [tombNew]);
      expect(result.merged, isEmpty);
      expect(result.deletedIds, ['p1']);

      final tombConcurrent =
          record('p1', version: {'pc': 1}, tombstone: true, at: hlc(2000, 0, 'pc'));
      result = mergeSyncRecords(local: [edit], remote: [tombConcurrent]);
      expect(result.merged, hasLength(1));
      expect(result.deletedIds, isEmpty);
    });

    test('records present on only one side are adopted', () {
      final only = record('p9', version: {'pc': 3});
      final result = mergeSyncRecords(local: const [], remote: [only]);
      expect(result.merged.single.entityId, 'p9');
    });

    test('record JSON round-trip', () {
      final r = record('p1', version: {'phone': 2}, tombstone: true);
      final back = SyncRecord.fromJson(r.toJson());
      expect(back.entityId, 'p1');
      expect(back.version['phone'], 2);
      expect(back.tombstone, isTrue);
      expect(back.updatedAt.deviceId, 'phone');
    });
  });
}
