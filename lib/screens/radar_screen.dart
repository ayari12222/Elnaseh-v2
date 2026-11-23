import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// ============================================================
// مساعد التشفير  ✅ AES-GCM مصادَق + PBKDF2
// ============================================================
class CryptoHelper {
  static const int _iterations = 20000;
  static const int _keyLength = 32;

  static enc.Key _deriveKey(String passphrase) {
    final salt = utf8.encode('Elnaseh_v2_salt_#fixed#');
    final hmac = crypto.Hmac(crypto.sha256, utf8.encode(passphrase));
    final block = Uint8List.fromList([...salt, 0, 0, 0, 1]);

    var u = Uint8List.fromList(hmac.convert(block).bytes);
    final t = Uint8List.fromList(u);
    for (var i = 1; i < _iterations; i++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var k = 0; k < t.length; k++) {
        t[k] ^= u[k];
      }
    }
    return enc.Key(t.sublist(0, _keyLength));
  }

  /// يشفّر ويعيد base64(iv12 + ciphertext + tag16).
  static String encrypt(String plain, String rawKey) {
    final key = _deriveKey(rawKey);
    final iv = enc.IV.fromSecureRandom(12);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    final encrypted = encrypter.encrypt(plain, iv: iv);
    return base64Encode(iv.bytes + encrypted.bytes);
  }

  /// يفك التشفير مع التحقق من السلامة. يعيد null عند فشل.
  static String? decrypt(String encoded, String rawKey) {
    try {
      final all = base64Decode(encoded);
      if (all.length < 12 + 16) return null;
      final iv = enc.IV(Uint8List.fromList(all.sublist(0, 12)));
      final cipherText = enc.Encrypted(Uint8List.fromList(all.sublist(12)));
      final encrypter =
          enc.Encrypter(enc.AES(_deriveKey(rawKey), mode: enc.AESMode.gcm));
      return encrypter.decrypt(cipherText, iv: iv);
    } catch (_) {
      return null;
    }
  }
}

// ============================================================
// نموذج الرسالة ✅ حقول واضحة + isTest
// ============================================================
class SosMessage {
  final String id;
  final String sender;
  final int ttl;
  final String content;
  final int timestampMs; // createdAt الأصلي (لا يتغير في Relay)
  final String type;
  final String? ackFor;
  final double? lat;
  final double? lng;
  final bool isTest;

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
    this.isTest = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        's': sender,
        'ttl': ttl,
        'c': content,
        't': timestampMs,
        'ty': type,
        if (ackFor != null) 'af': ackFor,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (isTest) 'tx': true,
      };

  factory SosMessage.fromJson(Map<String, dynamic> j) => SosMessage(
        id: j['id'] as String,
        sender: j['s'] as String,
        ttl: j['ttl'] as int,
        content: j['c'] as String,
        timestampMs: j['t'] as int,
        type: j['ty'] as String,
        ackFor: j['af'] as String?,
        lat: j['lat'] != null ? (j['lat'] as num).toDouble() : null,
        lng: j['lng'] != null ? (j['lng'] as num).toDouble() : null,
        isTest: j['tx'] == true,
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

// ============================================================
// شاشة الرادار — نفس الواجهة القديمة + إصلاحات الشبكة
// ============================================================
class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key});

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen>
    with TickerProviderStateMixin {
  late AnimationController _sweepController;
  late AnimationController _pulseController;

  final List<Map<String, dynamic>> _targets = [];
  bool _isScanning = false;
  bool _isAdvertising = false;
  bool _isSosSending = false;

  // ✅ FIFO لحماية منع التكرار (بدل clear الكامل)
  final LinkedHashSet<String> _processedMessageIds = LinkedHashSet<String>();
  static const int _maxProcessedIds = 2000;
  final List<SosMessage> _messageLog = [];

  Timer? _discoveryTimer;
  Timer? _stopDiscoveryTimer;

  String _userName = "مستخدم";
  String get _advertiseName {
    // ✅ حد أقصى آمن للاسم
    final raw = "Elnaseh_$_userName";
    return raw.length <= 40 ? raw : raw.substring(0, 40);
  }

  // ✅ مفتاح يُولَّد عشوائياً عند أول تشغيل ويُخزن في Secure Storage
  String _sharedKey = "";
  static const _secureStorage = FlutterSecureStorage();

  final Strategy strategy = Strategy.P2P_CLUSTER;
  final String serviceId = "com.elnaseh.app";

  // ✅ حالة الاتصال الفعلية (منفصلة عن رادار العرض)
  final Set<String> _linkedEndpoints = {};

  static const double _targetRadius = 180.0;
  static const int _maxTargets = 20;

  int _maxTtl = 5;
  static const Map<String, int> _ttlOptions = {
    'قريب (3)': 3,
    'متوازن (5)': 5,
    'بعيد (10)': 10,
    'طوارئ قصوى (15)': 15,
  };

  static const Duration _ackTimeout = Duration(seconds: 6);
  String? _activeSosId;
  final Set<String> _ackedNames = {};

  final AudioPlayer _audioPlayer = AudioPlayer();

  // ============================================================
  // دورة الحياة
  // ============================================================
  @override
  void initState() {
    super.initState();
    _sweepController = AnimationController(
        vsync: this, duration: const Duration(seconds: 4))
      ..repeat();
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadPrefs();
    if (!mounted) return;
    await _initNearby();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    String? key = await _secureStorage.read(key: 'sharedKey');

    // ✅ توليد مفتاح عشوائي قوي عند أول تشغيل
    if (key == null || key.length < 32) {
      final rnd = Random.secure();
      key = List<int>.generate(32, (_) => rnd.nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      await _secureStorage.write(key: 'sharedKey', value: key);
    }

    if (!mounted) return;
    setState(() {
      _userName = prefs.getString('userName') ?? "مستخدم";
      _maxTtl = prefs.getInt('maxTtl') ?? 5;
      _sharedKey = key!;
    });
  }

  Future<void> _initNearby() async {
    final statuses = await [
      Permission.location,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
    ].request();

    final locationOk = statuses[Permission.location]?.isGranted ?? false;
    final btOk = statuses[Permission.bluetoothScan]?.isGranted ?? false;

    if (!locationOk || !btOk) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('يجب منح أذونات الموقع والبلوتوث'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ يرجى تشغيل خدمة الموقع (GPS) من إعدادات الهاتف!'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 10),
          ),
        );
      }
      return;
    }

    await _startAdvertising();
    _startDiscoveryWithTimer();
  }

  // ============================================================
  // الشبكة — Advertising
  // ============================================================
  Future<void> _startAdvertising() async {
    if (_isAdvertising) return;
    try {
      await Nearby().startAdvertising(
        _advertiseName,
        strategy,
        serviceId: serviceId,
        onConnectionInitiated: (id, info) async {
          await Nearby().acceptConnection(
            id,
            onPayLoadRecieved: (endpointId, payload) {
              if (payload.type == PayloadType.BYTES && payload.bytes != null) {
                _onPayloadReceived(endpointId, payload.bytes!);
              }
            },
            onPayloadTransferUpdate: (endpointId, update) {},
          );
        },
        onConnectionResult: (id, status) {
          if (status == Status.CONNECTED) {
            _linkedEndpoints.add(id);
            _refreshTargetColor(id, Colors.cyanAccent);
          }
        },
        onDisconnected: (id) {
          // ✅ تنظيف حالة الاتصال عند الانفصال
          _linkedEndpoints.remove(id);
          if (mounted) {
            setState(() => _targets.removeWhere((t) => t['id'] == id));
          }
        },
      );
      if (mounted) setState(() => _isAdvertising = true);
    } catch (e) {
      debugPrint("❌ فشل الإعلان: $e");
    }
  }

  // ============================================================
  // الشبكة — Discovery
  // ============================================================
  void _startDiscoveryWithTimer() {
    _startDiscovery();
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(
      const Duration(seconds: 60), // ✅ 60 بدل 35 لتقليل استهلاك البطارية
      (_) => _startDiscovery(),
    );
  }

  Future<void> _startDiscovery() async {
    if (!mounted) return;
    try {
      await Nearby().stopDiscovery().catchError((_) {});
      if (mounted) setState(() => _isScanning = true);

      await Nearby().startDiscovery(
        _userName,
        strategy,
        serviceId: serviceId,
        onEndpointFound: (id, name, svcId) async {
          if (svcId != serviceId) return;

          if (!_targets.any((t) => t['id'] == id)) {
            setState(() {
              if (_targets.length >= _maxTargets) _targets.removeAt(0);
              final angle = (_targets.length * (2 * pi / 8)) - (pi / 2);
              _targets.add({
                'id': id,
                'name': name.replaceFirst("Elnaseh_", ""),
                'angle': angle + Random().nextDouble() * 0.15,
                'radius': _targetRadius,
                'color': Colors.amberAccent, // غير متصل بعد
              });
            });
          }

          // ✅ الاتصال الفعلي — إصلاح جوهري
          await _ensureConnected(id);
        },
        onEndpointLost: (id) {
          _linkedEndpoints.remove(id);
          if (mounted) {
            setState(() => _targets.removeWhere((t) => t['id'] == id));
          }
        },
      );

      _stopDiscoveryTimer?.cancel();
      _stopDiscoveryTimer = Timer(const Duration(seconds: 30), () async {
        await Nearby().stopDiscovery().catchError((_) {});
        if (mounted) setState(() => _isScanning = false);
      });
    } catch (e) {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  /// ✅ الاتصال الفعلي بجهاز مكتشف (كان مفقوداً تماماً)
  Future<void> _ensureConnected(String endpointId) async {
    if (_linkedEndpoints.contains(endpointId)) return;
    try {
      await Nearby().connect(
        endpointId,
        onConnectionInitiated: (id, info) async {
          await Nearby().acceptConnection(
            id,
            onPayLoadRecieved: (epid, payload) {
              if (payload.type == PayloadType.BYTES && payload.bytes != null) {
                _onPayloadReceived(epid, payload.bytes!);
              }
            },
            onPayloadTransferUpdate: (endpointId, update) {},
          );
        },
        onConnectionResult: (id, status) {
          if (status == Status.CONNECTED) {
            _linkedEndpoints.add(id);
            _refreshTargetColor(id, Colors.cyanAccent);
          }
        },
        onDisconnected: (id) {
          _linkedEndpoints.remove(id);
          if (mounted) {
            setState(() => _targets.removeWhere((t) => t['id'] == id));
          }
        },
      );
    } catch (e) {
      debugPrint("❌ الاتصال بـ $endpointId فشل: $e");
    }
  }

  void _refreshTargetColor(String endpointId, Color color) {
    if (!mounted) return;
    setState(() {
      for (final t in _targets) {
        if (t['id'] == endpointId) t['color'] = color;
      }
    });
  }

  // ============================================================
  // الإرسال مع Retry
  // ============================================================
  Future<bool> _sendWithRetry(String endpointId, Uint8List data) async {
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        if (!_linkedEndpoints.contains(endpointId)) {
          await _ensureConnected(endpointId);
          await Future.delayed(const Duration(milliseconds: 400));
        }
        await Nearby().sendBytesPayload(endpointId, data);
        return true;
      } catch (_) {
        // ✅ Exponential backoff
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      }
    }
    return false;
  }

  // ============================================================
  // إرسال SOS
  // ============================================================
  Future<void> _sendSosBroadcast() async {
    // ✅ قفل الزر بشرط _activeSosId أيضاً
    if (_isSosSending || _activeSosId != null) return;

    if (_targets.isEmpty) {
      _snack('لا توجد أجهزة قريبة (جرب زر الاختبار ✨)', Colors.orange);
      return;
    }

    final customMessage = await _askForMessage();
    if (customMessage == null || customMessage.trim().isEmpty) return;
    if (!mounted) return; // ✅ فحص mounted بعد await

    setState(() {
      _isSosSending = true;
      _ackedNames.clear();
    });
    HapticFeedback.heavyImpact();

    try {
      final pos = await _getCurrentLocation();
      if (!mounted) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      final messageId = '${now}_${Random().nextInt(9999)}';

      final sos = SosMessage(
        id: messageId,
        sender: _userName,
        ttl: _maxTtl,
        content: customMessage.trim(),
        timestampMs: now,
        type: 'SOS',
        lat: pos?.latitude,
        lng: pos?.longitude,
      );

      _markProcessed(messageId);
      _activeSosId = messageId;

      final targetsCopy = List<Map<String, dynamic>>.from(_targets);
      final data = Uint8List.fromList(utf8.encode(sos.encode(_sharedKey)));

      final results = await Future.wait(
        targetsCopy.map((t) => _sendWithRetry(t['id'] as String, data)),
      );
      final sentCount = results.where((ok) => ok).length;

      await Future.delayed(_ackTimeout);
      if (!mounted) return;

      final ackedCount = _ackedNames.length;
      _snack(
        ackedCount == 0
            ? 'تم الإرسال لـ $sentCount جهاز — ⚠️ لم يصل التأكيد'
            : '✅ وصل التأكيد من $ackedCount أجهزة',
        ackedCount == 0 ? Colors.red : Colors.green,
      );
    } finally {
      if (mounted) setState(() => _isSosSending = false);
      _activeSosId = null; // ✅ تصفير مضمون حتى عند الاستثناء
    }
  }

  Future<Position?> _getCurrentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
    } catch (_) {
      return await Geolocator.getLastKnownPosition();
    }
  }

  Future<String?> _askForMessage() {
    final ctrl = TextEditingController(); // ✅ controller مُدار
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('إرسال نداء استغاثة',
            style: TextStyle(color: Colors.cyanAccent)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          maxLength: 200,
          decoration: const InputDecoration(
            hintText: 'اكتب رسالتك هنا...',
            hintStyle: TextStyle(color: Colors.grey),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, ctrl.text),
            child:
                const Text('إرسال', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ).whenComplete(ctrl.dispose);
  }

  // ============================================================
  // استقبال الرسائل
  // ============================================================
  void _onPayloadReceived(String fromEndpointId, Uint8List bytes) {
    final raw = utf8.decode(bytes, allowMalformed: true);
    final msg = SosMessage.tryDecode(raw, _sharedKey);
    if (msg == null || msg.isExpired) return;
    if (_processedMessageIds.contains(msg.id)) return;

    if (msg.type == 'ACK') {
      _markProcessed(msg.id);
      if (_activeSosId != null && msg.ackFor == _activeSosId) {
        setState(() => _ackedNames.add(msg.sender));
      }
      return;
    }

    _handleIncomingSos(msg, fromEndpointId);
  }

  void _handleIncomingSos(SosMessage msg, String fromEndpointId) {
    _markProcessed(msg.id);
    _messageLog.add(msg);

    // ✅ ACK فوري (لا ننتظر التأخير)
    _sendAck(msg.id, fromEndpointId);

    if (mounted) {
      _alertSosReceived();
      _showSosReceived(msg);
    }

    // ✅ Relay مع استبعاد المُرسل (إصلاح الإرسال المزدوج)
    if (msg.ttl > 1) {
      final relay = SosMessage(
        id: msg.id,
        sender: msg.sender,
        ttl: msg.ttl - 1,
        content: msg.content,
        timestampMs: msg.timestampMs, // نفس الطابع الأصلي
        type: 'SOS',
        lat: msg.lat,
        lng: msg.lng,
      );
      _relayMessage(relay, excludeEndpointId: fromEndpointId);
    }
  }

  Future<void> _sendAck(String forMessageId, String toEndpointId) async {
    final ack = SosMessage(
      id: 'ack_${DateTime.now().millisecondsSinceEpoch}_${forMessageId.hashCode}',
      sender: _userName,
      ttl: 1,
      content: '',
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      type: 'ACK',
      ackFor: forMessageId,
    );
    _markProcessed(ack.id);
    await _sendWithRetry(
      toEndpointId,
      Uint8List.fromList(utf8.encode(ack.encode(_sharedKey))),
    );
  }

  Future<void> _relayMessage(SosMessage msg,
      {String? excludeEndpointId}) async {
    final data = Uint8List.fromList(utf8.encode(msg.encode(_sharedKey)));
    final targets = List<Map<String, dynamic>>.from(_targets)
        .where((t) => t['id'] != excludeEndpointId)
        .toList();
    await Future.wait(
      targets.map((t) => _sendWithRetry(t['id'] as String, data)),
    );
  }

  // ✅ FIFO بدل clear الكامل
  void _markProcessed(String id) {
    _processedMessageIds.add(id);
    while (_processedMessageIds.length > _maxProcessedIds) {
      _processedMessageIds.remove(_processedMessageIds.first);
    }
  }

  // ============================================================
  // تنبيهات
  // ============================================================
  Future<void> _alertSosReceived() async {
    HapticFeedback.vibrate();
    HapticFeedback.heavyImpact();
    try {
      await _audioPlayer.play(AssetSource('war-alarm-sound-long.mp3'));
    } catch (e) {
      debugPrint("❌ خطأ في تشغيل الصوت: $e");
      SystemSound.play(SystemSoundType.alert);
    }
    Future.delayed(const Duration(milliseconds: 400), HapticFeedback.vibrate);
    Future.delayed(const Duration(milliseconds: 800), HapticFeedback.vibrate);
  }

  // ============================================================
  // واجهات الحوارات (نفس التصميم القديم)
  // ============================================================
  void _snack(String text, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text), backgroundColor: color));
  }

  void _showSosReceived(SosMessage msg) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('🚨 استغاثة من ${msg.sender}',
            style: const TextStyle(color: Colors.redAccent)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(msg.content,
                style: const TextStyle(color: Colors.white, fontSize: 16)),
            if (msg.lat != null && msg.lng != null)
              const Text('📍 الموقع الجغرافي متوفر',
                  style:
                      TextStyle(color: Colors.cyanAccent, fontSize: 12)),
          ],
        ),
        actions: [
          if (msg.lat != null && msg.lng != null)
            TextButton.icon(
              icon: const Icon(Icons.map, color: Colors.greenAccent),
              label: const Text('عرض على الخريطة',
                  style: TextStyle(color: Colors.greenAccent)),
              onPressed: () => _openMap(msg.lat!, msg.lng!),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسناً',
                style: TextStyle(color: Colors.cyanAccent)),
          ),
        ],
      ),
    );
  }

  Future<void> _openMap(double lat, double lng) async {
    final url =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      _snack('فشل فتح الخريطة: $e', Colors.red);
    }
  }

  Future<void> _testIncomingSos() async {
    final msg = SosMessage(
      id: 'test_${DateTime.now().millisecondsSinceEpoch}',
      sender: "جهاز تجريبي",
      ttl: 1,
      content: "هذه رسالة اختبار! تأكد من الصوت والاهتزاز والخريطة.",
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      type: 'SOS',
      lat: 24.7136,
      lng: 46.6753,
      isTest: true, // ✅ لا تُخلط مع السجل الحقيقي بصرياً
    );
    _handleIncomingSos(msg, "dummy_endpoint");
  }

  void _showLog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('📜 سجل الرسائل',
              style: TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          const Divider(color: Colors.grey),
          if (_messageLog.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('لا توجد رسائل بعد',
                  style: TextStyle(color: Colors.grey)),
            )
          else
            ..._messageLog.reversed.map((m) {
              return ListTile(
                leading: Icon(m.isTest ? Icons.science : Icons.warning,
                    color: Colors.redAccent),
                title: Text('من: ${m.sender}',
                    style: const TextStyle(color: Colors.cyanAccent)),
                subtitle: Text(m.content,
                    style: const TextStyle(color: Colors.white70)),
                trailing: (m.lat != null && m.lng != null)
                    ? IconButton(
                        icon: const Icon(Icons.map,
                            color: Colors.greenAccent),
                        onPressed: () => _openMap(m.lat!, m.lng!),
                      )
                    : null,
              );
            }),
        ],
      ),
    );
  }

  Future<void> _showTtlSelector() async {
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('مدى انتشار الاستغاثة',
            style: TextStyle(color: Colors.cyanAccent)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _ttlOptions.entries.map((entry) {
            return ListTile(
              leading: Icon(
                entry.value == _maxTtl
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: entry.value == _maxTtl
                    ? Colors.cyanAccent
                    : Colors.grey,
              ),
              title: Text(entry.key,
                  style: TextStyle(
                      color: entry.value == _maxTtl
                          ? Colors.cyanAccent
                          : Colors.white)),
              onTap: () => Navigator.pop(context, entry.value),
            );
          }).toList(),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _maxTtl = selected);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('maxTtl', selected);
    }
  }

  Future<void> _showKeySettings() async {
    final ctrl = TextEditingController(text: _sharedKey);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('🔑 مفتاح التشفير',
            style: TextStyle(color: Colors.cyanAccent)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              style: const TextStyle(color: Colors.white),
              maxLength: 64,
              decoration: const InputDecoration(
                hintText: '32 حرفاً على الأقل',
                hintStyle: TextStyle(color: Colors.grey),
              ),
            ),
            const Text(
              '⚠️ يجب أن يطابق المفتاح على كل الأجهزة',
              style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent),
            onPressed: () => Navigator.pop(context, ctrl.text),
            child:
                const Text('حفظ', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
    ctrl.dispose();

    if (result == null || !mounted) return;
    final trimmed = result.trim();
    if (trimmed.length < 32) {
      _snack('المفتاح يجب أن يكون 32 حرفاً على الأقل', Colors.red);
      return;
    }
    await _secureStorage.write(key: 'sharedKey', value: trimmed);
    if (!mounted) return;
    setState(() => _sharedKey = trimmed);
    _snack('تم الحفظ. أعد تشغيل التطبيق لتطبيقه على الأجهزة الأخرى.',
        Colors.green);
  }

  // ============================================================
  // dispose
  // ============================================================
  @override
  void dispose() {
    _discoveryTimer?.cancel();
    _stopDiscoveryTimer?.cancel();
    _audioPlayer.dispose();
    Nearby().stopAdvertising().catchError((_) {});
    Nearby().stopDiscovery().catchError((_) {});
    Nearby().stopAllEndpoints().catchError((_) {});
    _sweepController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // ============================================================
  // الواجهة (نفس التصميم القديم حرفياً)
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shield_moon,
                color: Colors.cyanAccent, size: 28),
            const SizedBox(width: 10),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Colors.cyanAccent, Colors.white, Colors.cyanAccent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: const Text(
                'الناصح',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2),
              ),
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.cyanAccent),
        actions: [
          IconButton(
              icon: const Icon(Icons.auto_awesome,
                  color: Colors.amberAccent),
              tooltip: 'اختبار',
              onPressed: _testIncomingSos),
          IconButton(
              icon: const Icon(Icons.vpn_key),
              onPressed: _showKeySettings),
          IconButton(
              icon: const Icon(Icons.history), onPressed: _showLog),
          IconButton(
              icon: const Icon(Icons.tune), onPressed: _showTtlSelector),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = min(constraints.maxWidth, constraints.maxHeight - 120);
          final center = size / 2;
          final radius = size * 0.36;

          return Stack(
            children: [
              Center(
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ...List.generate(
                        4,
                        (i) => AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) => Container(
                            width: (size / 4) * (i + 1),
                            height: (size / 4) *
