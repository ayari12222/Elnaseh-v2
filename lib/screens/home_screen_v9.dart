import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:torch_light/torch_light.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'radar_screen.dart'; 
import 'post_studio_screen.dart'; // ✅ استيراد استوديو النشر الجديد

class HomeScreenV9 extends StatefulWidget {
  const HomeScreenV9({super.key});

  @override
  State<HomeScreenV9> createState() => _HomeScreenV9State();
}

class _HomeScreenV9State extends State<HomeScreenV9> {
  int _currentIndex = 0;
  String _selectedCategory = 'الكل';
  final List<String> _categories = ['الكل', 'عاجل', 'معلومات', 'تحذير'];
  final PageController _pageController = PageController();
  
  bool _isSosActive = false;
  final AudioPlayer _audioPlayer = AudioPlayer();

  // ✅ متغيرات التحكم بالصلاحيات
  bool _isAdmin = false;
  final String _adminCode = "ELNASEH2026"; // الرمز السري للناشرين

  List<Map<String, dynamic>> _allPosts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchPosts(); 
  }

  // دالة جلب المنشورات
  Future<void> _fetchPosts() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('announcements')
          .orderBy('created_at', descending: true)
          .get();

      final fetchedPosts = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'image': data['image_url'] ?? 'https://images.unsplash.com/photo-1582213782179-e0d53f98f2ca?w=800',
          'topText': data['title'] ?? '',
          'bottomText': data['content'] ?? '',
          'likes': data['likes'] ?? 0,
          'comments': data['comments'] ?? 0,
          'type': 'image',
          'tag': data['tag'] ?? 'الكل',
        };
      }).toList();

      if (mounted) {
        setState(() {
          _allPosts = fetchedPosts;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching posts: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تحميل المنشورات: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ✅ دالة دخول الناشرين
  void _showAdminLoginDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('🔐 دخول الناشرين', style: TextStyle(color: Colors.cyanAccent)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'أدخل الرمز السري'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim() == _adminCode) {
                setState(() => _isAdmin = true);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('✅ تم تفعيل وضع النشر!'), backgroundColor: Colors.green),
                );
              } else {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('❌ رمز خاطئ!'), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('دخول'),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredPosts {
    if (_selectedCategory == 'الكل') return _allPosts;
    return _allPosts.where((post) => post['tag'] == _selectedCategory).toList();
  }

  Future<bool> _showPermissionDialog() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Row(
          children: [
            Icon(Icons.flash_on, color: Colors.amber, size: 30),
            SizedBox(width: 10),
            Text('تفعيل الفلاش للطوارئ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'لتشغيل الفلاش تلقائياً في حالات الطوارئ، يرجى السماح للتطبيق بالوصول إلى الكاميرا.',
          style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('لاحقاً', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('السماح', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<void> _toggleSos() async {
    try { HapticFeedback.vibrate(); } catch (e) {}

    if (!_isSosActive) {
      var status = await Permission.camera.status;
      if (!status.isGranted) {
        bool? userWantsPermission = await _showPermissionDialog();
        if (userWantsPermission == true) {
          status = await Permission.camera.request();
        } else {
          return;
        }
      }

      if (status.isGranted) {
        try { await TorchLight.enableTorch(); } catch (e) {}
        try { await _audioPlayer.play(UrlSource('https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3')); } catch (e) {}
        setState(() => _isSosActive = true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم رفض إذن الكاميرا.'), backgroundColor: Colors.redAccent),
        );
      }
    } else {
      try { await TorchLight.disableTorch(); } catch (e) {}
      try { await _audioPlayer.stop(); } catch (e) {}
      setState(() => _isSosActive = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        leading: PopupMenuButton<String>(
          icon: const Icon(Icons.menu, color: Colors.white),
          onSelected: (String value) => setState(() => _selectedCategory = value),
          itemBuilder: (context) => _categories.map((String category) {
            return PopupMenuItem<String>(value: category, child: Text(category));
          }).toList(),
        ),
        title: GestureDetector(
          onLongPress: _showAdminLoginDialog, // ✅ الضغط المطول يفتح نافذة الدخول
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildCircleIcon(Icons.shield, Colors.blueAccent, () {}),
              const SizedBox(width: 8),
              _buildCircleIcon(Icons.warning, Colors.redAccent, () { _toggleSos(); }),
              const SizedBox(width: 8),
              _buildCircleIcon(Icons.radar, Colors.white, () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const RadarScreen()));
              }),
              const SizedBox(width: 8),
              _buildCircleIcon(FontAwesomeIcons.bluetoothB, Colors.blue, () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('البلوتوث قيد التطوير...')));
              }),
              const SizedBox(width: 8),
              _buildCircleIcon(Icons.notifications, Colors.white, () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الإشعارات قيد التطوير...')));
              }),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
               setState(() => _isLoading = true);
               _fetchPosts();
            }, 
          ),
        ],
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
      body: Stack(
        children: [
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
          else if (_filteredPosts.isEmpty)
            const Center(child: Text('لا توجد منشورات حالياً', style: TextStyle(color: Colors.white, fontSize: 18)))
          else
            PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              itemCount: _filteredPosts.length,
              itemBuilder: (context, index) => _buildPost(_filteredPosts[index]),
            ),
          
          Positioned(
            left: 20, top: 0, bottom: 0,
            child: Center(
              child: FloatingActionButton(
                onPressed: _toggleSos,
                backgroundColor: _isSosActive ? Colors.green : const Color(0xFFD32F2F),
                elevation: 10,
                child: Container(
                  width: 70, height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: _isSosActive ? [Colors.greenAccent, Colors.green] : [Colors.redAccent, const Color(0xFFB71C1C)],
                      center: Alignment.center, radius: 0.8,
                    ),
                    boxShadow: [BoxShadow(color: _isSosActive ? Colors.green.withOpacity(0.6) : Colors.red.withOpacity(0.6), blurRadius: 20, spreadRadius: 5)],
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      _isSosActive ? 'إيقاف' : 'SOS',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20, letterSpacing: 1.5),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ✅ زر النشر (+) يظهر فقط للمدير
          if (_isAdmin)
            Positioned(
              bottom: 30,
              right: 20,
              child: FloatingActionButton(
                backgroundColor: Colors.cyanAccent,
                onPressed: () {
                  // ✅ الانتقال المباشر لاستوديو النشر
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const PostStudioScreen()));
                },
                child: const Icon(Icons.add, color: Colors.black, size: 30),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCircleIcon(IconData icon, Color color, VoidCallback onPressed) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color.withOpacity(0.6), Colors.black.withOpacity(0.8)]),
          border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
          boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 10, spreadRadius: 1, offset: const Offset(0, 4))],
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _buildPost(Map<String, dynamic> post) {
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (post['type'] == 'image' && post['image'].isNotEmpty)
            Image.network(
              post['image'], 
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: Colors.black,
                child: const Center(child: Icon(Icons.image, size: 80, color: Colors.grey)),
              ),
            )
          else
            Container(color: Colors.black),

          Positioned(
            top: 60, 
            left: 16,
            right: 80, 
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (post['topText'] != null && post['topText'].toString().isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      post['topText'],
                      style: const TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                
                if (post['bottomText'] != null && post['bottomText'].toString().isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      post['bottomText'],
                      style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),

          Positioned(
            bottom: 20, 
            right: 16,
            child: Column(
              children: [
                _buildActionButton(Icons.favorite, post['likes'].toString(), Colors.white),
                const SizedBox(height: 16),
                _buildActionButton(Icons.comment, post['comments'].toString(), Colors.white),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => Share.share(post['topText'] ?? ''),
                  child: _buildActionButton(Icons.share, 'مشاركة', Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }
}
