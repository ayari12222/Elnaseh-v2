import 'dart:math';
import 'package:flutter/material.dart';

class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key});

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> with TickerProviderStateMixin {
  late AnimationController _sweepController;
  late AnimationController _pulseController;

  final List<Map<String, dynamic>> _targets = [
    {'name': 'أحمد', 'distance': 0.25, 'color': Colors.cyanAccent},
    {'name': 'سارة', 'distance': 0.55, 'color': Colors.redAccent},
    {'name': 'محمد', 'distance': 0.80, 'color': Colors.cyanAccent},
    {'name': 'نور', 'distance': 0.40, 'color': Colors.redAccent},
  ];

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
  }

  @override
  void dispose() {
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
                double radius = 220 * t['distance'];
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
