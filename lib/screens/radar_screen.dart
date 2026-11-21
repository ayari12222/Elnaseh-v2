import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key});

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> with TickerProviderStateMixin {
  late AnimationController _sweepController;
  late AnimationController _pulseController;

  final List<Map<String, dynamic>> _targets = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  bool _isScanning = false;
  
  String _userName = "مستخدم";
  String get _advertiseName => "Elnaseh_$_userName";

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

    _loadUserName().then((_) => _initBluetooth());
  }

  Future<void> _loadUserName() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('userName') ?? "مستخدم";
    });
  }

  Future<void> _initBluetooth() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (statuses[Permission.bluetoothScan]!.isGranted &&
        statuses[Permission.bluetoothAdvertise]!.isGranted) {
      _startAdvertising();
      _startScanning();
    } else {
      debugPrint("أذونات البلوتوث غير ممنوحة");
    }
  }

  Future<void> _startAdvertising() async {
    try {
      await FlutterBluePlus.startAdvertising(
        _advertiseName,
        androidAdvertiseSettings: AndroidAdvertiseSettings(
          connectable: true,
        ),
      );
      debugPrint("بدأ الإعلان باسم: $_advertiseName");
    } catch (e) {
      debugPrint("فشل الإعلان: $e");
    }
  }

  void _startScanning() {
    setState(() => _isScanning = true);
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (r.device.platformName.startsWith("Elnaseh_") && 
            !_targets.any((t) => t['id'] == r.device.remoteId.toString())) {
          
          String discoveredName = r.device.platformName.replaceFirst("Elnaseh_", "");
          
          setState(() {
            _targets.add({
              'id': r.device.remoteId.toString(),
              'name': discoveredName,
              'distance': 0.3 + (Random().nextDouble() * 0.5),
              'color': Colors.cyanAccent,
            });
          });
        }
      }
    });

    FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 10),
      androidUsesFineLocation: true,
    );
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    FlutterBluePlus.stopAdvertising();
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
                FlutterBluePlus.stopScan();
                setState(() => _isScanning = false);
              } else {
                _startScanning();
              }
            },
          ),
        ],
      ),
      body: Center(
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
