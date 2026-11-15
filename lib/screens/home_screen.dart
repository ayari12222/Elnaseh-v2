import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:torch_light/torch_light.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  bool _isSOSActive = false;
  final AudioPlayer _audioPlayer = AudioPlayer();

  void _toggleSOS() async {
    if (_isSOSActive) {
      await _audioPlayer.stop();
      try { await TorchLight.disableTorch(); } catch (e) {}
      setState(() => _isSOSActive = false);
    } else {
      setState(() => _isSOSActive = true);
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      try {
        await TorchLight.enableTorch();
      } catch (e) {
        print('الفلاش غير متوفر: $e');
      }
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    TorchLight.disableTorch();
    super.dispose();
  }

  final List<Map<String, String>> _posts = [
    {
      'image': 'https://picsum.photos/400/200?random=1',
      'text': 'تقوم استقبال لسنة البرمجة، المافئة الرقب من الموفية البرس، الدينية الحرية والوطنية فتح الناصح.',
      'sender': 'سانت كامين',
      'tag': 'عاجل',
      'tagColor': 'red',
    },
    {
      'image': 'https://picsum.photos/400/200?random=2',
      'text': 'متى استطاعة مدرية، الرصد من السنوات المتبقية في السنوات القادمة، بالضبط مع الجزيرة وتقانتم.',
      'sender': 'سانت كامين',
      'tag': 'معلومات',
      'tagColor': 'blue',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: Text(
          _isSOSActive ? '🚨 وضع الطوارئ نشط 🚨' : 'الناصح',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: _isSOSActive ? Colors.red : Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _posts.length,
        itemBuilder: (context, index) {
          final post = _posts[index];
          return Card(
            color: const Color(0xFF1E1E1E),
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: Image.network(
                    post['image']!,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      height: 200,
                      color: Colors.grey[800],
                      child: const Icon(Icons.image, size: 50, color: Colors.grey),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: post['tagColor'] == 'red' ? Colors.red : Colors.blue,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          post['tag']!,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            post['sender']!,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.verified, color: Colors.blue, size: 16),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        post['text']!,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        backgroundColor: const Color(0xFF1E1E1E),
        selectedItemColor: const Color(0xFF1E88E5),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.campaign), label: 'المنشورات'),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'الدردشة'),
          BottomNavigationBarItem(icon: Icon(Icons.devices), label: 'الأجهزة'),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _toggleSOS,
        backgroundColor: _isSOSActive ? Colors.red : const Color(0xFFD32F2F),
        child: Text(
          _isSOSActive ? 'إيقاف' : 'SOS',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}
