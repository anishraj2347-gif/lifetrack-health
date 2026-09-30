import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';

/// Where a doctor sends a prescription back: a reply mailbox only this phone
/// can open (its id is a hash of [secret]) and an X25519 key only this phone
/// holds. Included in every share so the doctor knows where to reply.
class ReplyIdentity {
  ReplyIdentity._(this.secret, this.mailbox, this.keyPair, this.publicKey);

  final String secret;
  final String mailbox;
  final SimpleKeyPair keyPair;
  final List<int> publicKey;

  static Future<ReplyIdentity> create() async {
    final (secret, mailbox) = await RelayApi.newPatientMailbox();
    final kp = await X25519().newKeyPair();
    return ReplyIdentity._(secret, mailbox, kp, (await kp.extractPublicKey()).bytes);
  }

  Future<Map<String, Object?>> toJson() async => {
        'secret': secret,
        'mailbox': mailbox,
        'seed': base64Encode(await keyPair.extractPrivateKeyBytes()),
      };

  static Future<ReplyIdentity> fromJson(Map<String, Object?> j) async {
    final kp = await X25519().newKeyPairFromSeed(base64Decode(j['seed']! as String));
    return ReplyIdentity._(j['secret']! as String, j['mailbox']! as String, kp, (await kp.extractPublicKey()).bytes);
  }

  Map<String, Object?> get replyTo => {'mailbox': mailbox, 'key': base64Encode(publicKey)};
}
