import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart'; // ✅ تفعيل Firebase
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_mesh_network/flutter_mesh_network.dart';
import 'screens/home_screen_v9.dart';

// متغير عام للوصول إلى شبكة Mesh من أي مكان في التطبيق
late final MeshNetwork meshNetwork;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ 1. تهيئة Firebase (يجب أن تكون قبل runApp)
  await Firebase.initializeApp();

  // 2. تهيئة Supabase (للدردشة والمواقع)
  // ⚠️ استبدل الرابط والمفتاح بالقيم الحقيقية من لوحة تحكم Supabase
  await Supabase.initialize(
    url: 'YOUR_SUPABASE_URL',
    anonKey: 'YOUR_SUPABASE_ANON_KEY',
  );

  // 3. تهيئة شبكة Mesh (روح التطبيق - SOS)
  meshNetwork = MeshNetwork(
    config: const MeshConfig(serviceName: 'elnaseh-sos'),
  );

  // بدء الشبكة (سنستخدم معرفاً مؤقتاً للتجربة)
  await meshNetwork.start(
    userId: 'user_${DateTime.now().millisecondsSinceEpoch}',
    userName: 'مستخدم_${DateTime.now().millisecondsSinceEpoch % 1000}',
  );

  // 4. الاستماع للرسائل الواردة (لميزة SOS)
  meshNetwork.onMessage.listen((msg) {
    debugPrint('📩 رسالة من ${msg.senderName}: ${msg.payload}');
    // لاحقاً: سنضيف إشعاراً هنا عندما تكون الرسالة من نوع SOS
  });

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
