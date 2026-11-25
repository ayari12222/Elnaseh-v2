import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_mesh_network/flutter_mesh_network.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/home_screen_v9.dart';

// متغير عام للوصول إلى شبكة Mesh من أي مكان في التطبيق
late final MeshNetwork meshNetwork;
bool isMeshReady = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // إظهار أي خطأ بوضوح بدلاً من الشاشة الرمادية في وضع Release
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'حدث خطأ أثناء عرض الواجهة:\n${details.exceptionAsString()}',
              style: const TextStyle(color: Colors.redAccent, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  };

  // 0. تهيئة Firebase بأمان إن وُجدت إعداداته
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('⚠️ تنبيه Firebase: $e');
  }

  // 1. تهيئة Supabase (للدردشة والمواقع) بأمان
  try {
    await Supabase.initialize(
      url: 'YOUR_SUPABASE_URL',
      anonKey: 'YOUR_SUPABASE_ANON_KEY',
    );
  } catch (e) {
    debugPrint('⚠️ تنبيه Supabase: $e');
  }

  // 2. تهيئة شبكة Mesh (روح التطبيق - SOS) بأمان حتى مع وضع الطيران
  try {
    meshNetwork = MeshNetwork(
      config: const MeshConfig(serviceName: 'elnaseh-sos'),
    );

    await meshNetwork.start(
      userId: 'user_${DateTime.now().millisecondsSinceEpoch}',
      userName: 'مستخدم_${DateTime.now().millisecondsSinceEpoch % 1000}',
    );
    isMeshReady = true;

    // 3. الاستماع للرسائل الواردة (لميزة SOS)
    meshNetwork.onMessage.listen((msg) {
      debugPrint('📩 رسالة من ${msg.senderName}: ${msg.payload}');
      // لاحقاً: سنضيف إشعاراً هنا عندما تكون الرسالة من نوع SOS
    });
  } catch (e) {
    debugPrint('⚠️ تنبيه Mesh Network: $e');
  }

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
      home: const HomeScreenV9(),
    );
  }
}
