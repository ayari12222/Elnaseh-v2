import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;

class CryptoHelper {
  static enc.Key _keyFrom(String raw) {
    final bytes = utf8.encode(raw.padRight(32, '0').substring(0, 32));
    return enc.Key(Uint8List.fromList(bytes));
  }

  static String encrypt(String plain, String rawKey) {
    final key = _keyFrom(rawKey);
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    return base64Encode(iv.bytes + encrypter.encrypt(plain, iv: iv).bytes);
  }

  static String? decrypt(String encoded, String rawKey) {
    try {
      final all = base64Decode(encoded);
      if (all.length < 16) return null;
      final iv = enc.IV(Uint8List.fromList(all.sublist(0, 16)));
      final cipherText = enc.Encrypted(Uint8List.fromList(all.sublist(16)));
      final encrypter =
          enc.Encrypter(enc.AES(_keyFrom(rawKey), mode: enc.AESMode.cbc));
      return encrypter.decrypt(cipherText, iv: iv);
    } catch (_) {
      return null;
    }
  }

  static String generateRandomKey() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    return base64Url.encode(bytes).substring(0, 32);
  }
}

class SosMessage {
  final String id;
  final String sender;
  final int ttl;
  final String content;
  final int timestampMs;
  final String type;
  final String? ackFor;
  final double? lat;
  final double? lng;

  SosMessage({
    required this.id,
    required this.sender,
    required this.ttl,
    required this.content,
    required this.timestampMs,
    required this.type,
    this.ackFor,
    this.lat,
    this.lng,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'sender': sender,
        'ttl': ttl,
        'content': content,
        'timestampMs': timestampMs,
        'type': type,
        if (ackFor != null) 'ackFor': ackFor,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      };

  factory SosMessage.fromJson(Map<String, dynamic> j) => SosMessage(
        id: j['id'] as String,
        sender: j['sender'] as String,
        ttl: j['ttl'] as int,
        content: j['content'] as String,
        timestampMs: j['timestampMs'] as int,
        type: j['type'] as String,
        ackFor: j['ackFor'] as String?,
        lat: j['lat'] != null ? (j['lat'] as num).toDouble() : null,
        lng: j['lng'] != null ? (j['lng'] as num).toDouble() : null,
      );

  String encode(String key) => CryptoHelper.encrypt(jsonEncode(toJson()), key);

  static SosMessage? tryDecode(String s, String key) {
    try {
      final plain = CryptoHelper.decrypt(s, key);
      if (plain == null) return null;
      return SosMessage.fromJson(jsonDecode(plain) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  bool isExpired({Duration maxAge = const Duration(minutes: 30)}) {
    return DateTime.now()
            .difference(DateTime.fromMillisecondsSinceEpoch(timestampMs)) >
        maxAge;
  }
}
