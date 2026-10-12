import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import 'identity.dart';

/// The partner credentials DigiLocker issues on registration, read from
/// `data/digilocker.json` (owner-only, like every file in data/):
///
///   {"clientId": "...", "clientSecret": "...",
///    "redirectUri": "https://<server>/v1/verify/callback",
///    "baseUrl": "https://api.digitallocker.gov.in"}   // optional
///
/// `redirectUri` must be exactly the one registered on the DigiLocker
/// Partner Portal, and must reach this server's /v1/verify/callback.
class DigiLockerCredentials {
  DigiLockerCredentials({required this.clientId, required this.clientSecret, required this.redirectUri, Uri? baseUrl})
      : baseUrl = baseUrl ?? defaultBase;
  final String clientId;
  final String clientSecret;
  final Uri redirectUri;
  final Uri baseUrl;

  static final defaultBase = Uri.parse('https://api.digitallocker.gov.in');

  static DigiLockerCredentials fromJson(Map<String, Object?> j) {
    String need(String k) => (j[k] as String?)?.trim().isNotEmpty == true ? (j[k]! as String).trim() : throw FormatException('digilocker.json: "$k" is missing');
    return DigiLockerCredentials(
      clientId: need('clientId'),
      clientSecret: need('clientSecret'),
      redirectUri: Uri.parse(need('redirectUri')),
      baseUrl: j['baseUrl'] == null ? null : Uri.parse(j['baseUrl']! as String),
    );
  }
}

/// The real DigiLocker, after the Requester API Specification v1.12
/// (NeGD, Sept 2023): authorization code with PKCE (S256), the access token
/// whose response already carries name, dob (DDMMYYYY), gender and the
/// eAadhaar flag, and — for a newborn — the issued birth certificates
/// (doctype BTCER) read as XML, each checked against DigiLocker's HMAC.
///
/// Untested against the live service until LifeTrack has partner keys; the
/// birth-certificate XML fields in particular vary by issuer and must be
/// checked against the first real certificate (see [parseBirthCertificate]).
class DigiLockerApi implements DigiLockerProvider {
  DigiLockerApi(this.credentials, {HttpClient? client}) : _client = client ?? HttpClient();
  final DigiLockerCredentials credentials;
  final HttpClient _client;

  /// DigiLocker's document type for a birth certificate.
  static const birthCertificateDoctype = 'BTCER';

  @override
  String get name => 'digilocker';

  Uri _at(String path) => credentials.baseUrl.replace(path: path);

  @override
  Uri authorizeUrl({required Uri base, required String state, required String codeChallenge, required String purpose}) =>
      _at('/public/oauth2/1/authorize').replace(queryParameters: {
        'response_type': 'code',
        'client_id': credentials.clientId,
        'redirect_uri': credentials.redirectUri.toString(),
        'state': state,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        'purpose': 'verification',
        // A newborn's check needs the birth certificate on the consent page.
        if (purpose == 'newborn') 'req_doctype': birthCertificateDoctype,
      });

  @override
  Future<DlAccount> finish({required String code, required String codeVerifier}) async {
    final token = await _post('/public/oauth2/1/token', {
      'code': code,
      'grant_type': 'authorization_code',
      'client_id': credentials.clientId,
      'client_secret': credentials.clientSecret,
      'redirect_uri': credentials.redirectUri.toString(),
      'code_verifier': codeVerifier,
    });
    final access = token['access_token'] as String?;
    if (access == null) throw const VerifyRefused('DigiLocker did not complete the sign-in.');
    try {
      // The token response carries the account (spec 1.6+); ask for it only
      // if an older response left it out.
      final who = token['digilockerid'] == null ? await _getJson('/public/oauth2/1/user', access) : token;
      final id = who['digilockerid'] as String?;
      final name = (who['name'] as String?)?.trim();
      final dob = parseDdMmYyyy(who['dob'] as String?);
      if (id == null || name == null || name.isEmpty || dob == null) throw const VerifyRefused('DigiLocker did not return a name and date of birth.');
      final scopes = ((token['scope'] as String?) ?? '').split(' ');
      return DlAccount(
        id: id,
        name: name,
        dateOfBirth: dob,
        gender: switch (who['gender']) { 'M' => 'M', 'F' => 'F', 'T' => 'T', _ => null },
        aadhaarLinked: who['eaadhaar'] == 'Y',
        birthCertificates: scopes.contains('files.issueddocs') ? await _birthCertificates(access) : const [],
      );
    } finally {
      // Nothing more is needed from this account: end the grant at once.
      await _revoke(access);
    }
  }

  Future<List<DlBirthCertificate>> _birthCertificates(String access) async {
    final list = await _getJson('/public/oauth2/2/files/issued', access);
    final out = <DlBirthCertificate>[];
    for (final item in ((list['items'] as List?) ?? const []).whereType<Map>()) {
      if (item['doctype'] != birthCertificateDoctype) continue;
      final uri = (item['uri'] as String?)?.trim();
      if (uri == null || uri.isEmpty) continue;
      final xml = await _getVerifiedXml('/public/oauth2/1/xml/$uri', access);
      final cert = xml == null ? null : parseBirthCertificate(xml, fallbackNumber: uri);
      if (cert != null) out.add(cert);
    }
    return out;
  }

  /// The certificate XML, only if DigiLocker's HMAC (SHA-256 keyed with our
  /// client secret, base64, in the `hmac` header) matches what arrived.
  Future<String?> _getVerifiedXml(String path, String access) async {
    final req = await _client.getUrl(_at(path));
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $access');
    final res = await req.close();
    final body = await res.fold<List<int>>([], (a, b) => a..addAll(b));
    if (res.statusCode != 200) return null;
    final sent = res.headers.value('hmac');
    final mac = await Hmac.sha256().calculateMac(body, secretKey: SecretKey(utf8.encode(credentials.clientSecret)));
    if (sent == null || base64.encode(mac.bytes) != sent.trim()) return null;
    return utf8.decode(body, allowMalformed: true);
  }

  Future<Map<String, Object?>> _post(String path, Map<String, String> form) async {
    final req = await _client.postUrl(_at(path));
    req.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
    req.write(Uri(queryParameters: form).query);
    return _read(await req.close());
  }

  Future<Map<String, Object?>> _getJson(String path, String access) async {
    final req = await _client.getUrl(_at(path));
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $access');
    return _read(await req.close());
  }

  Future<void> _revoke(String access) async {
    try {
      final req = await _client.postUrl(_at('/public/oauth2/1/revoke'));
      req.headers
        ..set(HttpHeaders.authorizationHeader, 'Basic ${base64.encode(utf8.encode('${credentials.clientId}:${credentials.clientSecret}'))}')
        ..contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      req.write(Uri(queryParameters: {'token': access, 'token_type_hint': 'access_token'}).query);
      await (await req.close()).drain<void>();
    } on Object {
      // The token expires on its own within the hour.
    }
  }

  static Future<Map<String, Object?>> _read(HttpClientResponse res) async {
    final text = await res.transform(utf8.decoder).join();
    Object? body;
    try {
      body = jsonDecode(text);
    } on FormatException {
      body = null;
    }
    if (res.statusCode != 200 || body is! Map) {
      final why = body is Map ? (body['error_description'] ?? body['error']) : null;
      throw VerifyRefused('DigiLocker refused the request${why == null ? '' : ': $why'}.');
    }
    return body.cast<String, Object?>();
  }

  /// DigiLocker's `dob`: DDMMYYYY.
  static DateTime? parseDdMmYyyy(String? s) {
    if (s == null || !RegExp(r'^\d{8}$').hasMatch(s)) return null;
    final d = int.parse(s.substring(0, 2)), m = int.parse(s.substring(2, 4)), y = int.parse(s.substring(4));
    final t = DateTime(y, m, d);
    return t.day == d && t.month == m ? t : null;
  }

  /// Reads a DigiLocker birth certificate. Issuers follow DigiLocker's
  /// certificate schema (`<Certificate number=…><IssuedTo><Person name=…
  /// dob=… gender=…/>`) but name the parents differently, so any attribute
  /// or element whose name mentions father, mother or parent is taken.
  /// Returns null when the child's name or date of birth cannot be read —
  /// the check is then refused rather than guessed.
  static DlBirthCertificate? parseBirthCertificate(String xml, {required String fallbackNumber}) {
    String? attr(String tag, String name) {
      final el = RegExp('<(?:\\w+:)?$tag\\b[^>]*>', caseSensitive: false).firstMatch(xml)?.group(0);
      if (el == null) return null;
      return RegExp('\\b$name\\s*=\\s*"([^"]*)"', caseSensitive: false).firstMatch(el)?.group(1)?.trim();
    }

    final childName = attr('Person', 'name');
    final dob = parseDate(attr('Person', 'dob'));
    if (childName == null || childName.isEmpty || dob == null) return null;
    final parents = <String>{
      for (final m in RegExp(r'\b\w*(?:father|mother|parent)\w*name\w*\s*=\s*"([^"]+)"', caseSensitive: false).allMatches(xml)) m.group(1)!.trim(),
      for (final m in RegExp(r'<(?:\w+:)?\w*(?:father|mother|parent)\w*\b[^>]*\bname\s*=\s*"([^"]+)"', caseSensitive: false).allMatches(xml)) m.group(1)!.trim(),
    }..removeWhere((p) => p.isEmpty);
    final gender = attr('Person', 'gender')?.toUpperCase();
    return DlBirthCertificate(
      number: attr('Certificate', 'number') ?? fallbackNumber,
      childName: childName,
      dateOfBirth: dob,
      gender: switch (gender) { 'M' || 'MALE' => 'M', 'F' || 'FEMALE' => 'F', _ => null },
      parentNames: parents.toList(),
    );
  }

  /// Certificate dates: dd-MM-yyyy, dd/MM/yyyy or yyyy-MM-dd.
  static DateTime? parseDate(String? s) {
    if (s == null) return null;
    final dmy = RegExp(r'^(\d{2})[-/](\d{2})[-/](\d{4})$').firstMatch(s.trim());
    final ymd = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s.trim());
    final (y, m, d) = dmy != null
        ? (int.parse(dmy.group(3)!), int.parse(dmy.group(2)!), int.parse(dmy.group(1)!))
        : ymd != null
            ? (int.parse(ymd.group(1)!), int.parse(ymd.group(2)!), int.parse(ymd.group(3)!))
            : (0, 0, 0);
    if (y == 0) return null;
    final t = DateTime(y, m, d);
    return t.day == d && t.month == m ? t : null;
  }
}
