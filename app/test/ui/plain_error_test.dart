import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/ui/widgets/parts.dart';

void main() {
  test('network failures read as plain words, not exception names', () {
    const raw = 'ClientException with SocketException: Connection refused (OS Error: Connection refused, errno = 111), address = 127.0.0.1, port = 42502';
    expect(plainError(Exception(raw)), "LifeTrack's server could not be reached. Check the internet connection and try again.");
    expect(plainError(const FormatException('An ABHA number has 14 digits.')), 'An ABHA number has 14 digits.');
    expect(plainError(Exception('boom')), 'Something went wrong. Please try again.');
  });
}
