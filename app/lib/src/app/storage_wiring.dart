import 'dart:io' show Directory;

import 'package:path_provider/path_provider.dart';

import '../storage/byte_store.dart';
import '../storage/file_byte_store.dart';

/// Application-support, not documents: on iOS the Files app exposes the
/// documents directory to the user and to other apps' document pickers.
///
/// Residual: application-support is included in iCloud device backups unless
/// excluded with `NSURLIsExcludedFromBackupKey`, which needs a platform
/// channel. What would be backed up is ciphertext under a Keychain key marked
/// this-device-only, so a restored copy on another device is unreadable.
/// Android is covered by `allowBackup=false`.
Future<ByteStore> openDeviceByteStore() async {
  final base = await getApplicationSupportDirectory();
  return FileByteStore(Directory('${base.path}/vault'));
}
