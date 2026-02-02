import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

Uint8List randomBytes(int length) {
  final random = Random.secure();
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return bytes;
}

String base64UrlEncodeNoPad(Uint8List bytes) {
  final encoded = base64Url.encode(bytes);
  return encoded.replaceAll('=', '');
}

Uint8List base64UrlDecodeNoPad(String value) {
  final normalized = value.padRight((value.length + 3) ~/ 4 * 4, '=');
  return Uint8List.fromList(base64Url.decode(normalized));
}

String generateId([int length = 16]) {
  return base64UrlEncodeNoPad(randomBytes(length));
}
