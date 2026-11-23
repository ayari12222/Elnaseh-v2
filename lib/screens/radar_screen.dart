import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================
// نموذج الرسالة — JSON + Base64 (بدون مكتبات إضافية)
// ============================================================
class SosMessage {
  final String id;
  final String sender;
  final int ttl;
  final String content;
  final int timestampMs;
  final String type; // "SOS" أو "ACK"
  final String? ackFor;

  SosMessage({
    required this.id,
    required this.sender,
    required this.ttl,
    required this.content,
    required this.timestampMs,
    required this.type,
    this.ackFor,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        's': sender,
        'ttl': ttl,
        'c': content,
        't': timestampMs,
        'ty': type,
        if (ackFor != null) 'af': ackFor,
      };

  factory SosMessage.fromJson(Map<String, dynamic> j) => SosMessage(
        id: j['id'] as String,
        sender: j['s'] as String,
        ttl: j['ttl'] as int,
        content: j['c'] as String,
        timestampMs: j['t'] as int,
        type: j['ty'] as String,
        ackFor: j['af'] as String?,
      );

  String encode() => base64Encode(utf8.encode(jsonEncode(toJson())));

  static SosMessage? tryDecode(String s) {
    try {
      final json = jsonDecode(utf8.decode(base64Decode(s)));
      return SosMessage.fromJson(json as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  bool isExpired({Duration maxAge = const Duration(minutes: 30)}) {
    final age = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(timestampMs));
    return age > maxAge;
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

class _RadarScreenState extends State<RadarScreen>
    with TickerProviderStateMixin {
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

  final Map<String, bool> _connectedEndpoints = {};

  String _userName = "مستخدم";
  String get _advertiseName => "Elnaseh_$_userName";

  final Strategy strategy = Strategy.P2P_CLUSTER;
  final String serviceId = "com.elnaseh.app";

  static const double _targetRadius = 180.0;
  static const int _maxTargets = 20;

  int _maxTtl = 5;
  static const Map<String, int> _ttlOptions = {
    'قريب (3)': 3,
    'متوازن (5)': 5,
    'بعيد (10)': 10,
    'طوارئ قصوى (15)': 15,
  };

  static const Duration _ackTimeout = Duration(seconds: 5);

  String? _activeSosId;
  final Set<String> _ackedNames = {};

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

    _loadUserName().then((_) => _initNearby());
  }

  Future<void> _loadUserName() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _userName = prefs.getString('userName') ?? "مستخدم";
      _maxTtl = prefs.getInt('maxTtl') ?? 5;
    });
  }

  // ------------------------------------------------------------
  // إعداد Nearby + طلب الأذونات
  // ------------------------------------------------------------
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
    final scanOk = statuses[Permission.bluetoothScan]?.isGranted ?? false;

    if (locationOk && scanOk) {
      await _startAdvertising();
      _startDiscoveryWithTimer();
    } else {
      debugPrint("⚠️ الأذونات غير ممنوحة");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('يجب منح أذونات الموقع والبلوتوث للعمل'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  // ------------------------------------------------------------
  // الإعلان عن الجهاز
  // ------------------------------------------------------------
  Future<void> _startAdvertising() async {
    if (_isAdvertising) return;
    try {
      final ok = await Nearby().startAdvertising(
        _advertiseName,
        strategy,
        onConnectionInitiated: (id, info) async {
          await Nearby().acceptConnection(
            id,
            onPayLoadRecieved: (endpointId, payload) {
              if (payload.type == PayloadType.BYTES && payload.bytes != null) {
                final raw = utf8.decode(payload.bytes!, allowMalformed: true);
                final msg = SosMessage.tryDecode(raw);
                if (msg != null) _handleIncomingMessage(msg, endpointId);
              }
            },
            onPayloadTransferUpdate: (endpointId, update) {},
          );
          _connectedEndpoints[id] = true;
        },
        onConnectionResult: (id, status) {
          if (status == Status.CONNECTED) {
            _connectedEndpoints[id] = true;
          } else {
            _connectedEndpoints.remove(id);
          }
        },
        onDisconnected: (id) {
          _connectedEndpoints.remove(id);
        },
        serviceId: serviceId,
      );
      if (ok) {
        setState(() => _isAdvertising = true);
        debugPrint("✅ بدأ الإعلان");
      }
    } catch (e) {
      debugPrint("❌ فشل الإعلان: $e");
    }
  }

  // ------------------------------------------------------------
  // دورة البحث: 30 ثانية بحث + 5 ثوانٍ توقف
  // ------------------------------------------------------------
  void _startDiscoveryWithTimer() {
    _startDiscovery();
    _discoveryTimer = Timer.periodic(const Duration(seconds: 35), (_) {
      _startDiscovery();
    });
  }

  Future<void> _startDiscovery() async {
    if (!mounted) return;
    try {
      await Nearby().stopDiscovery().catchError((_) {});

      setState(() => _isScanning = true);

      final ok = await Nearby().startDiscovery(
        _userName,
        strategy,
        onEndpointFound: (id, name, svcId) {
          if (svcId != serviceId) return;
          if (_targets.any((t) => t['id'] == id)) return;

          setState(() {
            if (_targets.length >= _maxTargets) {
              _targets.removeAt(0);
            }
            _targets.add({
              'id': id,
              'name': name.replaceFirst("Elnaseh_", ""),
              'angle': 0.0,
              'radius': _targetRadius,
              'color': Colors.cyanAccent,
            });
            _reassignAngles();
          });
        },
        onEndpointLost: (id) {
          setState(() {
            _targets.removeWhere((t) => t['id'] == id);
            _reassignAngles();
          });
        },
        serviceId: serviceId,
      );

      if (!ok) {
        if (mounted) setState(() => _isScanning = false);
        return;
      }

      _stopDiscoveryTimer?.cancel();
      _stopDiscoveryTimer = Timer(const Duration(seconds: 30), () async {
        await Nearby().stopDiscovery().catchError((_) {});
        if (mounted) setState(() => _isScanning = false);
      });
    } catch (e) {
      debugPrint("❌ فشل البحث: $e");
      if (mounted) setState(() => _isScanning = false);
    }
  }

  // ------------------------------------------------------------
  // توزيع الزوايا — عادل + انحراف بسيط
  // ------------------------------------------------------------
  void _reassignAngles() {
    if (_targets.isEmpty) return;
    final step = 2 * pi / _targets.length;
    final rand = Random();
    for (int i = 0; i < _targets.length; i++) {
      _targets[i]['angle'] = (i * step) - (pi / 2) + rand.nextDouble() * 0.15;
    }
  }

  // ------------------------------------------------------------
  // اختيار TTL
  // ------------------------------------------------------------
  Future<void> _showTtlSelector() async {
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'مدى انتشار الاستغاثة',
          style: TextStyle(color: Colors.cyanAccent),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _ttlOptions.entries.map((entry) {
            final isSelected = entry.value == _maxTtl;
            return ListTile(
              leading: Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: isSelected ? Colors.cyanAccent : Colors.grey,
              ),
              title: Text(
                entry.key,
                style: TextStyle(
                  color: isSelected ? Colors.cyanAccent : Colors.white,
                ),
              ),
              subtitle: Text(
                'حتى ${entry.value} قفزة عبر الأجهزة',
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
              onTap: () => Navigator.pop(context, entry.value),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );

    if (selected != null) {
      setState(() => _maxTtl = selected);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('maxTtl', selected);
    }
  }

  // ------------------------------------------------------------
  // إرسال SOS مع انتظار ACK
  // ------------------------------------------------------------
  Future<void> _sendSosBroadcast() async {
    if (_targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد أجهزة قريبة لإرسال الإشارة إليها'),
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
    });
    HapticFeedback.heavyImpact();

    final now = DateTime.now().millisecondsSinceEpoch;
    final messageId = '${now}_${Random().nextInt(9999)}';

    final sos = SosMessage(
      id: messageId,
      sender: _userName,
      ttl: _maxTtl,
      content: customMessage.trim(),
      timestampMs: now,
      type: 'SOS',
    );

    _processedMessageIds.add(messageId);
    _activeSosId = messageId;

    final targetsCopy = List<Map<String, dynamic>>.from(_targets);
    final encoded = sos.encode();

    for (final target in targetsCopy) {
      try {
        await Nearby().sendBytesPayload(
          target['id'],
          Uint8List.fromList(utf8.encode(encoded)),
        );
      } catch (e) {
        debugPrint("❌ فشل الإرسال إلى ${target['name']}: $e");
      }
    }

    final totalTargets = targetsCopy.length;
    await Future.delayed(_ackTimeout);

    if (!mounted) return;

    setState(() => _isSosSending = false);

    final ackedCount = _ackedNames.length;
    String feedback;
    Color color;
    if (ackedCount == 0) {
      feedback = '⚠️ لم يصل التأكيد من أي جهاز — قد لا تكون الاستغاثة وصلت';
      color = Colors.red;
    } else if (ackedCount < totalTargets) {
      feedback =
          '✅ وصل التأكيد من $ackedCount من أصل $totalTargets جهاز\n(${_ackedNames.join("، ")})';
      color = Colors.orange;
    } else {
      feedback = '✅ وصلت الاستغاثة إلى جميع الأجهزة ($ackedCount)';
      color = Colors.green;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(feedback), backgroundColor: color),
    );

    _activeSosId = null;
  }

  Future<String?> _askForMessage() async {
    String message = "";
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'إرسال نداء استغاثة',
          style: TextStyle(color: Colors.cyanAccent),
        ),
        content: TextField(
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          maxLength: 200,
          decoration: const InputDecoration(
            hintText: 'اكتب رسالتك هنا...',
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.cyanAccent),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.cyanAccent, width: 2),
            ),
          ),
          onChanged: (v) => message = v,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, message),
            child:
                const Text('إرسال', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // استقبال رسالة (SOS أو ACK)
  // ------------------------------------------------------------
  void _handleIncomingMessage(SosMessage msg, String fromEndpointId) {
    if (msg.isExpired()) {
      debugPrint("⏰ رسالة منتهية الصلاحية: ${msg.id}");
      return;
    }

    if (_processedMessageIds.contains(msg.id)) return;
    _processedMessageIds.add(msg.id);

    // رد ACK
    if (msg.type == 'ACK') {
      if (_activeSosId != null && msg.ackFor == _activeSosId) {
        setState(() => _ackedNames.add(msg.sender));
      }
      return;
    }

    // استلام SOS
    _sendAck(msg.id, msg.sender, fromEndpointId);

    _messageLog.add(msg);
    if (mounted) {
      HapticFeedback.heavyImpact();
      _showSosReceived(msg.sender, msg.content);
    }

    if (msg.ttl > 1) {
      final relay = SosMessage(
        id: msg.id,
        sender: msg.sender,
        ttl: msg.ttl - 1,
        content: msg.content,
        timestampMs: msg.timestampMs,
        type: 'SOS',
      );
      _relayMessage(relay);
    }
  }

  Future<void> _sendAck(
      String forMessageId, String toSender, String toEndpointId) async {
    final ack = SosMessage(
      id: 'ack_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999)}',
      sender: _userName,
      ttl: 1,
      content: '',
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      type: 'ACK',
      ackFor: forMessageId,
    );
    final data = Uint8List.fromList(utf8.encode(ack.encode()));
    try {
      await Nearby().sendBytesPayload(toEndpointId, data);
    } catch (e) {
      debugPrint("❌ فشل إرسال ACK: $e");
    }
  }

  Future<void> _relayMessage(SosMessage msg) async {
    final data = Uint8List.fromList(utf8.encode(msg.encode()));
    final targetsCopy = List<Map<String, dynamic>>.from(_targets);
    for (final target in targetsCopy) {
      try {
        await Nearby().sendBytesPayload(target['id'], data);
      } catch (e) {
        debugPrint("❌ فشل إعادة البث إلى ${target['name']}: $e");
      }
    }
  }

  void _showSosReceived(String senderName, String content) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(
          '🚨 استغاثة من $senderName',
          style: const TextStyle(color: Colors.redAccent),
        ),
        content: Text(content, style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسناً',
                style: TextStyle(color: Colors.cyanAccent)),
          ),
        ],
      ),
    );
  }

  void _showLog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (context) => ListView(
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
              final time = DateTime.fromMillisecondsSinceEpoch(m.timestampMs);
              return ListTile(
                leading: const Icon(Icons.warning, color: Colors.redAccent),
                title: Text(
                  'من: ${m.sender}',
                  style: const TextStyle(color: Colors.cyanAccent),
                ),
                subtitle: Text(
                  '${m.content}\n${time.hour}:${time.minute.toString().padLeft(2, "0")}',
                  style: const TextStyle(color: Colors.white70),
                ),
                isThreeLine: true,
              );
            }),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _discoveryTimer?.cancel();
    _stopDiscoveryTimer?.cancel();
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
        title: const Text(
          'الرادار',
          style: TextStyle(
            color: Colors.cyanAccent,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.cyanAccent),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: Colors.cyanAccent),
            tooltip: 'السجل',
            onPressed: _showLog,
          ),
          IconButton(
            icon: const Icon(Icons.tune, color: Colors.cyanAccent),
            tooltip: 'مدى الانتشار: $_maxTtl قفزات',
            onPressed: _showTtlSelector,
          ),
          IconButton(
            icon: Icon(
              _isScanning ? Icons.stop : Icons.search,
              color: Colors.cyanAccent,
            ),
            onPressed: () {
              if (_isScanning) {
                Nearby().stopDiscovery();
                setState(() => _isScanning = false);
              } else {
                _startDiscovery();
              }
            },
          ),
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
                      ...List.generate(4, (i) {
                        return AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) => Container(
                            width: (size / 4) * (i + 1),
                            height: (size / 4) * (i + 1),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.cyanAccent.withOpacity(
                                  0.1 + (_pulseController.value * 0.2),
                                ),
                                width: 1.5,
                              ),
                            ),
                          ),
                        );
                      }),
                      CustomPaint(
                        size: Size(size, size),
                        painter: RadarGridPainter(),
                      ),
                      AnimatedBuilder(
                        animation: _sweepController,
                        builder: (context, child) => Transform.rotate(
                          angle: _sweepController.value * 2 * pi,
                          child: Container(
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
                              ),
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
                                      color: (t['color'] as Color)
                                          .withOpacity(0.8),
                                      blurRadius: 15,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1.5,
                                  ),
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
                            BoxShadow(
                              color: Colors.cyanAccent,
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                      ),
                    ],
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
                    backgroundColor:
                        _isSosSending ? Colors.grey : Colors.redAccent,
                    icon: _isSosSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.warning, color: Colors.white),
                    label: Text(
                      _isSosSending ? 'جاري الإرسال...' : 'إرسال SOS',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
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

    canvas.drawLine(
        Offset(center.dx, 0), Offset(center.dx, size.height), paint);
    canvas.drawLine(
        Offset(0, center.dy), Offset(size.width, center.dy), paint);

    canvas.drawLine(Offset(0, 0), Offset(size.width, size.height), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), paint);

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
