import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../crypto_helper.dart';
import '../database_helper.dart';

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
  bool _showInstructions = true;

  final LinkedHashSet<String> _processedMessageIds = LinkedHashSet<String>();
  final List<SosMessage> _messageLog = [];
  final Set<String> _linkedEndpoints = {};

  Timer? _discoveryTimer;
  Timer? _stopDiscoveryTimer;
  Timer? _activeSosIdResetTimer;

  String _userName = "مستخدم";
  String _deviceId = "";
  String get _advertiseName => "Elnaseh_${_deviceId}_$_userName";
  String _sharedKey = "Elnaseh_Key_1";
  int _maxTtl = 5;

  static const Map<String, int> _ttlOptions = {
    'قريب جداً (للأجهزة المحيطة فقط)': 3,
    'متوازن (عبر بعض الأجهزة الوسيطة)': 5,
    'بعيد (لمسافة طويلة)': 10,
    'طوارئ قصوى (مسح شامل للمنطقة)': 15,
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
    
    _loadPrefs().then((_) {
      _initNearby();
      if (_showInstructions) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const HelpScreen()),
            );
          }
        });
      }
    });
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _userName = prefs.getString('userName') ?? "مستخدم";
      _maxTtl = prefs.getInt('maxTtl') ?? 5;
      _showInstructions = prefs.getBool('showInstructions') ?? true;
      
      var savedId = prefs.getString('deviceId');
      if (savedId == null || savedId.isEmpty) {
        savedId = CryptoHelper.generateRandomKey().substring(0, 8);
        prefs.setString('deviceId', savedId);
      }
      _deviceId = savedId;

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
              'name': name.split('_').last,
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
        final encryptedContent = CryptoHelper.encrypt(rawMsg['content'] as String, _sharedKey);
        final packet = MeshPacket(
          messageId: rawMsg['id'] as String,
          senderId: _deviceId,
          senderName: rawMsg['sender'] as String,
          targetId: "ALL",
          ttl: rawMsg['ttl'] as int,
          type: rawMsg['type'] as String,
          timestampMs: rawMsg['timestampMs'] as int,
          encryptedPayload: encryptedContent,
          lat: rawMsg['lat'] != null ? (rawMsg['lat'] as num).toDouble() : null,
          lng: rawMsg['lng'] != null ? (rawMsg['lng'] as num).toDouble() : null,
        );
        
        final data = Uint8List.fromList(utf8.encode(packet.encodePacket()));
        final ok = await _sendWithRetry(endpointId, data);
        if (ok) {
          await DatabaseHelper.instance.markAsSent(packet.messageId, endpointId);
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

    final encryptedContent = CryptoHelper.encrypt(customMessage.trim(), _sharedKey);
    final packet = MeshPacket(
      messageId: messageId,
      senderId: _deviceId,
      senderName: _userName,
      targetId: "ALL",
      ttl: _maxTtl,
      type: 'SOS',
      timestampMs: now,
      encryptedPayload: encryptedContent,
      lat: pos?.latitude,
      lng: pos?.longitude,
    );

    _processedMessageIds.add(messageId);
    _activeSosId = messageId;
    _activeSosIdResetTimer?.cancel();

    await DatabaseHelper.instance.saveMessage({
      'id': packet.messageId,
      'sender': packet.senderName,
      'content': customMessage.trim(),
      'ttl': packet.ttl,
      'lat': packet.lat,
      'lng': packet.lng,
      'timestampMs': packet.timestampMs,
      'type': packet.type,
    });

    final targetsCopy = List<Map<String, dynamic>>.from(_targets);
    final data = Uint8List.fromList(utf8.encode(packet.encodePacket()));

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
    final packet = MeshPacket.tryDecodePacket(raw);
    
    if (packet == null) return;
    if (packet.type != 'ACK' && packet.isExpired()) return;

    if (packet.targetId != "ALL" && packet.targetId != _deviceId) {
      _relayPacket(packet, fromEndpointId);
      return;
    }

    final decryptedContent = CryptoHelper.decrypt(packet.encryptedPayload, _sharedKey);
    if (decryptedContent == null) return;

    final msg = SosMessage(
      id: packet.messageId,
      sender: packet.senderName,
      ttl: packet.ttl,
      content: decryptedContent,
      timestampMs: packet.timestampMs,
      type: packet.type,
      lat: packet.lat,
      lng: packet.lng,
    );

    _handleIncomingMessage(msg, fromEndpointId);

    if (packet.ttl > 1) {
      final relayPacket = MeshPacket(
        messageId: packet.messageId,
        senderId: packet.senderId,
        senderName: packet.senderName,
        targetId: packet.targetId,
        ttl: packet.ttl - 1,
        type: packet.type,
        timestampMs: packet.timestampMs,
        encryptedPayload: packet.encryptedPayload,
        lat: packet.lat,
        lng: packet.lng,
      );
      _relayPacket(relayPacket, fromEndpointId);
    }
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
      if (_activeSosId != null && msg.content == _activeSosId) {
        if (mounted) setState(() => _ackedNames.add(msg.sender));
      }
      return;
    }

    _messageLog.add(msg);

    if (mounted) {
      _alertSosReceived();
      _showSosReceived(msg);
    }
  }

  Future<void> _sendAck(
    String forMessageId,
    String toSender,
    String toEndpointId,
  ) async {
    if (toEndpointId == _dummyEndpoint) return;
    
    final encryptedContent = CryptoHelper.encrypt(forMessageId, _sharedKey);
    final packet = MeshPacket(
      messageId: 'ack_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999)}',
      senderId: _deviceId,
      senderName: _userName,
      targetId: toSender,
      ttl: 1,
      type: 'ACK',
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      encryptedPayload: encryptedContent,
    );

    await _sendWithRetry(
      toEndpointId,
      Uint8List.fromList(utf8.encode(packet.encodePacket())),
    );
  }

  Future<void> _relayPacket(MeshPacket packet, String excludeEndpointId) async {
    final data = Uint8List.fromList(utf8.encode(packet.encodePacket()));
    final others = List<Map<String, dynamic>>.from(_targets)
        .where((t) => t['id'] != excludeEndpointId);
    
    await Future.wait(others.map((t) => _sendWithRetry(t['id'], data)));
  }

  Future<void> _alertSosReceived() async {
    HapticFeedback.vibrate();
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    Future.delayed(const Duration(milliseconds: 400), () => HapticFeedback.vibrate());
    Future.delayed(const Duration(milliseconds: 800), () => HapticFeedback.vibrate());
    Future.delayed(const Duration(milliseconds: 1200), () => HapticFeedback.vibrate());
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
            ..._messageLog.reversed.map<SosMessage>((m) {  // <--- الإصلاح هنا
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
                            await launchUrl(url, mode: LaunchMode.externalApplication);
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
          'مدى وصول الاستغاثة',
          style: TextStyle(color: Colors.cyanAccent),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'كلما زادت القيمة، انتقلت الرسالة عبر مسافة أطول وعبر أجهزة أكثر (يستهلك بطارية أكثر).',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 10),
            ..._ttlOptions.entries.map((entry) {
              final sel = entry.value == _maxTtl;
              return ListTile(
                leading: Icon(
                  sel ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: sel ? Colors.cyanAccent : Colors.grey,
                ),
                title: Text(
                  entry.key,
                  style: TextStyle(color: sel ? Colors.cyanAccent : Colors.white),
                ),
                onTap: () => Navigator.pop(ctx, entry.value),
              );
            }),
          ],
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
      (await SharedPreferences.getInstance()).setString('sharedKey', _sharedKey);
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
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
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
            icon: const Icon(Icons.help_outline, color: Colors.cyanAccent),
            tooltip: 'كيف يعمل التطبيق؟',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HelpScreen()),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.cyanAccent),
            color: const Color(0xFF1E1E1E),
            onSelected: (value) {
              switch (value) {
                case 'key': _showKeySettings(); break;
                case 'log': _showLog(); break;
                case 'ttl': _showTtlSelector(); break;
                case 'test': _testIncomingSos(); break;
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'key',
                child: ListTile(
                  leading: Icon(Icons.vpn_key, color: Colors.cyanAccent),
                  title: Text('مفتاح التشفير', style: TextStyle(color: Colors.white)),
                ),
              ),
              PopupMenuItem(
                value: 'log',
                child: ListTile(
                  leading: Icon(Icons.history, color: Colors.cyanAccent),
                  title: Text('سجل الرسائل', style: TextStyle(color: Colors.white)),
                ),
              ),
              PopupMenuItem(
                value: 'ttl',
                child: ListTile(
                  leading: Icon(Icons.wifi_tethering, color: Colors.cyanAccent),
                  title: Text('قوة بث الرسالة', style: TextStyle(color: Colors.white)),
                ),
              ),
              PopupMenuItem(
                value: 'test',
                child: ListTile(
                  leading: Icon(Icons.auto_awesome, color: Colors.amberAccent),
                  title: Text('رسالة تجريبية', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = max(0.0, min(constraints.maxWidth, constraints.maxHeight - 120));
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
                            height: (size / 4) * (i + 1),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.cyanAccent.withOpacity(0.1 + (_pulseController.value * 0.2)),
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                      CustomPaint(size: Size(size, size), painter: RadarGridPainter()),
                      AnimatedBuilder(
                        animation: _sweepController,
                        builder: (context, child) => Container(
                          width: size * 0.5,
                          height: size * 0.5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: SweepGradient(
                              colors: [
                                Colors.cyanAccent.withOpacity(0.0),
                                Colors.cyanAccent.withOpacity(0.4),
                                Colors.cyanAccent.withOpacity(0.0),
                              ],
                              stops: const [0.0, 0.5, 1.0],
                              transform: GradientRotation(_sweepController.value * 2 * pi),
                            ),
                          ),
                        ),
                      ),
                      ..._targets.map((t) {
                        final double a = t['angle'] as double;
                        return Positioned(
                          left: center + radius * cos(a) - 12,
                          top: center + radius * sin(a) - 12,
                          child: Column(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: t['color'] as Color,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: (t['color'] as Color).withOpacity(0.8),
                                      blurRadius: 15,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                  border: Border.all(color: Colors.white, width: 1.5),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                t['name'],
                                style: TextStyle(
                                  color: t['color'] as Color,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.cyanAccent, blurRadius: 20, spreadRadius: 5),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 120,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    'الناصح يقدم الحل',
                    style: TextStyle(
                      color: Colors.cyanAccent.withOpacity(0.7),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      shadows: [Shadow(color: Colors.cyanAccent.withOpacity(0.5), blurRadius: 10)],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 30,
                left: 0,
                right: 0,
                child: Center(
                  child: FloatingActionButton.extended(
                    onPressed: _isSosSending ? null : _sendSosBroadcast,
                    backgroundColor: _isSosSending ? Colors.grey : Colors.redAccent,
                    icon: _isSosSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.warning, color: Colors.white),
                    label: Text(
                      _isSosSending ? 'جاري الإرسال...' : 'إرسال استغاثة SOS',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
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
    final paint = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.15)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

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

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        title: const Text('كيف يعمل التطبيق؟', style: TextStyle(color: Colors.cyanAccent)),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.cyanAccent),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.shield_moon, color: Colors.cyanAccent, size: 80),
          const SizedBox(height: 20),
          const Text(
            'مرحباً بك في تطبيق الناصح',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 30),
          _buildHelpItem('1️⃣', 'تشغيل الأجهزة', 'تأكد من تشغيل البلوتوث وخدمة الموقع (GPS) في هاتفك.'),
          _buildHelpItem('2️⃣', 'الرادار', 'سيقوم التطبيق بالبحث تلقائياً عن المستخدمين الآخرين القريبين منك وعرضهم على الشاشة.'),
          _buildHelpItem('3️⃣', 'إرسال الاستغاثة', 'عند وقوع خطر، اضغط على الزر الأحمر "إرسال استغاثة SOS" واكتب رسالتك.'),
          _buildHelpItem('4️⃣', 'شبكة الطوارئ (Mesh)', 'حتى لو كنت بعيداً عن الشخص، سيقوم التطبيق بتمرير الرسالة من هاتف إلى هاتف حتى تصل إليه.'),
          _buildHelpItem('5️⃣', 'بدون إنترنت', 'التطبيق لا يحتاج إلى شبكة إنترنت أو أبراج اتصال ليعمل إطلاقاً.'),
          const SizedBox(height: 40),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            onPressed: () {
              Navigator.pop(context);
              SharedPreferences.getInstance().then((prefs) => prefs.setBool('showInstructions', false));
            },
            child: const Text('فهمت، العودة للرادار', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpItem(String number, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(number, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.cyanAccent, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                Text(description, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

  
