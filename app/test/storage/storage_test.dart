import 'dart:convert';
import 'dart:io';

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/crypto/vault_codec.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/storage/attachment_store.dart';
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

  group('sealed at rest, bound to names', () {
    final key = SecretKey(List.filled(32, 3));
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('lt-bound'));
    tearDown(() => dir.delete(recursive: true));

    test('the index of names is sealed too, and still lists them', () async {
      final store = FileByteStore(dir, indexKey: key);
      await store.write('emergency_card_p-1234abcd', Uint8List.fromList([1]));
      await store.write('att_scan42_0', Uint8List.fromList([2]));
      final raw = File('${dir.path}/index.json').readAsBytesSync();
      expect(latin1.decode(raw).contains('emergency'), isFalse);
      expect(latin1.decode(raw).contains('scan42'), isFalse);
      expect((await FileByteStore(dir, indexKey: key).names()).toSet(), {'emergency_card_p-1234abcd', 'att_scan42_0'});
    });

    test('an index written in the clear by an older version is read, then sealed on the next save', () async {
      final plain = FileByteStore(dir);
      await plain.write('records', Uint8List.fromList([1]));
      expect(File('${dir.path}/index.json').readAsStringSync(), contains('records'));
      final sealed = FileByteStore(dir, indexKey: key);
      expect(await sealed.names(), ['records']);
      await sealed.write('grants', Uint8List.fromList([2]));
      expect(latin1.decode(File('${dir.path}/index.json').readAsBytesSync()).contains('records'), isFalse);
      expect((await sealed.names()).toSet(), {'records', 'grants'});
    });

    test('a sealed blob copied under another name does not open there', () async {
      final bytes = InMemoryByteStore();
      final store = SealedStore(bytes, key);
      await store.write('grants', {'g': 1});
      await bytes.write('records', (await bytes.read('grants'))!);
      expect(() => store.read('records'), throwsA(isA<VaultAuthenticationFailed>()));
      expect(await store.read('grants'), {'g': 1});
    });

    test('a blob sealed before names were bound is read, then rewritten bound', () async {
      final bytes = InMemoryByteStore();
      await bytes.write('records', await VaultCodec.seal(['old'], key));
      expect((await bytes.read('records'))![2], 1);
      expect(await SealedStore(bytes, key).read('records'), ['old']);
      expect((await bytes.read('records'))![2], VaultCodec.frameVersion);
    });

    test('original pages cannot be swapped between records', () async {
      final bytes = InMemoryByteStore();
      final pages = AttachmentStore(bytes, key);
      await pages.save('a', [Uint8List.fromList([1, 1])]);
      await pages.save('b', [Uint8List.fromList([2, 2])]);
      await bytes.write('att_a_0', (await bytes.read('att_b_0'))!);
      expect(() => pages.load('a'), throwsA(anything));
      expect(await pages.load('b'), [[2, 2]]);
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
