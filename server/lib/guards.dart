import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

/// Counts per (client, bucket) in fixed windows. Memory is bounded: when the
/// table grows large, windows that have ended are dropped.
class RateLimiter {
  RateLimiter({DateTime Function()? clock}) : clock = clock ?? DateTime.now;
  final DateTime Function() clock;
  final Map<String, (DateTime, int)> _windows = {};

  static const _maxEntries = 100000;

  /// True when this hit is within [limit] per [window].
  bool allow(String key, int limit, Duration window) {
    final now = clock();
    if (_windows.length > _maxEntries) {
      _windows.removeWhere((_, v) => now.difference(v.$1) >= const Duration(hours: 1));
    }
    final w = _windows[key];
    if (w == null || now.difference(w.$1) >= window) {
      _windows[key] = (now, 1);
      return true;
    }
    if (w.$2 >= limit) return false;
    _windows[key] = (w.$1, w.$2 + 1);
    return true;
  }
}

/// One rate rule: requests whose method and path match share a budget.
class RateRule {
  const RateRule(this.method, this.path, this.limit, this.window);
  final String method;
  final RegExp path;
  final int limit;
  final Duration window;
}

/// The caller's address, or `local` for in-process requests (tests).
///
/// The server listens on loopback only, so behind a reverse proxy every
/// connection comes from 127.0.0.1 and would share one budget. With
/// [trustProxy] (`--trust-proxy`, only when a proxy you run is in front), the
/// client is the last `X-Forwarded-For` entry — the address that proxy saw
/// and appended; entries a client wrote itself come before it and are
/// ignored.
String clientOf(Request req, {bool trustProxy = false}) {
  if (trustProxy) {
    final hops = (req.headers['x-forwarded-for'] ?? '').split(',').map((h) => h.trim()).where((h) => h.isNotEmpty);
    if (hops.isNotEmpty) return hops.last;
  }
  return (req.context['shelf.io.connection_info'] as HttpConnectionInfo?)?.remoteAddress.address ?? 'local';
}

Response _err(int status, String message) =>
    Response(status, body: jsonEncode({'error': message}), headers: {'content-type': 'application/json'});

/// Refuses a client that has used up the budget of the first rule matching
/// the request.
Middleware rateLimit(RateLimiter limiter, List<RateRule> rules, {bool trustProxy = false}) => (inner) => (req) {
      final path = '/${req.url.path}';
      for (var i = 0; i < rules.length; i++) {
        final r = rules[i];
        if (r.method != req.method || !r.path.hasMatch(path)) continue;
        if (!limiter.allow('${clientOf(req, trustProxy: trustProxy)}|$i', r.limit, r.window)) return _err(429, 'Too many requests. Try again later.');
        break;
      }
      return inner(req);
    };

/// Reads at most [max] bytes of the body; null when it is larger.
Future<List<int>?> readCapped(Request req, int max) async {
  final declared = req.contentLength;
  if (declared != null && declared > max) return null;
  final out = <int>[];
  await for (final chunk in req.read()) {
    out.addAll(chunk);
    if (out.length > max) return null;
  }
  return out;
}

/// Who may talk to this server from a browser, and under which Host names.
///
/// - Host: only loopback names and [publicHosts]. A DNS-rebinding page
///   (evil.example resolving to 127.0.0.1) arrives with its own Host and is
///   refused.
/// - Origin: a request a browser sends from a web page carries one; only
///   loopback pages (the doctor web app in development) and [allowedOrigins]
///   may call. Phones send no Origin and are unaffected.
class OriginPolicy {
  const OriginPolicy({this.publicHosts = const {}, this.allowedOrigins = const {}});
  final Set<String> publicHosts;
  final Set<String> allowedOrigins;

  static final _loopbackOrigin = RegExp(r'^http://(localhost|127\.0\.0\.1|\[::1\])(:\d{1,5})?$');
  static const _loopbackHosts = {'localhost', '127.0.0.1', '::1', '[::1]'};

  bool hostAllowed(String host) => _loopbackHosts.contains(host) || publicHosts.contains(host);
  bool originAllowed(String origin) => _loopbackOrigin.hasMatch(origin) || allowedOrigins.contains(origin);

  static const _allowHeaders = 'content-type, x-lt-expires, x-lt-withdraw-hash, x-lt-withdraw-token, x-lt-cert, x-lt-time, '
      'x-lt-sig, x-lt-nonce, x-lt-mailbox-secret, x-lt-admin, x-lt-verifier, x-lt-id-token, x-lt-session-secret';

  Middleware middleware() => (inner) => (req) async {
        if (!hostAllowed(req.requestedUri.host)) return _err(421, 'Unknown host.');
        final origin = req.headers['origin'];
        if (origin != null && !originAllowed(origin)) return _err(403, 'This origin may not call LifeTrack.');
        final cors = origin == null
            ? const <String, String>{}
            : {
                'access-control-allow-origin': origin,
                'access-control-allow-methods': 'GET, POST, PUT, DELETE, OPTIONS',
                'access-control-allow-headers': _allowHeaders,
                'vary': 'origin',
              };
        if (req.method == 'OPTIONS') return Response.ok('', headers: cors);
        final res = await inner(req);
        return cors.isEmpty ? res : res.change(headers: cors);
      };
}
