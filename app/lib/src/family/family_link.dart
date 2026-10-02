import 'dart:convert';
import 'dart:math';

import 'package:cryptography/dart.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';

import '../audit/audit_log.dart';
import '../emergency/emergency_card.dart';
import '../model/health_record.dart';
import '../share/relay.dart';
import '../share/reply_identity.dart';
import '../storage/sealed_store.dart';

/// An invitation to link two adults who each keep their own records on
/// their own phones (flow P7/F2). Linking gives NEITHER side the other's
/// records — only what the invited person chooses to share: their
/// Emergency ID and/or their current medicines.
class FamilyInvite {
  const FamilyInvite({required this.id, required this.fromName, required this.mailbox, required this.key, required this.expiresAt});

  static const lifetime = Duration(days: 7);

  final String id;
  final String fromName;
  final String mailbox;
  final String key;
  final DateTime expiresAt;

  String encode() => 'LTF1.${base64Url.encode(utf8.encode(jsonEncode({'id': id, 'from': fromName, 'mb': mailbox, 'k': key, 'exp': expiresAt.toUtc().toIso8601String()})))}';

  static FamilyInvite decode(String code) {
    final c = code.trim();
    if (!c.startsWith('LTF1.')) throw const FormatException('This is not a LifeTrack family invite.');
    try {
      final j = (jsonDecode(utf8.decode(base64Url.decode(c.substring(5)))) as Map).cast<String, Object?>();
      return FamilyInvite(
        id: j['id']! as String,
        fromName: j['from']! as String,
        mailbox: j['mb']! as String,
        key: j['k']! as String,
        expiresAt: DateTime.parse(j['exp']! as String),
      );
    } on Object {
      throw const FormatException('This invite code is damaged. Ask for a new one.');
    }
  }
}

enum LinkSide { iInvited, iJoined }

/// A link to another adult, as this phone knows it.
class FamilyLink {
  const FamilyLink({
    required this.id,
    required this.side,
    required this.name,
    required this.theirMailbox,
    required this.theirKey,
    required this.linkedAt,
    this.iShareEmergency = false,
    this.iShareMedicines = false,
    this.theirEmergency,
    this.theirMedicines,
    this.theirUpdateAt,
    this.secret,
  });

  final String id;

  /// Made by the phone that accepted the invite and sent, sealed, only to
  /// the inviter's phone. Every later message on the link carries it, so a
  /// person who only saw the invite code (often sent over a chat app) cannot
  /// send updates or unlink in either name. Null on links made before
  /// 1.18.1: those accept no messages and must be linked again.
  final String? secret;

  bool get secured => secret != null;

  /// Eight characters both phones show for this link. If they match, each
  /// phone is linked to the other — not to someone who took the invite
  /// first.
  String? get safetyCode {
    final k = secret;
    if (k == null) return null;
    const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    final h = const DartSha256().hashSync(utf8.encode('lifetrack/family-link|$id|$k')).bytes;
    final c = [for (var i = 0; i < 8; i++) alphabet[h[i] % 32]].join();
    return '${c.substring(0, 4)} ${c.substring(4)}';
  }
  final LinkSide side;
  final String name;
  final String theirMailbox;
  final String theirKey;
  final DateTime linkedAt;

  /// What THIS phone's owner chose to share with them.
  final bool iShareEmergency;
  final bool iShareMedicines;

  /// What THEY chose to share with this phone's owner, as last received.
  final Map<String, Object?>? theirEmergency;
  final List<Object?>? theirMedicines;
  final DateTime? theirUpdateAt;

  FamilyLink withTheirs({Map<String, Object?>? emergency, List<Object?>? medicines, required DateTime at}) => FamilyLink(
        id: id,
        side: side,
        name: name,
        theirMailbox: theirMailbox,
        theirKey: theirKey,
        linkedAt: linkedAt,
        iShareEmergency: iShareEmergency,
        iShareMedicines: iShareMedicines,
        theirEmergency: emergency,
        theirMedicines: medicines,
        theirUpdateAt: at,
        secret: secret,
      );

  FamilyLink sharing({required bool emergency, required bool medicines}) =>
      FamilyLink.fromJson({...toJson(), 'shareEm': emergency, 'shareMed': medicines});

  Map<String, Object?> toJson() => {
        'id': id,
        'side': side.name,
        'name': name,
        'mb': theirMailbox,
        'k': theirKey,
        'at': linkedAt.toIso8601String(),
        'shareEm': iShareEmergency,
        'shareMed': iShareMedicines,
        'theirEm': theirEmergency,
        'theirMed': theirMedicines,
        'theirAt': theirUpdateAt?.toIso8601String(),
        'sec': secret,
      };

  static FamilyLink fromJson(Map<String, Object?> j) => FamilyLink(
        id: j['id']! as String,
        side: LinkSide.values.byName(j['side']! as String),
        name: j['name']! as String,
        theirMailbox: j['mb']! as String,
        theirKey: j['k']! as String,
        linkedAt: DateTime.parse(j['at']! as String),
        iShareEmergency: (j['shareEm'] as bool?) ?? false,
        iShareMedicines: (j['shareMed'] as bool?) ?? false,
        theirEmergency: (j['theirEm'] as Map?)?.cast(),
        theirMedicines: j['theirMed'] as List?,
        theirUpdateAt: j['theirAt'] == null ? null : DateTime.parse(j['theirAt']! as String),
        secret: j['sec'] as String?,
      );
}

class LinkRefused implements MessageRefused {
  const LinkRefused(this.message);
  final String message;
  @override
  String get reason => message;
  @override
  String toString() => 'LinkRefused: $message';
}

/// Invites, accepts, updates and unlinks — each a sealed message through the
/// relay to the other phone's reply mailbox. The relay sees only ciphertext.
class FamilyLinkService {
  FamilyLinkService({required this.sealed, required this.relay, required this.audit, required this.replyIdentity});

  static const _blob = 'family_links';
  static const _invitesBlob = 'family_invites';

  final SealedStore sealed;
  final RelayClient relay;
  final AuditLog audit;
  final Future<ReplyIdentity> Function(String patientId) replyIdentity;

  Future<List<FamilyLink>> links() async => [
        for (final e in ((await sealed.read(_blob) as List?) ?? const [])) FamilyLink.fromJson((e as Map).cast()),
      ];

  Future<void> _save(List<FamilyLink> all) => sealed.write(_blob, [for (final l in all) l.toJson()]);

  /// Makes an invite for [ownerId] to hand to another adult.
  Future<FamilyInvite> createInvite({required String ownerId, required String ownerName, required DateTime at}) async {
    final me = await replyIdentity(ownerId);
    final r = Random.secure();
    final invite = FamilyInvite(
      id: List.generate(8, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join(),
      fromName: ownerName,
      mailbox: me.mailbox,
      key: base64Encode(me.publicKey),
      expiresAt: at.add(FamilyInvite.lifetime),
    );
    final open = ((await sealed.read(_invitesBlob) as List?) ?? const []).cast<Object?>().toList()..add(invite.id);
    await sealed.write(_invitesBlob, open);
    return invite;
  }

  /// The invited adult accepts on THEIR phone, choosing what to share.
  Future<FamilyLink> accept({
    required String ownerId,
    required String ownerName,
    required String code,
    required bool shareEmergency,
    required bool shareMedicines,
    required EmergencyCard? emergency,
    required List<HealthRecord> activeMedicines,
    required DateTime at,
  }) async {
    final invite = FamilyInvite.decode(code);
    if (!at.isBefore(invite.expiresAt)) throw const LinkRefused('This invite has expired. Ask for a new one.');
    final me = await replyIdentity(ownerId);
    if (invite.mailbox == me.mailbox) throw const LinkRefused('This is your own invite.');
    final link = FamilyLink(
      id: invite.id,
      side: LinkSide.iJoined,
      name: invite.fromName,
      theirMailbox: invite.mailbox,
      theirKey: invite.key,
      linkedAt: at,
      iShareEmergency: shareEmergency,
      iShareMedicines: shareMedicines,
      secret: RelayApi.newToken(),
    );
    await _send(link, {
      'type': 'family_link_accept',
      'inviteId': invite.id,
      'name': ownerName,
      'replyTo': me.replyTo,
      ..._mine(link, emergency, activeMedicines),
    }, at);
    await _save([...(await links()).where((l) => l.id != link.id), link]);
    await audit.append(AuditEntry(at: at, actorId: 'patient:$ownerId', patientId: ownerId, action: AuditAction.grantIssued, tokenId: 'family-link-${link.id}', detail: 'Linked with ${invite.fromName}; shares ${_whatLine(link)}'));
    return link;
  }

  /// Re-sends what this phone shares — after the card or medicines change.
  Future<void> sendUpdate({required String ownerId, required FamilyLink link, required EmergencyCard? emergency, required List<HealthRecord> activeMedicines, required DateTime at}) =>
      _send(link, {'type': 'family_link_update', 'linkId': link.id, ..._mine(link, emergency, activeMedicines)}, at);

  /// Either side changes what it shares; the other phone replaces its copy,
  /// and deletes it when nothing is shared any more.
  Future<FamilyLink> changeSharing({
    required String ownerId,
    required FamilyLink link,
    required bool shareEmergency,
    required bool shareMedicines,
    required EmergencyCard? emergency,
    required List<HealthRecord> activeMedicines,
    required DateTime at,
  }) async {
    final next = link.sharing(emergency: shareEmergency, medicines: shareMedicines);
    await sendUpdate(ownerId: ownerId, link: next, emergency: emergency, activeMedicines: activeMedicines, at: at);
    await _save([for (final l in await links()) l.id == next.id ? next : l]);
    await audit.append(AuditEntry(at: at, actorId: 'patient:$ownerId', patientId: ownerId, action: AuditAction.edit, tokenId: 'family-link-${link.id}', detail: 'Now sharing ${_whatLine(next)} with ${link.name}'));
    return next;
  }

  /// Either side can unlink. The other phone deletes what it held.
  Future<void> unlink({required String ownerId, required FamilyLink link, required DateTime at}) async {
    try {
      // A link from an older version has no secret to prove the message
      // with; it is removed here only.
      if (link.secured) await _send(link, {'type': 'family_unlink', 'linkId': link.id}, at);
    } finally {
      await _save([...(await links()).where((l) => l.id != link.id)]);
      await audit.append(AuditEntry(at: at, actorId: 'patient:$ownerId', patientId: ownerId, action: AuditAction.grantRevoked, tokenId: 'family-link-${link.id}', detail: 'Unlinked from ${link.name}'));
    }
  }

  /// Inbox handlers, for `ClinicalShareService.collectInbox`.
  Map<String, Future<void> Function(Map<String, Object?>)> handlers({required String ownerId, required DateTime at}) => {
        'family_link_accept': (p) async {
          final open = ((await sealed.read(_invitesBlob) as List?) ?? const []).cast<String>().toList();
          final inviteId = p['inviteId']! as String;
          if (!open.contains(inviteId)) throw const LinkRefused('an invite this phone did not make, or already used');
          final reply = (p['replyTo']! as Map).cast<String, Object?>();
          final secret = p['linkSecret'];
          if (secret is! String || secret.length < 16 || secret.length > 100) throw const LinkRefused('an invite answer without its link secret');
          final mailbox = reply['mailbox']! as String;
          final key = reply['key']! as String;
          if (!RegExp(r'^p-[0-9a-f]{64}$').hasMatch(mailbox) || base64Decode(key).length != 32) throw const LinkRefused('an invite answer with a bad address');
          final link = FamilyLink(
            id: inviteId,
            side: LinkSide.iInvited,
            name: _text(p['name'], max: 80) ?? 'Family member',
            theirMailbox: mailbox,
            theirKey: key,
            linkedAt: at,
            secret: secret,
          ).withTheirs(emergency: _emergency(p['emergency']), medicines: _medicines(p['medicines']), at: at);
          await _save([...(await links()).where((l) => l.id != inviteId), link]);
          await sealed.write(_invitesBlob, open..remove(inviteId));
          await audit.append(AuditEntry(at: at, actorId: 'family:${link.name}', patientId: ownerId, action: AuditAction.edit, tokenId: 'family-link-$inviteId', detail: '${link.name} accepted your family invite'));
        },
        'family_link_update': (p) async {
          final all = await links();
          final i = all.indexWhere((l) => l.id == p['linkId']);
          if (i < 0) throw const LinkRefused('an update for a link that no longer exists');
          _proven(all[i], p);
          all[i] = all[i].withTheirs(emergency: _emergency(p['emergency']), medicines: _medicines(p['medicines']), at: at);
          await _save(all);
        },
        'family_unlink': (p) async {
          final all = await links();
          final gone = all.where((l) => l.id == p['linkId']).toList();
          if (gone.isEmpty) throw const LinkRefused('an unlink for a link that no longer exists');
          _proven(gone.single, p);
          await _save([...all.where((l) => l.id != p['linkId'])]);
          for (final l in gone) {
            await audit.append(AuditEntry(at: at, actorId: 'family:${l.name}', patientId: ownerId, action: AuditAction.grantRevoked, tokenId: 'family-link-${l.id}', detail: '${l.name} unlinked; what they shared was deleted'));
          }
        },
      };

  /// Refuses a message that does not carry this link's secret.
  static void _proven(FamilyLink link, Map<String, Object?> p) {
    final mine = link.secret;
    final given = p['linkSecret'];
    if (mine == null) throw const LinkRefused('a message for a link made by an older version — unlink and link again');
    if (given is! String || !_sameText(given, mine)) throw const LinkRefused('a message that did not come from the linked phone');
  }

  static bool _sameText(String a, String b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return d == 0;
  }

  static String? _text(Object? v, {int max = 200}) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : (t.length > max ? t.substring(0, max) : t);
  }

  /// Only the Emergency ID's own fixed fields, each bounded (#7).
  static Map<String, Object?>? _emergency(Object? v) {
    if (v is! Map) return null;
    final j = v.cast<String, Object?>();
    String f(String k) => _text(j[k], max: EmergencyCard.maxFieldLength) ?? '';
    final card = EmergencyCard(
      bloodType: EmergencyCard.bloodTypes.contains(j['blood']) ? j['blood']! as String : '',
      allergies: f('allergies'),
      conditions: f('conditions'),
      medications: f('meds'),
      contactName: f('contactName'),
      contactRelation: f('contactRelation'),
      contactPhone: RegExp(r'^\+?[0-9 ]{0,20}$').hasMatch(f('contactPhone')) ? f('contactPhone') : '',
    );
    return card.toJson();
  }

  /// Medicine names and doses only, at most 50.
  static List<Object?>? _medicines(Object? v) {
    if (v is! List) return null;
    return [
      for (final m in v.take(50))
        if (m is Map && _text(m['title']) != null) {'title': _text(m['title']), 'dose': _text(m['dose'], max: 60), 'endsOn': DateTime.tryParse('${m['endsOn']}')?.toIso8601String()},
    ];
  }

  Map<String, Object?> _mine(FamilyLink link, EmergencyCard? emergency, List<HealthRecord> meds) => {
        'emergency': link.iShareEmergency && emergency != null ? emergency.toJson() : null,
        'medicines': link.iShareMedicines ? [for (final m in meds) {'title': m.title, 'dose': m.dose?.display, 'endsOn': m.endDate?.toIso8601String()}] : null,
      };

  Future<void> _send(FamilyLink link, Map<String, Object?> payload, DateTime at) async {
    final secret = link.secret;
    if (secret == null) throw const LinkRefused('This link was made by an older version. Unlink, then link again.');
    payload = {...payload, 'linkSecret': secret};
    final key = base64Decode(link.theirKey);
    final exp = at.add(const Duration(hours: 47));
    // Unique per message: two sends in the same instant must not overwrite
    // each other at the relay.
    final r = Random.secure();
    final grant = 'family-${link.id}-${List.generate(8, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    await relay.deposit(
      mailbox: link.theirMailbox,
      grantId: grant,
      envelope: await ShareEnvelope.seal(bundle: payload, recipientKey: key, keyId: await RelayApi.keyId(key), grantId: grant, expiresAt: exp),
      expiresAt: exp,
    );
  }

  static String _whatLine(FamilyLink l) => [
        if (l.iShareEmergency) 'Emergency ID',
        if (l.iShareMedicines) 'medicines',
        if (!l.iShareEmergency && !l.iShareMedicines) 'nothing',
      ].join(' and ');
}
