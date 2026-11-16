import 'package:flutter/material.dart';
import 'screens/home_screen_v3.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'الناصح',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF1E88E5),
        scaffoldBackgroundColor: const Color(0xFF121212),
        fontFamily: 'Cairo',
      ),
      home: const HomeScreenV3(),
    );
  }
}
