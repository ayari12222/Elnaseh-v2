import 'package:flutter/material.dart';
// import 'package:firebase_core/firebase_core.dart'; // ✅ معطل مؤقتاً
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_mesh_network/flutter_mesh_network.dart';
import 'screens/home_screen_v9.dart';

late final MeshNetwork meshNetwork;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ تم تعطيل Firebase مؤقتاً
  // await Firebase.initializeApp();

  await Supabase.initialize(
    url: 'YOUR_SUPABASE_URL',
    anonKey: 'YOUR_SUPABASE_ANON_KEY',
  );

  meshNetwork = MeshNetwork(
    config: const MeshConfig(serviceName: 'elnaseh-sos'),
  );

  await meshNetwork.start(
    userId: 'user_${DateTime.now().millisecondsSinceEpoch}',
    userName: 'مستخدم_${DateTime.now().millisecondsSinceEpoch % 1000}',
  );

  meshNetwork.onMessage.listen((msg) {
    debugPrint('📩 رسالة من ${msg.senderName}: ${msg.payload}');
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
