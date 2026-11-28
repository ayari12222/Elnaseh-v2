import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:torch_light/torch_light.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:screenshot/screenshot.dart'; // ✅ لالتقاط الصورة مع النص
import 'dart:io';
import 'dart:typed_data';
import 'radar_screen.dart'; 

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
  
  // متغيرات النشر فوق الصورة
  bool _isPublishing = false;
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _textController = TextEditingController();
  final ScreenshotController _screenshotController = ScreenshotController(); // ✅ أداة التقاط التصميم

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
          'image': data['image_url'] ?? '',
          'topText': data['title'] ?? '',
          'bottomText': data['content'] ?? '',
          'likes': data['likes'] ?? 0,
          'comments': data['comments'] ?? 0,
          'type': data['type'] ?? 'image',
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
      if (mounted) setState(() => _isLoading = false);
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

  Future<void> _toggleSos() async {
    try { HapticFeedback.vibrate(); } catch (e) {}
    if (!_isSosActive) {
      var status = await Permission.camera.status;
      if (!status.isGranted) { status = await Permission.camera.request(); }
      if (status.isGranted) {
        try { await TorchLight.enableTorch(); } catch (e) {}
        try { await _audioPlayer.play(UrlSource('https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3')); } catch (e) {}
        setState(() => _isSosActive = true);
      }
    } else {
      try { await TorchLight.disableTorch(); } catch (e) {}
      try { await _audioPlayer.stop(); } catch (e) {}
      setState(() => _isSosActive = false);
    }
  }

  // 🛑 دالة اختيار الصورة
  Future<void> _pickImageToPublish() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
        _isPublishing = true;
        _textController.clear(); 
      });
    }
  }

  // 🛑 دالة النشر (تأخذ لقطة للصورة مع النص وترفعها)
  Future<void> _publishPost() async {
    if (_selectedImage == null) return;
    setState(() => _isLoading = true);
    
    try {
      // 1. أخذ لقطة للشاشة (الصورة + النص)
      final Uint8List? imageBytes = await _screenshotController.capture();
      if (imageBytes == null) throw Exception('فشل التقاط التصميم');

      // 2. رفع الصورة النهائية
      String imageUrl = '';
      final ref = FirebaseStorage.instance.ref().child('announcements/${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putData(imageBytes);
      imageUrl = await ref.getDownloadURL();

      // 3. حفظ المنشور في Firebase
      await FirebaseFirestore.instance.collection('announcements').add({
        'title': '', 
        'content': '', // لا نحتاج نص هنا لأننا أخذنا الصورة كاملة
        'image_url': imageUrl,
        'likes': 0,
        'comments': 0,
        'created_at': FieldValue.serverTimestamp(),
        'type': 'image',
        'tag': 'الكل',
      });

      setState(() {
        _selectedImage = null;
        _isPublishing = false;
      });
      
      await _fetchPosts(); 
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ تم النشر!'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: _isPublishing ? Colors.transparent : const Color(0xFF1E1E1E),
        elevation: 0,
        leading: _isPublishing 
            ? IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => setState(() { _isPublishing = false; _selectedImage = null; }))
            : PopupMenuButton<String>(
                icon: const Icon(Icons.menu, color: Colors.white),
                onSelected: (String value) => setState(() => _selectedCategory = value),
                itemBuilder: (context) => _categories.map((String category) {
                  return PopupMenuItem<String>(value: category, child: Text(category));
                }).toList(),
              ),
        title: _isPublishing 
            ? null 
            : GestureDetector(
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
        actions: _isPublishing 
            ? [
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.cyanAccent, size: 30),
                  onPressed: _isLoading ? null : _publishPost,
                )
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: () { setState(() => _isLoading = true); _fetchPosts(); }, 
                ),
              ],
      ),
      bottomNavigationBar: _isPublishing ? null : BottomNavigationBar(
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
      body: _isPublishing ? _buildPublishingView() : _buildMainView(),
    );
  }

  // 🛑 واجهة النشر: الصورة مع الكتابة فوقها مباشرة (بدون صندوق)
  Widget _buildPublishingView() {
    return Screenshot(
      controller: _screenshotController,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // الصورة تملأ الشاشة
          if (_selectedImage != null)
            Image.file(_selectedImage!, fit: BoxFit.cover)
          else
            Container(color: Colors.black),

          // الكتابة فوق الصورة مباشرة (نص شفاف يطفو فوق الصورة)
          Positioned(
            top: 100, left: 16, right: 16,
            child: TextField(
              controller: _textController,
              maxLines: null,
              style: const TextStyle(
                color: Colors.white, // لون النص أبيض ليظهر فوق الصورة
                fontSize: 24, 
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(color: Colors.black, blurRadius: 10, offset: Offset(0, 2)) // ظل ليظهر النص فوق أي صورة
                ]
              ),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                hintText: 'اكتب هنا...',
                hintStyle: TextStyle(color: Colors.white70, fontSize: 20),
                border: InputBorder.none, // لا يوجد إطار
              ),
            ),
          ),

          // زر تغيير الصورة
          Positioned(
            bottom: 30, left: 20, right: 20,
            child: ElevatedButton.icon(
              onPressed: _pickImageToPublish,
              icon: const Icon(Icons.image),
              label: const Text('تغيير الصورة'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }

  // 🛑 واجهة العرض الرئيسية
  Widget _buildMainView() {
    return Stack(
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
              child: Container(
                width: 70, height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: _isSosActive ? [Colors.greenAccent, Colors.green] : [Colors.redAccent, const Color(0xFFB71C1C)],
                  ),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: Text(
                    _isSosActive ? 'إيقاف' : 'SOS',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20),
                  ),
                ),
              ),
            ),
          ),
        ),

        if (_isAdmin)
          Positioned(
            bottom: 30, right: 20,
            child: FloatingActionButton(
              backgroundColor: Colors.cyanAccent,
              onPressed: _pickImageToPublish, 
              child: const Icon(Icons.add, color: Colors.black, size: 30),
            ),
          ),
      ],
    );
  }

  Widget _buildCircleIcon(IconData icon, Color color, VoidCallback onPressed) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [color.withOpacity(0.6), Colors.black.withOpacity(0.8)]),
          border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
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
            Image.network(post['image'], fit: BoxFit.cover)
          else
            Container(color: Colors.black),

          // أزرار التفاعل (إعجاب، تعليق، مشاركة)
          Positioned(
            bottom: 20, right: 16,
            child: Column(
              children: [
                GestureDetector(
                  onTap: () async {
                    try {
                      await FirebaseFirestore.instance.collection('announcements').doc(post['id']).update({
                        'likes': (post['likes'] ?? 0) + 1,
                      });
                      setState(() {
                        final index = _allPosts.indexWhere((p) => p['id'] == post['id']);
                        if (index != -1) _allPosts[index]['likes'] = (post['likes'] ?? 0) + 1;
                      });
                    } catch (e) {
                      debugPrint("خطأ في الإعجاب: $e");
                    }
                  },
                  child: _buildActionButton(Icons.favorite, post['likes'].toString(), Colors.white),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('التعليقات قيد التطوير...')));
                  },
                  child: _buildActionButton(Icons.comment, post['comments'].toString(), Colors.white),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => Share.share('شاهد هذا المنشور على تطبيق الناصح!'),
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
        Icon(icon, color: color, size: 35, shadows: [Shadow(color: Colors.black.withOpacity(0.8), blurRadius: 5)]),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black, blurRadius: 5)])),
      ],
    );
  }
}
