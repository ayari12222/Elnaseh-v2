import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:path/path.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

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
        's': sender,
        'ttl': ttl,
        'c': content,
        't': timestampMs,
        'ty': type,
        if (ackFor != null) 'af': ackFor,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
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

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _db;
  DatabaseHelper._internal();

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'elnaseh.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            sender TEXT NOT NULL,
            content TEXT NOT NULL,
            ttl INTEGER NOT NULL,
            lat REAL,
            lng REAL,
            timestampMs INTEGER NOT NULL,
            type TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE delivery (
            messageId TEXT NOT NULL,
            endpointId TEXT NOT NULL,
            PRIMARY KEY (messageId, endpointId)
          )
        ''');
      },
    );
  }

  Future<void> saveMessage(Map<String, dynamic> message) async {
    final db = await database;
    await db.insert('messages', message,
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> markAsSent(String messageId, String endpointId) async {
    final db = await database;
    await db.insert(
      'delivery',
      {'messageId': messageId, 'endpointId': endpointId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<Map<String, dynamic>>> getUnsentMessages(
      String endpointId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT m.* FROM messages m
      WHERE m.id NOT IN (
        SELECT messageId FROM delivery WHERE endpointId = ?
      )
      ORDER BY m.timestampMs ASC
    ''', [endpointId]);
  }
}

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
  bool _discoveryInProgress = false;

  final LinkedHashSet<String> _processedMessageIds = LinkedHashSet<String>();
  final List<SosMessage> _messageLog = [];
  final Set<String> _linkedEndpoints = {};

  Timer? _discoveryTimer;
  Timer? _stopDiscoveryTimer;
  Timer? _activeSosIdResetTimer;

  String _userName = "مستخدم";
  String get _advertiseName => "Elnaseh_$_userName";
  String _sharedKey = "Elnaseh_Key_1";
  int _maxTtl = 5;

  static const Map<String, int> _ttlOptions = {
    'قريب (3)': 3,
    'متوازن (5)': 5,
    'بعيد (10)': 10,
    'طوارئ قصوى (15)': 15,
  };

  final Strategy strategy = Strategy.P2P_CLUSTER;
  final String serviceId = "com.elnaseh.app";
  static const double _targetRadius = 180.0;
  static const int _maxTargets = 20;
  static const int _maxProcessedIds = 1000;
  static const Duration _ackTimeout = Duration(seconds: 5);
  static const String _dummyEndpoint = "dummy_endpoint";

  String? _activeSosId;
  final Set<String> _ackedNames = {};
  int _activeSosTargetCount = 0;

  @override
  void initState() {
    super.initState();
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _loadPrefs().then((_) => _initNearby());
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _userName = prefs.getString('userName') ?? "مستخدم";
      _maxTtl = prefs.getInt('maxTtl') ?? 5;
      final savedKey = prefs.getString('sharedKey');
      if (savedKey == null || savedKey.isEmpty) {
        _sharedKey = CryptoHelper.generateRandomKey();
        prefs.setString('sharedKey', _sharedKey);
      } else {
        _sharedKey = savedKey;
      }
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

    final granted = (statuses[Permission.location]?.isGranted ?? false) &&
        (statuses[Permission.bluetoothScan]?.isGranted ?? false);

    if (!granted) {
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
            content: Text('⚠️ يرجى تشغيل خدمة الموقع (GPS)!'),
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

  Future<void> _startAdvertising() async {
    if (_isAdvertising) return;
    try {
      await Nearby().startAdvertising(
        _advertiseName,
        strategy,
        onConnectionInitiated: (id, info) async {
          await Nearby().acceptConnection(
            id,
            onPayLoadRecieved: (endpointId, payload) {
              if (payload.type == PayloadType.BYTES && payload.bytes != null) {
                _onPayloadReceived(endpointId, payload.bytes!);
              }
            },
            onPayloadTransferUpdate: (_, __) {},
          );
        },
        onConnectionResult: (id, status) {
          if (status == Status.CONNECTED) {
            _linkedEndpoints.add(id);
            _refreshTargetColor(id, Colors.cyanAccent);
            _syncMessagesWithPeer(id);
          }
        },
        onDisconnected: (id) {
          _linkedEndpoints.remove(id);
          if (mounted) {
            setState(() => _targets.removeWhere((t) => t['id'] == id));
          }
        },
        serviceId: serviceId,
      );
      if (mounted) setState(() => _isAdvertising = true);
    } catch (e) {
      debugPrint("❌ فشل الإعلان: $e");
    }
  }

  void _startDiscoveryWithTimer() {
    _startDiscovery();
    _discoveryTimer = Timer.periodic(
      const Duration(seconds: 35),
      (_) => _startDiscovery(),
    );
  }

  Future<void> _startDiscovery() async {
    if (_discoveryInProgress || !mounted) return;
    _discoveryInProgress = true;
    try {
      await Nearby().stopDiscovery().catchError((_) {});
      if (mounted) setState(() => _isScanning = true);

      await Nearby().startDiscovery(
        _userName,
        strategy,
        onEndpointFound: (id, name, svcId) {
          if (svcId != serviceId) return;
          if (_targets.any((t) => t['id'] == id)) return;

          setState(() {
            if (_targets.length >= _maxTargets) _targets.removeAt(0);
            final angle = (_targets.length * (2 * pi / 8)) - (pi / 2);
            _targets.add({
              'id': id,
              'name': name.replaceFirst("Elnaseh_", ""),
              'angle': angle + Random().nextDouble() * 0.15,
              'radius': _targetRadius,
              'color': Colors.amberAccent,
            });
          });

          Future.delayed(
            const Duration(milliseconds: 500),
            () => _ensureConnected(id),
          );
        },
        onEndpointLost: (id) {
          _linkedEndpoints.remove(id);
          if (mounted) {
            setState(() => _targets.removeWhere((t) => t['id'] == id));
          }
        },
        serviceId: serviceId,
      );

      _stopDiscoveryTimer?.cancel();
      _stopDiscoveryTimer = Timer(const Duration(seconds: 30), () async {
        await Nearby().stopDiscovery().catchError((_) {});
        if (mounted) setState(() => _isScanning = false);
      });
    } catch (e) {
      debugPrint("❌ الاكتشاف فشل: $e");
      if (mounted) setState(() => _isScanning = false);
    } finally {
      _discoveryInProgress = false;
    }
  }

  Future<void> _ensureConnected(String endpointId) async {
    if (_linkedEndpoints.contains(endpointId)) return;
    try {
      await Nearby().requestConnection(
        _userName,
        endpointId,
        onConnectionInitiated: (id, info) async {
          await Nearby().acceptConnection(
            id,
            onPayLoadRecieved: (epid, payload) {
              if (payload.type == PayloadType.BYTES && payload.bytes != null) {
                _onPayloadReceived(epid, payload.bytes!);
              }
            },
            onPayloadTransferUpdate: (_, __) {},
          );
        },
        onConnectionResult: (id, status) {
          if (status == Status.CONNECTED) {
            _linkedEndpoints.add(id);
            _refreshTargetColor(id, Colors.cyanAccent);
            _syncMessagesWithPeer(id);
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

  Future<void> _syncMessagesWithPeer(String endpointId) async {
    try {
      final unsent = await DatabaseHelper.instance.getUnsentMessages(endpointId);
      for (final rawMsg in unsent) {
        final msg = SosMessage(
          id: rawMsg['id'] as String,
          sender: rawMsg['sender'] as String,
          ttl: rawMsg['ttl'] as int,
          content: rawMsg['content'] as String,
          timestampMs: rawMsg['timestampMs'] as int,
          type: rawMsg['type'] as String,
          lat: rawMsg['lat'] != null ? (rawMsg['lat'] as num).toDouble() : null,
          lng: rawMsg['lng'] != null ? (rawMsg['lng'] as num).toDouble() : null,
        );
        final data = Uint8List.fromList(utf8.encode(msg.encode(_sharedKey)));
        final ok = await _sendWithRetry(endpointId, data);
        if (ok) {
          await DatabaseHelper.instance.markAsSent(msg.id, endpointId);
        }
      }
    } catch (e) {
      debugPrint("فشل المزامنة: $e");
    }
  }

  Future<bool> _sendWithRetry(String endpointId, Uint8List data) async {
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        if (!_linkedEndpoints.contains(endpointId)) {
          await _ensureConnected(endpointId);
          await Future.delayed(const Duration(milliseconds: 400));
        }
        await Nearby().sendBytesPayload(endpointId, data);
        return true;
      } catch (e) {
        debugPrint("محاولة $attempt فشلت: $e");
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      }
    }
    return false;
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
      try {
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 10),
        );
      } catch (_) {
        return await Geolocator.getLastKnownPosition();
      }
    }
  }

  Future<void> _sendSosBroadcast() async {
    if (_targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد أجهزة قريبة (جرب زر الاختبار ✨)'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final customMessage = await _askForMessage();
    if (customMessage == null || customMessage.trim().isEmpty) return;

    setState(() {
      _isSosSending = true;
      _ackedNames.clear();
      _activeSosTargetCount = _targets.length;
    });
    HapticFeedback.heavyImpact();

    final pos = await _getCurrentLocation();
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

    _processedMessageIds.add(messageId);
    _activeSosId = messageId;
    _activeSosIdResetTimer?.cancel();

    await DatabaseHelper.instance.saveMessage({
      'id': sos.id,
      'sender': sos.sender,
      'content': sos.content,
      'ttl': sos.ttl,
      'lat': sos.lat,
      'lng': sos.lng,
      'timestampMs': sos.timestampMs,
      'type': sos.type,
    });

    final targetsCopy = List<Map<String, dynamic>>.from(_targets);
    final data = Uint8List.fromList(utf8.encode(sos.encode(_sharedKey)));

    await Future.wait(targetsCopy.map((t) => _sendWithRetry(t['id'], data)));
    await Future.delayed(_ackTimeout);

    if (!mounted) return;
    setState(() => _isSosSending = false);

    final ackedCount = _ackedNames.length;
    final total = _activeSosTargetCount;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ackedCount == 0
              ? '⚠️ لم يصل التأكيد من أي جهاز'
              : '✅ وصل التأكيد من $ackedCount من $total أجهزة',
        ),
        backgroundColor: ackedCount == 0 ? Colors.red : Colors.green,
        duration: const Duration(seconds: 5),
      ),
    );

    _activeSosIdResetTimer = Timer(const Duration(seconds: 30), () {
      if (mounted) setState(() => _activeSosId = null);
    });
  }

  Future<String?> _askForMessage() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'إرسال نداء استغاثة',
          style: TextStyle(color: Colors.cyanAccent),
        ),
        content: TextField(
          controller: controller,
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
            onPressed: () => Navigator.pop(context, null),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('إرسال', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  void _onPayloadReceived(String fromEndpointId, Uint8List bytes) {
    final raw = utf8.decode(bytes, allowMalformed: true);
    final msg = SosMessage.tryDecode(raw, _sharedKey);
    if (msg == null) return;
    if (msg.type != 'ACK' && msg.isExpired()) return;
    _handleIncomingMessage(msg, fromEndpointId);
  }

  void _handleIncomingMessage(SosMessage msg, String fromEndpointId) {
    if (msg.type == 'SOS') {
      _sendAck(msg.id, msg.sender, fromEndpointId);
    }

    if (_processedMessageIds.contains(msg.id)) return;
    _processedMessageIds.add(msg.id);

    if (_processedMessageIds.length > _maxProcessedIds) {
      _processedMessageIds.remove(_processedMessageIds.first);
    }

    DatabaseHelper.instance.saveMessage({
      'id': msg.id,
      'sender': msg.sender,
      'content': msg.content,
      'ttl': msg.ttl,
      'lat': msg.lat,
      'lng': msg.lng,
      'timestampMs': msg.timestampMs,
      'type': msg.type,
    });

    if (fromEndpointId != _dummyEndpoint) {
      DatabaseHelper.instance.markAsSent(msg.id, fromEndpointId);
    }

    if (msg.type == 'ACK') {
      if (_activeSosId != null && msg.ackFor == _activeSosId) {
        if (mounted) setState(() => _ackedNames.add(msg.sender));
      }
      return;
    }

    _messageLog.add(msg);

    if (mounted) {
      _alertSosReceived();
      _showSosReceived(msg);
    }

    if (msg.ttl > 1) {
      final relay = SosMessage(
        id: msg.id,
        sender: msg.sender,
        ttl: msg.ttl - 1,
        content: msg.content,
        timestampMs: msg.timestampMs,
        type: 'SOS',
        lat: msg.lat,
        lng: msg.lng,
      );
      _relayMessage(relay, fromEndpointId);
    }
  }

  Future<void> _sendAck(
    String forMessageId,
    String toSender,
    String toEndpointId,
  ) async {
    if (toEndpointId == _dummyEndpoint) return;
    final ack = SosMessage(
      id:
          'ack_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999)}',
      sender: _userName,
      ttl: 1,
      content: '',
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      type: 'ACK',
      ackFor: forMessageId,
    );
    await _sendWithRetry(
      toEndpointId,
      Uint8List.fromList(utf8.encode(ack.encode(_sharedKey))),
    );
  }

  Future<void> _relayMessage(SosMessage msg, String excludeEndpointId) async {
    final data = Uint8List.fromList(utf8.encode(msg.encode(_sharedKey)));
    final others = List<Map<String, dynamic>>.from(_targets)
        .where((t) => t['id'] != excludeEndpointId);
    await Future.wait(others.map((t) => _sendWithRetry(t['id'], data)));
  }

  Future<void> _alertSosReceived() async {
    HapticFeedback.vibrate();
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    Future.delayed(
        const Duration(milliseconds: 400), () => HapticFeedback.vibrate());
    Future.delayed(
        const Duration(milliseconds: 800), () => HapticFeedback.vibrate());
    Future.delayed(
        const Duration(milliseconds: 1200), () => HapticFeedback.vibrate());
  }

  void _showSosReceived(SosMessage msg) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(
          '🚨 استغاثة من ${msg.sender}',
          style: const TextStyle(color: Colors.redAccent),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              msg.content,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            if (msg.lat != null && msg.lng != null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '📍 الموقع الجغرافي متوفر',
                  style: TextStyle(color: Colors.cyanAccent, fontSize: 12),
                ),
              ),
          ],
        ),
        actions: [
          if (msg.lat != null && msg.lng != null)
            TextButton.icon(
              icon: const Icon(Icons.map, color: Colors.greenAccent),
              label: const Text(
                'عرض على الخريطة',
                style: TextStyle(color: Colors.greenAccent),
              ),
              onPressed: () async {
                final url = Uri.parse(
                  'https://www.google.com/maps/search/?api=1&query=${msg.lat},${msg.lng}',
                );
                try {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text('فشل فتح الخريطة: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'حسناً',
              style: TextStyle(color: Colors.cyanAccent),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _testIncomingSos() async {
    final msg = SosMessage(
      id: 'test_${DateTime.now().millisecondsSinceEpoch}',
      sender: "جهاز تجريبي",
      ttl: 1,
      content: "هذه رسالة اختبار! تأكد من أن الصوت والاهتزاز والخريطة تعمل.",
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      type: 'SOS',
      lat: 24.7136,
      lng: 46.6753,
    );
    _handleIncomingMessage(msg, _dummyEndpoint);
  }

  void _showLog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (ctx) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '📜 سجل الرسائل',
            style: TextStyle(
              color: Colors.cyanAccent,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Divider(color: Colors.grey),
          if (_messageLog.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'لا توجد رسائل بعد',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            ..._messageLog.reversed.map((m) {
              return ListTile(
                leading: const Icon(Icons.warning, color: Colors.redAccent),
                title: Text(
                  'من: ${m.sender}',
                  style: const TextStyle(color: Colors.cyanAccent),
                ),
                subtitle: Text(
                  m.content,
                  style: const TextStyle(color: Colors.white70),
                ),
                trailing: (m.lat != null && m.lng != null)
                    ? IconButton(
                        icon: const Icon(Icons.map, color: Colors.greenAccent),
                        onPressed: () async {
                          final url = Uri.parse(
                            'https://www.google.com/maps/search/?api=1&query=${m.lat},${m.lng}',
                          );
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url,
                                mode: LaunchMode.externalApplication);
                          }
                        },
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
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'مدى انتشار الاستغاثة',
          style: TextStyle(color: Colors.cyanAccent),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _ttlOptions.entries.map((entry) {
            final sel = entry.value == _maxTtl;
            return ListTile(
              leading: Icon(
                sel
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: sel ? Colors.cyanAccent : Colors.grey,
              ),
              title: Text(
                entry.key,
                style:
                    TextStyle(color: sel ? Colors.cyanAccent : Colors.white),
              ),
              onTap: () => Navigator.pop(ctx, entry.value),
            );
          }).toList(),
        ),
      ),
    );
    if (selected != null) {
      setState(() => _maxTtl = selected);
      (await SharedPreferences.getInstance()).setInt('maxTtl', selected);
    }
  }

  Future<void> _showKeySettings() async {
    final controller = TextEditingController(text: _sharedKey);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          '🔑 مفتاح التشفير',
          style: TextStyle(color: Colors.cyanAccent),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          maxLength: 32,
          decoration: const InputDecoration(
            hintText: 'المفتاح',
            hintStyle: TextStyle(color: Colors.grey),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('حفظ', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null && result.trim().isNotEmpty) {
      setState(() => _sharedKey = result.trim());
      (await SharedPreferences.getInstance())
          .setString('sharedKey', _sharedKey);
    }
  }

  @override
  void dispose() {
    _discoveryTimer?.cancel();
    _stopDiscoveryTimer?.cancel();
    _activeSosIdResetTimer?.cancel();
    Nearby().stopAdvertising();
    Nearby().stopDiscovery();
    Nearby().stopAllEndpoints();
    _sweepController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shield_moon, color: Colors.cyanAccent, size: 28),
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
                  letterSpacing: 2,
                ),
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
            icon: const Icon(Icons.auto_awesome, color: Colors.amberAccent),
            tooltip: 'اختبار',
            onPressed: _testIncomingSos,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.cyanAccent),
            color: const Color(0xFF1E1E1E),
            onSelected: (value) {
              switch (value) {
                case 'key':
                  _showKeySettings();
                  break;
                case 'log':
                  _showLog();
                  break;
                case 'ttl':
                  _showTtlSelector();
                  break;
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'key',
                child: ListTile(
                  leading: Icon(Icons.vpn_key, color: Colors.cyanAccent),
                  title: Text('مفتاح التشفير',
                      style: TextStyle(color: Colors.white)),
                ),
              ),
              PopupMenuItem(
                value: 'log',
                child: ListTile(
                  leading: Icon(Icons.history, color: Colors.cyanAccent),
                  title: Text('السجل', style: TextStyle(color: Colors.white)),
                ),
              ),
              PopupMenuItem(
                value: 'ttl',
                child: ListTile(
                  leading: Icon(Icons.tune, color: Colors.cyanAccent),
                  title: Text('مدى الانتشار',
                      style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = max(
            0.0,
            min(constraints.maxWidth, constraints.maxHeight - 120),
          );
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
                            width
