import 'dart:async';
import 'dart:math';
import 'dart:typed_data'; // <-- تمت إضافة هذا السطر
import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

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
  
  final Set<String> _receivedMessageIds = {};

  String _userName = "مستخدم";
  String get _advertiseName => "Elnaseh_$_userName";

  final Strategy strategy = Strategy.P2P_CLUSTER;
  final String serviceId = "com.elnaseh.app";

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
    setState(() {
      _userName = prefs.getString('userName') ?? "مستخدم";
    });
  }

  Future<void> _initNearby() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
    ].request();

    if (statuses[Permission.location]!.isGranted &&
        statuses[Permission.bluetoothScan]!.isGranted) {
      _startAdvertising();
      _startDiscovery();
    } else {
      debugPrint("الأذونات غير ممنوحة");
    }
  }

  Future<void> _startAdvertising() async {
    if (_isAdvertising) return;
    try {
      bool isSuccess = await Nearby().startAdvertising(
        _advertiseName,
        strategy,
        onConnectionInitiated: (id, info) {
          Nearby().acceptConnection(
            id,
            onPayLoadRecieved: (endpointId, payload) {
              if (payload.type == PayloadType.BYTES) {
                // التصحيح: استخدام Uint8List
                String message = String.fromCharCodes(Uint8List.fromList(payload.bytes!));
                _handleIncomingMessage(message);
              }
            },
            onPayloadTransferUpdate: (endpointId, update) {},
          );
        },
        onConnectionResult: (id, status) {},
        onDisconnected: (id) {},
        serviceId: serviceId,
      );
      if (isSuccess) {
        setState(() => _isAdvertising = true);
        debugPrint("بدأ الإعلان بنجاح");
      }
    } catch (e) {
      debugPrint("فشل الإعلان: $e");
    }
  }

  Future<void> _startDiscovery() async {
    if (_isScanning) return;
    setState(() => _isScanning = true);
    try {
      bool isSuccess = await Nearby().startDiscovery(
        _userName,
        strategy,
        onEndpointFound: (id, name, serviceId) {
          if (serviceId != this.serviceId) return;
          
          if (!_targets.any((t) => t['id'] == id)) {
            setState(() {
              _targets.add({
                'id': id,
                'name': name.replaceFirst("Elnaseh_", ""),
                'distance': 0.3 + (Random().nextDouble() * 0.5),
                'color': Colors.cyanAccent,
              });
            });
          }
        },
        onEndpointLost: (id) {
          setState(() {
            _targets.removeWhere((t) => t['id'] == id);
          });
        },
        serviceId: serviceId,
      );
      if (!isSuccess) {
        setState(() => _isScanning = false);
      }
    } catch (e) {
      debugPrint("فشل البحث: $e");
      setState(() => _isScanning = false);
    }
  }

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

    String? customMessage = await showDialog<String>(
      context: context,
      builder: (context) {
        String message = "";
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text(
            'إرسال نداء استغاثة',
            style: TextStyle(color: Colors.cyanAccent),
          ),
          content: TextField(
            autofocus: true,
            style: const TextStyle(color: Colors.white),
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
            onChanged: (value) => message = value,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(context, message),
              child: const Text('إرسال', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (customMessage == null || customMessage.trim().isEmpty) {
      return;
    }

    setState(() => _isSosSending = true);
    HapticFeedback.vibrate();

    String messageId = DateTime.now().millisecondsSinceEpoch.toString();
    String fullMessage = "🚨 SOS|$messageId|$_userName|$customMessage";
    _receivedMessageIds.add(messageId);

    for (var target in _targets) {
      try {
        // التصحيح: استخدام Uint8List.fromList
        await Nearby().sendBytesPayload(
          target['id'],
          Uint8List.fromList(fullMessage.codeUnits),
        );
      } catch (e) {
        debugPrint("فشل الإرسال إلى ${target['name']}: $e");
      }
    }

    setState(() => _isSosSending = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إرسال رسالتك لجميع الأجهزة القريبة'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _handleIncomingMessage(String message) {
    List<String> parts = message.split('|');
    if (parts.length < 4) return;
    if (parts[0] != "🚨 SOS") return;

    String messageId = parts[1];
    String senderName = parts[2];
    String content = parts[3];

    if (_receivedMessageIds.contains(messageId)) return;

    _receivedMessageIds.add(messageId);

    _showSosReceived(senderName, content);

    _relayMessage(message);
  }

  Future<void> _relayMessage(String originalMessage) async {
    for (var target in _targets) {
      try {
        // التصحيح: استخدام Uint8List.fromList
        await Nearby().sendBytesPayload(
          target['id'],
          Uint8List.fromList(originalMessage.codeUnits),
        );
      } catch (e) {
        debugPrint("فشل إعادة الإرسال إلى ${target['name']}: $e");
      }
    }
  }

  void _showSosReceived(String senderName, String content) {
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
            child: const Text('حسناً', style: TextStyle(color: Colors.cyanAccent)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
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
            icon: Icon(_isScanning ? Icons.stop : Icons.search, color: Colors.cyanAccent),
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
      body: Stack(
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ...List.generate(4, (i) {
                    return AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Container(
                          width: 120.0 * (i + 1),
                          height: 120.0 * (i + 1),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.cyanAccent.withOpacity(
                                0.1 + (_pulseController.value * 0.2),
                              ),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.cyanAccent.withOpacity(0.05),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  }),
                  CustomPaint(
                    size: const Size(500, 500),
                    painter: RadarGridPainter(),
                  ),
                  AnimatedBuilder(
                    animation: _sweepController,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: _sweepController.value * 2 * pi,
                        child: Container(
                          width: 250,
                          height: 250,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: SweepGradient(
                              colors: [
                                Colors.cyanAccent.withOpacity(0.0),
                                Colors.cyanAccent.withOpacity(0.4),
                                Colors.cyanAccent.withOpacity(0.0),
                              ],
                              stops: const [0.0, 0.5, 1.0],
                              startAngle: 0.0,
                              endAngle: pi * 2,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  ..._targets.map((t) {
                    double radius = 220 * (t['distance'] as num).toDouble();
                    double angle = (t['name'].hashCode % 360) * (pi / 180);

                    return Positioned(
                      left: 250 + radius * cos(angle) - 12,
                      top: 250 + radius * sin(angle) - 12,
                      child: Column(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: t['color'],
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: t['color'].withOpacity(0.8),
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
                              color: t['color'],
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              shadows: const [
                                Shadow(color: Colors.black, blurRadius: 4),
                              ],
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
                backgroundColor: _isSosSending ? Colors.grey : Colors.redAccent,
                icon: _isSosSending 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.warning, color: Colors.white),
                label: Text(
                  _isSosSending ? 'جاري الإرسال...' : 'إرسال SOS',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
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
