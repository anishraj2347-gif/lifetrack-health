import 'dart:io';

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/storage/file_byte_store.dart';
import 'package:lifetrack/src/storage/record_repository.dart';
import 'package:lifetrack/src/storage/sealed_store.dart';

void main() {
  group('FileByteStore', () {
    late Directory dir;
    late FileByteStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('lt-store');
      store = FileByteStore(dir);
    });
    tearDown(() => dir.delete(recursive: true));

    test('write, read, overwrite, delete', () async {
      await store.write('records', Uint8List.fromList([1, 2]));
      await store.write('records', Uint8List.fromList([3]));
      expect(await store.read('records'), [3]);
      expect(await store.names(), ['records']);
      await store.delete('records');
      expect(await store.read('records'), isNull);
      expect(await store.names(), isEmpty);
    });

    test('many saves at the same moment never corrupt the index (bug seen in the phase 2 demo)', () async {
      await Future.wait([for (var i = 0; i < 40; i++) store.write('blob-$i', Uint8List.fromList([i]))]);
      final names = await store.names();
      expect(names.toSet(), {for (var i = 0; i < 40; i++) 'blob-$i'});
      for (var i = 0; i < 40; i++) {
        expect(await store.read('blob-$i'), [i]);
      }
    });

    test('a damaged index is repaired instead of blocking every save', () async {
      await store.write('a', Uint8List.fromList([1]));
      File('${dir.path}/index.json').writeAsStringSync('["a"]g]');
      await store.write('b', Uint8List.fromList([2]));
      expect(await store.read('a'), [1]);
      expect(await store.read('b'), [2]);
      expect(await store.names(), contains('b'));
    });

    test('leaves no temp files behind and never uses the blob name on disk', () async {
      await store.write('../../escape', Uint8List.fromList([9]));
      final files = dir.listSync().map((f) => f.path.split('/').last).toList();
      expect(files.where((f) => f.endsWith('.tmp')), isEmpty);
      expect(files.any((f) => f.contains('escape')), isFalse);
      expect(File('${dir.parent.path}/escape').existsSync(), isFalse);
      expect(await store.read('../../escape'), [9]);
    });
  });

  group('RecordRepository', () {
    final key = SecretKey(List.filled(32, 3));
    final record = HealthRecord(
      id: 'r1',
      patientId: 'p1',
      kind: RecordKind.report,
      title: 'Lipid panel',
      date: DateTime(2026, 3, 9),
      source: RecordSource.doctorIssued,
      results: const [LabResult(analyte: 'ldl', value: 132, unit: 'mg/dL')],
    );

    test('records survive a reopen, sealed at rest', () async {
      final bytes = InMemoryByteStore();
      final repo = await RecordRepository.open(SealedStore(bytes, key));
      await repo.add(record);
      final raw = await bytes.read(RecordRepository.recordsBlob);
      expect(String.fromCharCodes(raw!).contains('Lipid'), isFalse);
      final reopened = await RecordRepository.open(SealedStore(bytes, key));
      expect(reopened.recordsOf('p1').single.results.single.value, 132);
    });

    test('recordsOf is per patient', () async {
      final repo = await RecordRepository.open(SealedStore(InMemoryByteStore(), key));
      await repo.add(record);
      expect(repo.recordsOf('p2'), isEmpty);
    });
  });
}
