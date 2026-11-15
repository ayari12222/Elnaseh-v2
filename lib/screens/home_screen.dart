import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الناصح'),
        backgroundColor: const Color(0xFF1E1E1E),
      ),
      body: const Center(
        child: Text(
          'مرحباً بك في تطبيق الناصح',
          style: TextStyle(color: Colors.white, fontSize: 20),
        ),
      ),
    );
  }
}
