import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';

/// What DigiLocker tells us about the signed-in account, and the birth
/// certificates the user chose to share from it.
class DlAccount {
  const DlAccount({required this.id, required this.name, required this.dateOfBirth, required this.gender, required this.aadhaarLinked, this.birthCertificates = const []});
  final String id;
  final String name;
  final DateTime dateOfBirth;
  final String? gender;

  /// DigiLocker's own flag that the account is tied to an Aadhaar (eAadhaar).
  final bool aadhaarLinked;
  final List<DlBirthCertificate> birthCertificates;
}

class DlBirthCertificate {
  const DlBirthCertificate({required this.number, required this.childName, required this.dateOfBirth, required this.gender, required this.parentNames});
  final String number;
  final String childName;
  final DateTime dateOfBirth;
  final String? gender;
  final List<String> parentNames;
}

/// DigiLocker's OAuth sign-in, as the server sees it. The real one needs the
/// partner credentials LifeTrack gets on registration with DigiLocker; the
/// [PracticeDigiLocker] stands in until then.
abstract interface class DigiLockerProvider {
  String get name;
  Uri authorizeUrl({required Uri base, required String state, required String codeChallenge, required String purpose});
  Future<DlAccount> finish({required String code, required String codeVerifier});
}

enum VerifyPurpose { self, newborn }

class VerifyRefused implements Exception {
  const VerifyRefused(this.message);
  final String message;
}

class _Session {
  _Session({required this.secretHash, required this.purpose, required this.verifier, required this.createdAt, this.parent});
  final String secretHash;
  final VerifyPurpose purpose;
  final String verifier;
  final DateTime createdAt;
  final IdentityAttestation? parent;
  String status = 'pending';
  IdentityAttestation? result;
  String? error;
}

/// Runs one identity check from start to signed result. The DigiLocker
/// token, the account id and the documents are used and dropped here: what
/// leaves is a signed [IdentityAttestation] with a keyed hash in place of
/// any identifier. Sessions last ten minutes.
class IdentityService {
  IdentityService({required this.provider, required this.registryKey, required List<int> hmacSecret, required this.trust, DateTime Function()? clock})
      : _hmacKey = SecretKey(hmacSecret),
        clock = clock ?? DateTime.now;

  final DigiLockerProvider provider;
  final SimpleKeyPair registryKey;
  final RegistryTrust trust;
  final SecretKey _hmacKey;
  final DateTime Function() clock;

  static const sessionLife = Duration(minutes: 10);

  /// How young a child must be to use a birth certificate instead of their
  /// own Aadhaar (user decision, 1 Oct 2026: newborns only).
  static const newbornWindow = Duration(days: 365);

  final Map<String, _Session> _sessions = {};

  Future<String> _subject(String kind, String id) async {
    final mac = await Hmac.sha256().calculateMac(utf8.encode('$kind:$id'), secretKey: _hmacKey);
    return mac.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  void _purge() {
    final now = clock();
    _sessions.removeWhere((_, s) => now.difference(s.createdAt) > sessionLife);
  }

  static String _rand(int n) {
    final r = Random.secure();
    return base64Url.encode(List.generate(n, (_) => r.nextInt(256))).replaceAll('=', '');
  }

  /// Returns (session id, secret, where to send the user).
  Future<(String, String, Uri)> start({required Uri base, required VerifyPurpose purpose, IdentityAttestation? parent}) async {
    _purge();
    if (purpose == VerifyPurpose.newborn) {
      if (parent == null || parent.method != IdentityMethod.aadhaarDigiLocker || !await parent.verifies(trust)) {
        throw const VerifyRefused('A newborn is added by a parent whose own profile is verified with Aadhaar.');
      }
    }
    final id = _rand(16);
    final secret = _rand(24);
    final verifier = _rand(32);
    final challenge = base64Url.encode((await Sha256().hash(utf8.encode(verifier))).bytes).replaceAll('=', '');
    _sessions[id] = _Session(secretHash: await RelayApi.sha256Hex(secret), purpose: purpose, verifier: verifier, createdAt: clock(), parent: parent);
    return (id, secret, provider.authorizeUrl(base: base, state: id, codeChallenge: challenge, purpose: purpose.name));
  }

  /// DigiLocker sent the user back. Records the result or the reason, and
  /// returns the reason (null when the check succeeded) for the page the
  /// person sees in the browser.
  Future<String?> callback({required String state, required String? code, String? error}) async {
    _purge();
    final s = _sessions[state];
    if (s == null) throw const VerifyRefused('This verification has expired. Start again in the app.');
    if (code == null) {
      s
        ..status = 'error'
        ..error = error == null ? 'DigiLocker sign-in was cancelled.' : 'DigiLocker said: $error';
      return s.error;
    }
    try {
      final acct = await provider.finish(code: code, codeVerifier: s.verifier);
      s.result = switch (s.purpose) {
        VerifyPurpose.self => await _self(acct),
        VerifyPurpose.newborn => await _newborn(acct, s.parent!),
      };
      s.status = 'done';
      return null;
    } on VerifyRefused catch (e) {
      s
        ..status = 'error'
        ..error = e.message;
      return e.message;
    }
  }

  Future<IdentityAttestation> _self(DlAccount a) async {
    if (!a.aadhaarLinked) throw const VerifyRefused('This DigiLocker account is not linked to an Aadhaar. Link Aadhaar in DigiLocker, then try again.');
    return IdentityAttestation(
      method: IdentityMethod.aadhaarDigiLocker,
      name: a.name,
      dateOfBirth: a.dateOfBirth,
      gender: a.gender,
      subjectHash: await _subject('dl', a.id),
      verifiedAt: clock(),
    ).signedWith(registryKey);
  }

  static String _norm(String n) => n.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

  Future<IdentityAttestation> _newborn(DlAccount a, IdentityAttestation parent) async {
    // The certificate must come from the verified parent's own DigiLocker…
    if (await _subject('dl', a.id) != parent.subjectHash) {
      throw const VerifyRefused('Sign in to DigiLocker as the parent whose profile is on this phone.');
    }
    // …name that parent, and be for a child under one year.
    final now = clock();
    final cert = a.birthCertificates.where((c) => c.parentNames.any((p) => _norm(p) == _norm(parent.name))).firstOrNull;
    if (cert == null) throw VerifyRefused('No birth certificate in this DigiLocker names ${parent.name} as a parent.');
    if (now.difference(cert.dateOfBirth) > newbornWindow) {
      throw const VerifyRefused('This child is over one year old. Children with Aadhaar (Baal Aadhaar) are verified with their own Aadhaar through DigiLocker.');
    }
    return IdentityAttestation(
      method: IdentityMethod.birthCertificateDigiLocker,
      name: cert.childName,
      dateOfBirth: cert.dateOfBirth,
      gender: cert.gender,
      subjectHash: await _subject('bc', cert.number),
      verifiedAt: now,
      parentSubjectHash: parent.subjectHash,
    ).signedWith(registryKey);
  }

  /// The app collects the result with the session's secret; a finished
  /// session is removed as it is handed over.
  Future<Map<String, Object?>> poll(String id, String secret) async {
    _purge();
    final s = _sessions[id];
    if (s == null || s.secretHash != await RelayApi.sha256Hex(secret)) return {'status': 'expired'};
    if (s.status == 'pending') return {'status': 'pending'};
    _sessions.remove(id);
    return s.status == 'done' ? {'status': 'done', 'attestation': s.result!.toJson()} : {'status': 'error', 'error': s.error};
  }
}

/// A stand-in DigiLocker for development and demos: a consent page with
/// sample people and one sample birth certificate. Nothing here is a real
/// person or a real document.
class PracticeDigiLocker implements DigiLockerProvider {
  @override
  String get name => 'practice';

  static final accounts = <String, DlAccount>{
    'anjali': DlAccount(
      id: 'practice-anjali',
      name: 'Anjali Sharma',
      dateOfBirth: DateTime(1984, 6, 14),
      gender: 'F',
      aadhaarLinked: true,
      birthCertificates: [
        DlBirthCertificate(number: 'PRACTICE-BC-2026-0001', childName: 'Baby of Anjali Sharma', dateOfBirth: DateTime(2026, 8, 20), gender: 'M', parentNames: const ['Anjali Sharma', 'Vikram Sharma']),
      ],
    ),
    'ramesh': DlAccount(id: 'practice-ramesh', name: 'Ramesh Sharma', dateOfBirth: DateTime(1955, 1, 10), gender: 'M', aadhaarLinked: true),
    'vikram': DlAccount(id: 'practice-vikram', name: 'Vikram Sharma', dateOfBirth: DateTime(1982, 3, 2), gender: 'M', aadhaarLinked: true),
    'noaadhaar': DlAccount(id: 'practice-noaadhaar', name: 'Sample Without Aadhaar', dateOfBirth: DateTime(1990), gender: 'F', aadhaarLinked: false),
  };

  final Map<String, (String account, String challenge)> _codes = {};

  @override
  Uri authorizeUrl({required Uri base, required String state, required String codeChallenge, required String purpose}) =>
      base.replace(path: '/v1/practice-digilocker/authorize', queryParameters: {'state': state, 'challenge': codeChallenge, 'purpose': purpose});

  /// Issues a code for the chosen sample account, like DigiLocker does after
  /// the user consents.
  String approve(String account, String challenge) {
    final code = base64Url.encode(List.generate(12, (_) => Random.secure().nextInt(256)));
    _codes[code] = (account, challenge);
    return code;
  }

  @override
  Future<DlAccount> finish({required String code, required String codeVerifier}) async {
    final c = _codes.remove(code);
    if (c == null) throw const VerifyRefused('DigiLocker did not recognise the sign-in.');
    final challenge = base64Url.encode((await Sha256().hash(utf8.encode(codeVerifier))).bytes).replaceAll('=', '');
    if (challenge != c.$2) throw const VerifyRefused('DigiLocker sign-in did not match this session.');
    return accounts[c.$1]!;
  }

  static String page({required String state, required String challenge, required String purpose}) {
    String esc(String s) => const HtmlEscape().convert(s);
    final rows = [
      for (final e in accounts.entries)
        '<a class="acct" href="/v1/practice-digilocker/approve?state=${Uri.encodeQueryComponent(state)}&challenge=${Uri.encodeQueryComponent(challenge)}&account=${e.key}">'
            '<b>${esc(e.value.name)}</b><span>${e.value.aadhaarLinked ? 'Aadhaar linked' : 'No Aadhaar linked'}'
            '${purpose == 'newborn' && e.value.birthCertificates.isNotEmpty ? ' · shares birth certificate of ${esc(e.value.birthCertificates.first.childName)}' : ''}</span></a>',
    ].join();
    return '<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Practice DigiLocker</title>'
        '<style>body{font:16px system-ui;margin:0;background:#f4f4f2;color:#111}header{background:#1b3a6b;color:#fff;padding:18px}'
        '.warn{background:#fef3c7;color:#78350f;padding:12px 18px;font-size:14px}main{padding:18px}'
        '.acct{display:block;background:#fff;border-radius:14px;padding:16px;margin-bottom:12px;text-decoration:none;color:#111}'
        '.acct span{display:block;color:#555;font-size:14px;margin-top:4px}</style></head><body>'
        '<header><b>Practice DigiLocker</b><div style="font-size:14px;opacity:.8">Stand-in for development — not the real DigiLocker</div></header>'
        '<div class="warn">Sample people only. In a real build this is DigiLocker\'s own sign-in with an Aadhaar OTP.</div>'
        '<main><p>${purpose == 'newborn' ? 'Sign in as the parent and share the newborn\'s birth certificate with LifeTrack:' : 'Choose who is signing in, and allow LifeTrack to read your name, date of birth and gender:'}</p>$rows</main></body></html>';
  }
}
