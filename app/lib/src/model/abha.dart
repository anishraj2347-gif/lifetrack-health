/// An Ayushman Bharat Health Account, as the patient typed it in.
///
/// LifeTrack cannot check it against ABDM until it is registered there, so
/// [verified] is false for every ABHA the app holds today and the UI says so.
/// Aadhaar is never asked for or stored: ABHA is created with Aadhaar on
/// ABDM's side, and only the ABHA reaches LifeTrack.
class Abha {
  const Abha({required this.number, this.address, this.verified = false, required this.addedAt});

  /// 14 digits, no separators.
  final String number;

  /// e.g. `anjali.sharma@abdm`. Optional.
  final String? address;
  final bool verified;
  final DateTime addedAt;

  /// Digits only if [input] is a plausible 14-digit ABHA number, else null.
  static String? parseNumber(String input) {
    final d = input.replaceAll(RegExp(r'[\s-]'), '');
    return RegExp(r'^\d{14}$').hasMatch(d) ? d : null;
  }

  /// Lower-cased address if [input] looks like `name@domain`, else null.
  static String? parseAddress(String input) {
    final a = input.trim().toLowerCase();
    return RegExp(r'^[a-z0-9][a-z0-9._]{2,31}@[a-z]{2,16}$').hasMatch(a) ? a : null;
  }

  /// `91-2345-6789-0123`.
  String get display => '${number.substring(0, 2)}-${number.substring(2, 6)}-${number.substring(6, 10)}-${number.substring(10)}';

  /// What the Emergency ID shows: enough to match a hospital's record, not
  /// enough to use.
  String get masked => 'XX-XXXX-XXXX-${number.substring(10)}';

  Map<String, Object?> toJson() => {'number': number, 'address': address, 'verified': verified, 'addedAt': addedAt.toIso8601String()};

  static Abha fromJson(Map<String, Object?> j) => Abha(
        number: j['number']! as String,
        address: j['address'] as String?,
        verified: (j['verified'] as bool?) ?? false,
        addedAt: DateTime.parse(j['addedAt']! as String),
      );
}
