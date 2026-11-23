import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// ============================================================
// مساعد التشفير
// ============================================================
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
}

// ============================================================
// نموذج الرسالة
// ============================================================
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
        'id': id, 's': sender, 'ttl': ttl, 'c': content, 't': timestampMs, 'ty': type,
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
    return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(timestampMs)) > maxAge;
  }
}

// ============================================================
// شاشة الرادار
// ============================================================
class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key});

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> with TickerProviderStateMixin {
  late AnimationController _sweepController;
  late AnimationController _pulseController;

  final List<Map<String, dynamic>> _targets = [];
  bool _isScanning = false;
  bool _isAdvertising = false;
  bool _isSosSending = false;

  final Set<String> _processedMessageIds = {};
  final List<SosMessage> _messageLog = [];

  Timer? _discoveryTimer;
  Timer? _stopDiscoveryTimer;

  String _userName = "مستخدم";
  String get _advertiseName => "Elnaseh_$_userName";
  
  String _sharedKey = "Elnaseh_Key_1"; 

  final Strategy strategy = Strategy.P2P_CLUSTER;
  final String serviceId = "com.elnaseh.app";

  static const double _targetRadius = 180.0;
  static const int _maxTargets = 20;

  int _maxTtl = 5;
  static const Map<String, int> _ttlOptions = {
    'قريب (3)': 3, 'متوازن (5)': 5, 'بعيد (10)': 10, 'طوارئ قصوى (15)': 15,
  };

  static const Duration _ackTimeout = Duration(seconds: 5);
  String? _activeSosId;
  final Set<String> _ackedNames = {};

  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _sweepController = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _loadPrefs().then((_) => _initNearby());
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _userName = prefs.getString('userName') ?? "مستخدم";
      _maxTtl = prefs.getInt('maxTtl') ?? 5;
      _sharedKey = prefs.getString('sharedKey') ?? _sharedKey;
    });
  }

  Future<void> _initNearby() async {
    final statuses = await [
      Permission.location, Permission.bluetooth, Permission.bluetoothScan,
      Permission.bluetoothAdvertise, Permission.bluetoothConnect, Permission.nearbyWifiDevices,
    ].request();

    if ((statuses[Permission.location]?.isGranted ?? false) &&
        (statuses[Permission.bluetoothScan]?.isGranted ?? false)) {
      await _startAdvertising();
      _startDiscoveryWithTimer();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يجب منح أذونات الموقع والبلوتوث للعمل'), backgroundColor: Colors.orange),
        );
      }
    }
  }

  Future<void> _startAdvertising() async {
    if (_isAdvertising) return;
    try {
      await Nearby().startAdvertising(
        _advertiseName, strategy,
        onConnectionInitiated: (id, info) async {
          await Nearby().acceptConnection(
            id,
            onPayLoadRecieved: (endpointId, payload) {
              if (payload.type == PayloadType.BYTES && payload.bytes != null) {
                final raw = utf8.decode(payload.bytes!, allowMalformed: true);
                final msg = SosMessage.tryDecode(raw, _sharedKey);
                if (msg != null) _handleIncomingMessage(msg, endpointId);
              }
            },
            onPayloadTransferUpdate: (endpointId, update) {},
          );
        },
        onConnectionResult: (id, status) {},
        onDisconnected: (id) {},
        serviceId: serviceId,
      );
      setState(() => _isAdvertising = true);
    } catch (e) {
      debugPrint("❌ فشل الإعلان: $e");
    }
  }

  void _startDiscoveryWithTimer() {
    _startDiscovery();
    _discoveryTimer = Timer.periodic(const Duration(seconds: 35), (_) => _startDiscovery());
  }

  Future<void> _startDiscovery() async {
    if (!mounted) return;
    try {
      await Nearby().stopDiscovery().catchError((_) {});
      setState(() => _isScanning = true);
      await Nearby().startDiscovery(
        _userName, strategy,
        onEndpointFound: (id, name, svcId) {
          if (svcId != serviceId) return;
          if (_targets.any((t) => t['id'] == id)) return;
          setState(() {
            if (_targets.length >= _maxTargets) _targets.removeAt(0);
            final angle = (_targets.length * (2 * pi / 8)) - (pi / 2);
            _targets.add({
              'id': id, 'name': name.replaceFirst("Elnaseh_", ""),
              'angle': angle + Random().nextDouble() * 0.15,
              'radius': _targetRadius, 'color': Colors.cyanAccent,
            });
          });
        },
        onEndpointLost: (id) => setState(() => _targets.removeWhere((t) => t['id'] == id)),
        serviceId: serviceId,
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

  // ✅ دالة التنبيه (تشغيل الصوت الحقيقي من الجذر + الاهتزاز)
  Future<void> _alertSosReceived() async {
    HapticFeedback.vibrate();
    HapticFeedback.heavyImpact();

    try {
      // تشغيل الملف الصوتي من الجذر الرئيسي للمشروع
      await _audioPlayer.play(AssetSource('war-alarm-sound-long.mp3'));
    } catch (e) {
      debugPrint("❌ خطأ في تشغيل الصوت: $e");
      SystemSound.play(SystemSoundType.alert);
    }

    Future.delayed(const Duration(milliseconds: 400), () => HapticFeedback.vibrate());
    Future.delayed(const Duration(milliseconds: 800), () => HapticFeedback.vibrate());
  }

  Future<bool> _sendWithRetry(String endpointId, Uint8List data) async {
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        await Nearby().sendBytesPayload(endpointId, data);
        return true;
      } catch (e) {
        if (attempt < 3) await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    return false;
  }

  Future<Position?> _getCurrentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return null;
    try {
      return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 5));
    } catch (e) {
      return await Geolocator.getLastKnownPosition();
    }
  }

  Future<void> _sendSosBroadcast() async {
    if (_targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد أجهزة قريبة (جرب زر الاختبار ✨)'), backgroundColor: Colors.orange));
      return;
    }

    final customMessage = await _askForMessage();
    if (customMessage == null || customMessage.trim().isEmpty) return;

    setState(() { _isSosSending = true; _ackedNames.clear(); });
    HapticFeedback.heavyImpact();

    Position? pos = await _getCurrentLocation();
    final now = DateTime.now().millisecondsSinceEpoch;
    final messageId = '${now}_${Random().nextInt(9999)}';

    final sos = SosMessage(
      id: messageId, sender: _userName, ttl: _maxTtl,
      content: customMessage.trim(), timestampMs: now, type: 'SOS',
      lat: pos?.latitude, lng: pos?.longitude,
    );

    _processedMessageIds.add(messageId);
    _activeSosId = messageId;

    final targetsCopy = List<Map<String, dynamic>>.from(_targets);
    final data = Uint8List.fromList(utf8.encode(sos.encode(_sharedKey)));

    await Future.wait(targetsCopy.map((t) => _sendWithRetry(t['id'], data)));
    await Future.delayed(_ackTimeout);

    if (!mounted) return;
    setState(() => _isSosSending = false);

    final ackedCount = _ackedNames.length;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ackedCount == 0 ? '⚠️ لم يصل التأكيد' : '✅ وصل التأكيد من $ackedCount أجهزة'),
      backgroundColor: ackedCount == 0 ? Colors.red : Colors.green,
    ));
    _activeSosId = null;
  }

  Future<String?> _askForMessage() async {
    String message = "";
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('إرسال نداء استغاثة', style: TextStyle(color: Colors.cyanAccent)),
        content: TextField(
          autofocus: true, style: const TextStyle(color: Colors.white), maxLength: 200,
          decoration: const InputDecoration(hintText: 'اكتب رسالتك هنا...', hintStyle: TextStyle(color: Colors.grey)),
          onChanged: (v) => message = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('إلغاء', style: TextStyle(color: Colors.grey))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () => Navigator.pop(context, message), child: const Text('إرسال', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  void _handleIncomingMessage(SosMessage msg, String fromEndpointId) {
    if (msg.isExpired() || _processedMessageIds.contains(msg.id)) return;
    _processedMessageIds.add(msg.id);
    if (_processedMessageIds.length > 1000) _processedMessageIds.clear();

    if (msg.type == 'ACK') {
      if (_activeSosId != null && msg.ackFor == _activeSosId) setState(() => _ackedNames.add(msg.sender));
      return;
    }

    _sendAck(msg.id, msg.sender, fromEndpointId);
    _messageLog.add(msg);

    if (mounted) {
      _alertSosReceived();
      _showSosReceived(msg);
    }

    if (msg.ttl > 1) {
      final relay = SosMessage(id: msg.id, sender: msg.sender, ttl: msg.ttl - 1, content: msg.content, timestampMs: msg.timestampMs, type: 'SOS', lat: msg.lat, lng: msg.lng);
      _relayMessage(relay);
    }
  }

  Future<void> _sendAck(String forMessageId, String toSender, String toEndpointId) async {
    final ack = SosMessage(id: 'ack_${DateTime.now().millisecondsSinceEpoch}', sender: _userName, ttl: 1, content: '', timestampMs: DateTime.now().millisecondsSinceEpoch, type: 'ACK', ackFor: forMessageId);
    await _sendWithRetry(toEndpointId, Uint8List.fromList(utf8.encode(ack.encode(_sharedKey))));
  }

  Future<void> _relayMessage(SosMessage msg) async {
    final data = Uint8List.fromList(utf8.encode(msg.encode(_sharedKey)));
    await Future.wait(List<Map<String, dynamic>>.from(_targets).map((t) => _sendWithRetry(t['id'], data)));
  }

  void _showSosReceived(SosMessage msg) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('🚨 استغاثة من ${msg.sender}', style: const TextStyle(color: Colors.redAccent)),
        content: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(msg.content, style: const TextStyle(color: Colors.white, fontSize: 16)),
            if (msg.lat != null && msg.lng != null) const Text('📍 الموقع الجغرافي متوفر', style: TextStyle(color: Colors.cyanAccent, fontSize: 12)),
          ],
        ),
        actions: [
          if (msg.lat != null && msg.lng != null)
            TextButton.icon(
              icon: const Icon(Icons.map, color: Colors.greenAccent), label: const Text('عرض على الخريطة', style: TextStyle(color: Colors.greenAccent)),
              onPressed: () async {
                final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=${msg.lat},${msg.lng}');
                try {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('فشل فتح الخريطة: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('حسناً', style: TextStyle(color: Colors.cyanAccent))),
        ],
      ),
    );
  }

  Future<void> _testIncomingSos() async {
    final msg = SosMessage(
      id: 'test_${DateTime.now().millisecondsSinceEpoch}',
      sender: "جهاز تجريبي", ttl: 1,
      content: "هذه رسالة اختبار! تأكد من أن الصوت والاهتزاز والخريطة تعمل.",
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      type: 'SOS', lat: 24.7136, lng: 46.6753,
    );
    _handleIncomingMessage(msg, "dummy_endpoint");
  }

  void _showLog() {
    showModalBottomSheet(
      context: context, backgroundColor: const Color(0xFF1E1E1E),
      builder: (context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('📜 سجل الرسائل', style: TextStyle(color: Colors.cyanAccent, fontSize: 20, fontWeight: FontWeight.bold)),
          const Divider(color: Colors.grey),
          if (_messageLog.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('لا توجد رسائل بعد', style: TextStyle(color: Colors.grey)))
          else
            ..._messageLog.reversed.map((m) {
              return ListTile(
                leading: const Icon(Icons.warning, color: Colors.redAccent),
                title: Text('من: ${m.sender}', style: const TextStyle(color: Colors.cyanAccent)),
                subtitle: Text(m.content, style: const TextStyle(color: Colors.white70)),
                trailing: (m.lat != null && m.lng != null) ? IconButton(
                  icon: const Icon(Icons.map, color: Colors.greenAccent),
                  onPressed: () async {
                    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=${m.lat},${m.lng}');
                    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
                  },
                ) : null,
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
        title: const Text('مدى انتشار الاستغاثة', style: TextStyle(color: Colors.cyanAccent)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _ttlOptions.entries.map((entry) {
            return ListTile(
              leading: Icon(entry.value == _maxTtl ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: entry.value == _maxTtl ? Colors.cyanAccent : Colors.grey),
              title: Text(entry.key, style: TextStyle(color: entry.value == _maxTtl ? Colors.cyanAccent : Colors.white)),
              onTap: () => Navigator.pop(context, entry.value),
            );
          }).toList(),
        ),
      ),
    );
    if (selected != null) setState(() => _maxTtl = selected);
  }

  Future<void> _showKeySettings() async {
    String newKey = _sharedKey;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('🔑 مفتاح التشفير', style: TextStyle(color: Colors.cyanAccent)),
        content: TextField(
          controller: TextEditingController(text: _sharedKey), style: const TextStyle(color: Colors.white), maxLength: 32,
          decoration: const InputDecoration(hintText: 'المفتاح', hintStyle: TextStyle(color: Colors.grey)),
          onChanged: (v) => newKey = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء', style: TextStyle(color: Colors.grey))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent), onPressed: () => Navigator.pop(context, newKey), child: const Text('حفظ', style: TextStyle(color: Colors.black))),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      setState(() => _sharedKey = result.trim());
      (await SharedPreferences.getInstance()).setString('sharedKey', _sharedKey);
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _discoveryTimer?.cancel(); _stopDiscoveryTimer?.cancel();
    Nearby().stopAdvertising(); Nearby().stopDiscovery(); Nearby().stopAllEndpoints();
    _sweepController.dispose(); _pulseController.dispose();
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
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ).createShader(bounds),
              child: const Text('الناصح', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 2)),
            ),
          ],
        ),
        centerTitle: true, backgroundColor: Colors.transparent, elevation: 0,
        iconTheme: const IconThemeData(color: Colors.cyanAccent),
        actions: [
          IconButton(icon: const Icon(Icons.auto_awesome, color: Colors.amberAccent), tooltip: 'اختبار', onPressed: _testIncomingSos),
          IconButton(icon: const Icon(Icons.vpn_key), onPressed: _showKeySettings),
          IconButton(icon: const Icon(Icons.history), onPressed: _showLog),
          IconButton(icon: const Icon(Icons.tune), onPressed: _showTtlSelector),
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
                  width: size, height: size,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ...List.generate(4, (i) => AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) => Container(
                          width: (size / 4) * (i + 1), height: (size / 4) * (i + 1),
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.cyanAccent.withOpacity(0.1 + (_pulseController.value * 0.2)), width: 1.5)),
                        ),
                      )),
                      CustomPaint(size: Size(size, size), painter: RadarGridPainter()),
                      AnimatedBuilder(
                        animation: _sweepController,
                        builder: (context, child) => Transform.rotate(
                          angle: _sweepController.value * 2 * pi,
                          child: Container(
                            width: size * 0.5, height: size * 0.5,
                            decoration: BoxDecoration(shape: BoxShape.circle, gradient: SweepGradient(colors: [Colors.cyanAccent.withOpacity(0.0), Colors.cyanAccent.withOpacity(0.4), Colors.cyanAccent.withOpacity(0.0)], stops: const [0.0, 0.5, 1.0])),
                          ),
                        ),
                      ),
                      ..._targets.map((t) {
                        final double a = t['angle'] as double;
                        return Positioned(
                          left: center + radius * cos(a) - 12, top: center + radius * sin(a) - 12,
                          child: Column(
                            children: [
                              Container(width: 24, height: 24, decoration: BoxDecoration(color: t['color'] as Color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: (t['color'] as Color).withOpacity(0.8), blurRadius: 15, spreadRadius: 2)], border: Border.all(color: Colors.white, width: 1.5))),
                              const SizedBox(height: 4),
                              Text(t['name'], style: TextStyle(color: t['color'] as Color, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        );
                      }).toList(),
                      Container(width: 16, height: 16, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.cyanAccent, blurRadius: 20, spreadRadius: 5)])),
                    ],
                  ),
                ),
              ),
              
              Positioned(
                bottom: 120, left: 0, right: 0,
                child: Center(
                  child: Text(
                    'الناصح يقدم الحل',
                    style: TextStyle(
                      color: Colors.cyanAccent.withOpacity(0.7), fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5,
                      shadows: [Shadow(color: Colors.cyanAccent.withOpacity(0.5), blurRadius: 10)],
                    ),
                  ),
                ),
              ),

              Positioned(
                bottom: 30, left: 0, right: 0,
                child: Center(
                  child: FloatingActionButton.extended(
                    onPressed: _isSosSending ? null : _sendSosBroadcast,
                    backgroundColor: _isSosSending ? Colors.grey : Colors.redAccent,
                    icon: _isSosSending ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.warning, color: Colors.white),
                    label: Text(_isSosSending ? 'جاري الإرسال...' : 'إرسال SOS', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class RadarGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.cyanAccent.withOpacity(0.15)..strokeWidth = 1.0..style = PaintingStyle.stroke;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), paint);
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), paint);
    canvas.drawLine(Offset(0, 0), Offset(size.width, size.height), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
    canvas.drawCircle(center, radius, paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
