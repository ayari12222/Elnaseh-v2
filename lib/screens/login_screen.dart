import 'package:flutter/material.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF121212),
      body: Center(
        child: Text(
          'شاشة تسجيل الدخول',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
      ),
    );
  }
}
