import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:lifetrack_server/digilocker_api.dart';
import 'package:lifetrack_server/identity.dart';
import 'package:test/test.dart';

/// The real DigiLocker client against a stand-in that answers as the
/// Requester API Specification v1.12 describes (sample responses from it).
void main() {
  const secret = 'partner-secret';
  late HttpServer fake;
  late DigiLockerApi api;
  late Map<String, Object?> tokenResponse;
  late List<String> calls;
  late String certXml;
  var badHmac = false;

  Future<String> hmacOf(List<int> body) async => base64.encode((await Hmac.sha256().calculateMac(body, secretKey: SecretKey(utf8.encode(secret)))).bytes);

  setUp(() async {
    calls = [];
    badHmac = false;
    certXml = '<?xml version="1.0"?><Certificate language="99" name="Birth Certificate" type="BTCER" number="BC-2026-77">'
        '<IssuedBy><Organization name="Municipal Corporation"/></IssuedBy>'
        '<IssuedTo><Person name="Baby Sharma" dob="20-08-2026" gender="M"/></IssuedTo>'
        '<CertificateData><BirthDetails fatherName="Vikram Sharma" motherName="Anjali Sharma"/></CertificateData></Certificate>';
    tokenResponse = {
      'access_token': 'bc125c',
      'expires_in': 3600,
      'token_type': 'Bearer',
      'scope': 'files.issueddocs userdetails',
      'digilockerid': '123e4567-e89b-12d3-a456-426655440000',
      'name': 'Anjali Sharma',
      'dob': '14061984',
      'gender': 'F',
      'eaadhaar': 'Y',
      'reference_key': '2a33',
    };
    fake = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    fake.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      calls.add('${req.method} ${req.uri.path}');
      final res = req.response;
      switch (req.uri.path) {
        case '/public/oauth2/1/token':
          final f = Uri.splitQueryString(body);
          final ok = f['grant_type'] == 'authorization_code' && f['client_id'] == 'lt-client' && f['client_secret'] == secret && f['code'] == 'good-code' && f['code_verifier'] == 'v' * 43;
          res.statusCode = ok ? 200 : 400;
          res.write(jsonEncode(ok ? tokenResponse : {'error': 'invalid_grant', 'error_description': 'The code is invalid'}));
        case '/public/oauth2/2/files/issued':
          res.write(jsonEncode({
            'items': [
              {'name': 'Class XII Marksheet', 'type': 'file', 'uri': 'in.gov.cbse-HSCER-2014', 'doctype': 'HSCER'},
              {'name': 'Birth Certificate', 'type': 'file', 'uri': 'in.gov.mcd-BTCER-77', 'doctype': 'BTCER', 'mime': ['application/pdf', 'application/xml']},
            ],
          }));
        case '/public/oauth2/1/xml/in.gov.mcd-BTCER-77':
          final bytes = utf8.encode(certXml);
          res.headers.set('hmac', badHmac ? base64.encode(List.filled(32, 1)) : await hmacOf(bytes));
          res.add(bytes);
        case '/public/oauth2/1/revoke':
          res.statusCode = 200;
        default:
          res.statusCode = 404;
      }
      await res.close();
    });
    api = DigiLockerApi(DigiLockerCredentials(
      clientId: 'lt-client',
      clientSecret: secret,
      redirectUri: Uri.parse('https://lifetrack.example/v1/verify/callback'),
      baseUrl: Uri.parse('http://127.0.0.1:${fake.port}'),
    ));
  });
  tearDown(() => fake.close(force: true));

  test('the sign-in link carries PKCE S256, the registered redirect and, for a newborn, the birth certificate', () {
    final u = api.authorizeUrl(base: Uri.parse('https://x'), state: 's1', codeChallenge: 'c' * 43, purpose: 'newborn');
    expect(u.path, '/public/oauth2/1/authorize');
    expect(u.queryParameters, containsPair('response_type', 'code'));
    expect(u.queryParameters, containsPair('code_challenge_method', 'S256'));
    expect(u.queryParameters, containsPair('redirect_uri', 'https://lifetrack.example/v1/verify/callback'));
    expect(u.queryParameters, containsPair('req_doctype', 'BTCER'));
    expect(api.authorizeUrl(base: Uri.parse('https://x'), state: 's', codeChallenge: 'c', purpose: 'self').queryParameters.containsKey('req_doctype'), isFalse);
  });

  test('the account comes from the token response; the token is revoked afterwards', () async {
    final a = await api.finish(code: 'good-code', codeVerifier: 'v' * 43);
    expect(a.name, 'Anjali Sharma');
    expect(a.dateOfBirth, DateTime(1984, 6, 14));
    expect(a.gender, 'F');
    expect(a.aadhaarLinked, isTrue);
    expect(a.birthCertificates.single.childName, 'Baby Sharma');
    expect(a.birthCertificates.single.dateOfBirth, DateTime(2026, 8, 20));
    expect(a.birthCertificates.single.parentNames, containsAll(['Vikram Sharma', 'Anjali Sharma']));
    expect(a.birthCertificates.single.number, 'BC-2026-77');
    expect(calls.last, 'POST /public/oauth2/1/revoke');
  });

  test('a certificate whose HMAC does not match is not used', () async {
    badHmac = true;
    expect((await api.finish(code: 'good-code', codeVerifier: 'v' * 43)).birthCertificates, isEmpty);
  });

  test('no eAadhaar, a wrong code or an unreadable date is refused, never guessed', () async {
    tokenResponse['eaadhaar'] = 'N';
    expect((await api.finish(code: 'good-code', codeVerifier: 'v' * 43)).aadhaarLinked, isFalse);
    await expectLater(api.finish(code: 'bad', codeVerifier: 'v' * 43), throwsA(isA<VerifyRefused>().having((e) => e.message, 'message', contains('The code is invalid'))));
    tokenResponse['dob'] = '31021990';
    await expectLater(api.finish(code: 'good-code', codeVerifier: 'v' * 43), throwsA(isA<VerifyRefused>()));
  });

  test('credentials file: every field is required except the base URL', () {
    expect(() => DigiLockerCredentials.fromJson({'clientId': 'a', 'clientSecret': 'b'}), throwsFormatException);
    final c = DigiLockerCredentials.fromJson({'clientId': 'a', 'clientSecret': 'b', 'redirectUri': 'https://h/v1/verify/callback'});
    expect(c.baseUrl, DigiLockerCredentials.defaultBase);
  });

  test('dates as DigiLocker writes them', () {
    expect(DigiLockerApi.parseDdMmYyyy('31121970'), DateTime(1970, 12, 31));
    expect(DigiLockerApi.parseDdMmYyyy('1970-12-31'), isNull);
    expect(DigiLockerApi.parseDate('20/08/2026'), DateTime(2026, 8, 20));
    expect(DigiLockerApi.parseDate('2026-08-20'), DateTime(2026, 8, 20));
    expect(DigiLockerApi.parseBirthCertificate('<Certificate><IssuedTo><Person name="X"/></IssuedTo></Certificate>', fallbackNumber: 'u'), isNull);
  });
}
