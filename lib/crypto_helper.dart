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
      final encrypter = enc.Encrypter(enc.AES(_keyFrom(rawKey), mode: enc.AESMode.cbc));
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

class MeshPacket {
  final String messageId;
  final String senderId;
  final String senderName;
  final String targetId; // معرف الجهاز المستهدف، أو "ALL" للبث
  final int ttl;
  final String type; // SOS, ACK, CHAT
  final int timestampMs;
  final String encryptedPayload; // المحتوى المشفر
  final double? lat;
  final double? lng;

  MeshPacket({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.targetId,
    required this.ttl,
    required this.type,
    required this.timestampMs,
    required this.encryptedPayload,
    this.lat,
    this.lng,
  });

  Map<String, dynamic> toJson() => {
        'id': messageId,
        'sid': senderId,
        'sn': senderName,
        'tid': targetId,
        'ttl': ttl,
        'ty': type,
        't': timestampMs,
        'p': encryptedPayload,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      };

  factory MeshPacket.fromJson(Map<String, dynamic> j) => MeshPacket(
        messageId: j['id'],
        senderId: j['sid'],
        senderName: j['sn'],
        targetId: j['tid'],
        ttl: j['ttl'],
        type: j['ty'],
        timestampMs: j['t'],
        encryptedPayload: j['p'],
        lat: j['lat'] != null ? (j['lat'] as num).toDouble() : null,
        lng: j['lng'] != null ? (j['lng'] as num).toDouble() : null,
      );

  String encodePacket() => base64Encode(utf8.encode(jsonEncode(toJson())));

  static MeshPacket? tryDecodePacket(String s) {
    try {
      return MeshPacket.fromJson(jsonDecode(utf8.decode(base64Decode(s))));
    } catch (_) {
      return null;
    }
  }

  bool isExpired({Duration maxAge = const Duration(minutes: 30)}) {
    return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(timestampMs)) > maxAge;
  }
}
