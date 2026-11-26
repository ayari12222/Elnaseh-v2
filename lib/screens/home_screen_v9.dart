import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:torch_light/torch_light.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_player/video_player.dart'; // ✅ مكتبة الفيديو
import 'radar_screen.dart'; 
import '../post_studio_screen.dart'; // ✅ شاشة النشر الخاصة بك

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

  bool _isAdmin = false;
  final String _adminCode = "ELNASEH2026";

  List<Map<String, dynamic>> _allPosts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchPosts(); 
  }

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
          'videoUrl': data['video_url'] ?? '', // ✅ دعم الفيديو
          'topText': data['title'] ?? '',
          'bottomText': data['content'] ?? '',
          'likes': data['likes'] ?? 0,
          'comments': data['comments'] ?? 0,
          'type': data['type'] ?? 'image', // 'image' أو 'video'
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
          onLongPress: _showAdminLoginDialog,
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

          if (_isAdmin)
            Positioned(
              bottom: 30,
              right: 20,
              child: FloatingActionButton(
                backgroundColor: Colors.cyanAccent,
                onPressed: () {
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
          gradient: LinearGradient(
            begin: Alignment.topLeft, 
            end: Alignment.bottomRight, 
            colors: [color.withOpacity(0.6), Colors.black.withOpacity(0.8)]
          ),
          border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.4), 
              blurRadius: 10, 
              spreadRadius: 1, 
              offset: const Offset(0, 4)
            )
          ],
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
          // ✅ 1. عرض الفيديو أو الصورة
          if (post['type'] == 'video' && post['videoUrl'].isNotEmpty)
            _VideoPlayerWidget(videoUrl: post['videoUrl'])
          else if (post['type'] == 'image' && post['image'].isNotEmpty)
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

          // ✅ 2. النصوص
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
                    decoration: BoxDecoration(
                      color: Colors.white, 
                      borderRadius: BorderRadius.circular(8)
                    ),
                    child: Text(
                      post['topText'],
                      style: const TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                
                if (post['bottomText'] != null && post['bottomText'].toString().isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white, 
                      borderRadius: BorderRadius.circular(8)
                    ),
                    child: Text(
                      post['bottomText'],
                      style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),

          // ✅ 3. أزرار التفاعل (إعجاب حقيقي، تعليق، مشاركة)
          Positioned(
            bottom: 20, 
            right: 16,
            child: Column(
              children: [
                // زر الإعجاب (يتحدث مباشرة في Firebase)
                GestureDetector(
                  onTap: () async {
                    try {
                      await FirebaseFirestore.instance.collection('announcements').doc(post['id']).update({
                        'likes': (post['likes'] ?? 0) + 1,
                      });
                      setState(() {
                        final index = _allPosts.indexWhere((p) => p['id'] == post['id']);
                        if (index != -1) {
                          _allPosts[index]['likes'] = (post['likes'] ?? 0) + 1;
                        }
                      });
                    } catch (e) {
                      debugPrint("خطأ في الإعجاب: $e");
                    }
                  },
                  child: _buildActionButton(Icons.favorite, post['likes'].toString(), Colors.white),
                ),
                const SizedBox(height: 16),
                
                // زر التعليق
                _buildActionButton(Icons.comment, post['comments'].toString(), Colors.white),
                const SizedBox(height: 16),
                
                // زر المشاركة
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
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 10,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            icon,
            color: color,
            size: 35,
            shadows: [
              Shadow(color: Colors.black.withOpacity(0.8), blurRadius: 5),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white, 
            fontSize: 13, 
            fontWeight: FontWeight.bold,
            shadows: [Shadow(color: Colors.black, blurRadius: 5)],
          ),
        ),
      ],
    );
  }
}

// ✅ ويدجت تشغيل الفيديو
class _VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  const _VideoPlayerWidget({required this.videoUrl});

  @override
  State<_VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<_VideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        setState(() => _isInitialized = true);
        _controller.setLooping(true);
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _controller.value.size.width,
          height: _controller.value.size.height,
          child: VideoPlayer(_controller),
        ),
      ),
    );
  }
}
