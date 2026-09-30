import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:lifetrack_server/api.dart';
import 'package:lifetrack_server/registry.dart';
import 'package:lifetrack_server/relay_store.dart';
import 'package:lifetrack_server/vault_store.dart';
import 'package:lifetrack_server/id_registry.dart';
import 'package:lifetrack_server/identity.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';
import 'package:shelf/shelf_io.dart' as io;

/// Local phase 2 server. Binds to 127.0.0.1 only — nothing on the Wi-Fi can
/// reach it. The phone reaches it over USB with `adb reverse tcp:8787 tcp:8787`.
///
///   dart run bin/server.dart [--port 8787] [--data data]
Future<void> main(List<String> args) async {
  final port = int.parse(_arg(args, '--port') ?? '8787');
  final dataDir = Directory(_arg(args, '--data') ?? 'data');
  await dataDir.create(recursive: true);

  final signingKey = await _registryKey(File('${dataDir.path}/registry_key.json'));
  final adminToken = await _adminToken(File('${dataDir.path}/admin_token'));
  final registry = await DoctorRegistry.open(signingKey: signingKey, file: File('${dataDir.path}/doctors.json'));
  final relay = RelayStore();
  Timer.periodic(const Duration(minutes: 1), (_) => relay.purgeExpired(DateTime.now()));

  // Identity checks. Until LifeTrack is a DigiLocker partner, only the
  // practice stand-in exists; real DigiLocker is configuration, not code.
  final practice = args.contains('--practice-digilocker');
  final identity = practice
      ? IdentityService(
          provider: PracticeDigiLocker(),
          registryKey: signingKey,
          hmacSecret: await _secret(File('${dataDir.path}/identity_secret')),
          trust: RegistryTrust([await signingKey.extractPublicKey()]),
        )
      : null;
  final api = LifeTrackApi(registry: registry, relay: relay, vault: VaultStore(Directory('${dataDir.path}/vault')), ids: await IdRegistry.open(file: File('${dataDir.path}/ids.json')), adminToken: adminToken,
      identity: identity, requireIdentity: args.contains('--require-identity'));
  final server = await io.serve(api.handler, InternetAddress.loopbackIPv4, port);
  final pub = base64Encode((await signingKey.extractPublicKey()).bytes);
  stdout
    ..writeln('LifeTrack local server on http://${server.address.address}:${server.port}')
    ..writeln('Registry public key (pin this in the apps): $pub')
    ..writeln('Admin token is in ${dataDir.path}/admin_token')
    ..writeln(identity == null ? 'Identity checks: off' : 'Identity checks: PRACTICE DigiLocker (not real)${args.contains('--require-identity') ? ', required for new IDs' : ''}');
}

String? _arg(List<String> args, String name) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

/// The registry's Ed25519 key, created on first run. Local development only:
/// a real deployment keeps it in a KMS/HSM, never in a file.
Future<SimpleKeyPair> _registryKey(File f) async {
  if (await f.exists()) {
    final seed = base64Decode((jsonDecode(await f.readAsString()) as Map)['seed']! as String);
    return Ed25519().newKeyPairFromSeed(seed);
  }
  final r = Random.secure();
  final seed = List<int>.generate(32, (_) => r.nextInt(256));
  await f.writeAsString(jsonEncode({'seed': base64Encode(seed)}), flush: true);
  if (!Platform.isWindows) await Process.run('chmod', ['600', f.path]);
  return Ed25519().newKeyPairFromSeed(seed);
}

Future<String> _adminToken(File f) async {
  if (await f.exists()) return (await f.readAsString()).trim();
  final r = Random.secure();
  final t = base64Url.encode(List.generate(24, (_) => r.nextInt(256)));
  await f.writeAsString(t, flush: true);
  if (!Platform.isWindows) await Process.run('chmod', ['600', f.path]);
  return t;
}

/// A random 32-byte secret kept in [f]; the key for identity hashes.
Future<List<int>> _secret(File f) async {
  if (await f.exists()) return base64Decode((await f.readAsString()).trim());
  final r = Random.secure();
  final k = List<int>.generate(32, (_) => r.nextInt(256));
  await f.writeAsString(base64Encode(k), flush: true);
  if (!Platform.isWindows) await Process.run('chmod', ['600', f.path]);
  return k;
}
