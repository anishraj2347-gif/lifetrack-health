import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:lifetrack_server/api.dart';
import 'package:lifetrack_server/guards.dart';
import 'package:lifetrack_server/registry.dart';
import 'package:lifetrack_server/relay_store.dart';
import 'package:lifetrack_server/vault_store.dart';
import 'package:lifetrack_server/id_registry.dart';
import 'package:lifetrack_server/digilocker_api.dart';
import 'package:lifetrack_server/identity.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';
import 'package:shelf/shelf_io.dart' as io;

/// Local phase 2 server. Binds to 127.0.0.1 only — nothing on the Wi-Fi can
/// reach it. The phone reaches it over USB with `adb reverse tcp:8787 tcp:8787`.
///
///   dart run bin/server.dart [--port 8787] [--data data]
///       [--public-base https://lifetrack.example] [--allow-origin https://doctor.example]
///       [--trust-proxy] [--lan]
///
/// `--lan` (home Wi-Fi, 12 Oct 2026): also listens on the laptop's Wi-Fi
/// address so the phone works without the cable. Plain HTTP on the home
/// network: shares, family-link messages and backups are end-to-end
/// encrypted before they reach it, but anyone on the same Wi-Fi can see
/// which IDs talk to the server and when. Pass `--public-base
/// http://<laptop-ip>:<port>` with it (scripts/run_server_lan.sh does).
///
/// `--trust-proxy`: a reverse proxy you run is in front and appends the
/// caller's address to X-Forwarded-For; rate limits then count per caller
/// instead of treating everyone as 127.0.0.1. Never set it without a proxy:
/// a client could then choose its own address.
///
/// Browsers may call it only from loopback pages and `--allow-origin`s, and
/// only under loopback Host names or the host of `--public-base` (refusing
/// DNS-rebinding pages).
Future<void> main(List<String> args) async {
  final port = int.parse(_arg(args, '--port') ?? '8787');
  final dataDir = Directory(_arg(args, '--data') ?? 'data');
  await dataDir.create(recursive: true);
  // Owner-only: the ID map, doctor enrolments, backups and keys. A folder
  // others cannot open protects every file in it, including ones written later.
  if (!Platform.isWindows) await Process.run('chmod', ['-R', 'go-rwx', dataDir.path]);

  final signingKey = await _registryKey(File('${dataDir.path}/registry_key.json'));
  final adminToken = await _adminToken(File('${dataDir.path}/admin_token'));
  final registry = await DoctorRegistry.open(signingKey: signingKey, file: File('${dataDir.path}/doctors.json'));
  final relay = RelayStore();
  Timer.periodic(const Duration(minutes: 1), (_) => relay.purgeExpired(DateTime.now()));

  // Identity checks: the real DigiLocker once its partner keys are in
  // data/digilocker.json, else the practice stand-in when asked for.
  final practice = args.contains('--practice-digilocker');
  final keys = File('${dataDir.path}/digilocker.json');
  final real = !practice && await keys.exists() ? DigiLockerCredentials.fromJson((jsonDecode(await keys.readAsString()) as Map).cast()) : null;
  final DigiLockerProvider? provider = real != null ? DigiLockerApi(real) : practice ? PracticeDigiLocker() : null;
  final identity = provider != null
      ? IdentityService(
          provider: provider,
          registryKey: signingKey,
          hmacSecret: await _secret(File('${dataDir.path}/identity_secret')),
          trust: RegistryTrust([await signingKey.extractPublicKey()]),
        )
      : null;
  final publicBase = _arg(args, '--public-base') == null ? null : Uri.parse(_arg(args, '--public-base')!);
  final api = LifeTrackApi(
    registry: registry,
    relay: relay,
    vault: VaultStore(Directory('${dataDir.path}/vault')),
    ids: await IdRegistry.open(file: File('${dataDir.path}/ids.json')),
    adminToken: adminToken,
    identity: identity,
    requireIdentity: args.contains('--require-identity'),
    publicBase: publicBase,
    trustProxy: args.contains('--trust-proxy'),
    origins: OriginPolicy(
      publicHosts: {?publicBase?.host},
      allowedOrigins: {for (var i = 0; i < args.length - 1; i++) if (args[i] == '--allow-origin') args[i + 1]},
    ),
  );
  final lan = args.contains('--lan');
  if (lan && publicBase == null) {
    stderr.writeln('--lan needs --public-base http://<laptop-ip>:$port (the address the phone uses).');
    exit(64);
  }
  final server = await io.serve(api.handler, lan ? InternetAddress.anyIPv4 : InternetAddress.loopbackIPv4, port);
  final pub = base64Encode((await signingKey.extractPublicKey()).bytes);
  stdout
    ..writeln(lan ? 'LifeTrack server on this laptop and the Wi-Fi: $publicBase (and http://127.0.0.1:${server.port})' : 'LifeTrack local server on http://${server.address.address}:${server.port}')
    ..writeln('Registry public key (pin this in the apps): $pub')
    ..writeln('Admin token is in ${dataDir.path}/admin_token')
    ..writeln(args.contains('--trust-proxy')
        ? 'Rate limits: per X-Forwarded-For client (--trust-proxy)'
        : publicBase != null
            ? 'Rate limits: per connection — behind a proxy every caller shares one budget; add --trust-proxy'
            : 'Rate limits: per connection')
    ..writeln(identity == null
        ? 'Identity checks: off'
        : '${real != null ? 'Identity checks: DigiLocker (${real.baseUrl.host})' : 'Identity checks: PRACTICE DigiLocker (not real)'}${args.contains('--require-identity') ? ', required for new IDs' : ''}');
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
