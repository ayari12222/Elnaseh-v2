import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:torch_light/torch_light.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  final ImagePicker _picker = ImagePicker();

  // قائمة المنشورات المحلية
  List<Map<String, dynamic>> _posts = [];

  @override
  void initState() {
    super.initState();
    _loadPosts(); // تحميل المنشورات المحفوظة عند فتح التطبيق
  }

  // دالة تحميل المنشورات من ذاكرة الهاتف
  Future<void> _loadPosts() async {
    final prefs = await SharedPreferences.getInstance();
    final String? postsString = prefs.getString('local_posts');
    if (postsString != null) {
      final List<dynamic> decoded = jsonDecode(postsString);
      setState(() {
        _posts = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      });
    }
  }

  // دالة حفظ المنشورات في ذاكرة الهاتف
  Future<void> _savePosts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('local_posts', jsonEncode(_posts));
  }

  // دالة إضافة منشور جديد
  Future<void> _addNewPost() async {
    final TextEditingController textController = TextEditingController();
    File? selectedImage;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              title: const Text('إضافة منشور جديد', style: TextStyle(color: Colors.white)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () async {
                        final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
                        if (image != null) {
                          setDialogState(() => selectedImage = File(image.path));
                        }
                      },
                      child: Container(
                        height: 100,
                        width: double.infinity,
                        color: Colors.black26,
                        child: selectedImage == null
                            ? const Icon(Icons.add_photo_alternate, color: Colors.cyanAccent, size: 50)
                            : Image.file(selectedImage!, fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: textController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'اكتب النص هنا...',
                        hintStyle: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (textController.text.isNotEmpty) {
                      setState(() {
                        _posts.insert(0, {
                          'text': textController.text,
                          'sender': 'الناصح الرسمي',
                          'tag': 'عاجل',
                          'tagColor': 'red',
                          'likes': 0,
                          'comments': 0,
                          'imagePath': selectedImage?.path,
                          'type': selectedImage != null ? 'image' : 'text',
                        });
                      });
                      await _savePosts(); // حفظ في الهاتف
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                  child: const Text('نشر'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<Map<String, dynamic>> get _filteredPosts {
    if (_selectedCategory == 'الكل') return _posts;
    return _posts.where((post) => post['tag'] == _selectedCategory).toList();
  }

  // ... (دوال SOS والرادار تبقى كما هي) ...

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
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildCircleIcon(Icons.shield, Colors.blueAccent, () {}),
            const SizedBox(width: 8),
            _buildCircleIcon(Icons.warning, Colors.redAccent, _toggleSos),
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
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle, color: Colors.cyanAccent, size: 30),
            onPressed: _addNewPost, // زر الإضافة الجديد
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
          _filteredPosts.isEmpty
              ? const Center(child: Text('لا توجد منشورات بعد. اضغط + للإضافة.', style: TextStyle(color: Colors.white)))
              : PageView.builder(
                  controller: _pageController,
                  scrollDirection: Axis.vertical,
                  itemCount: _filteredPosts.length,
                  itemBuilder: (context, index) {
                    final post = _filteredPosts[index];
                    return _buildPost(post);
                  },
                ),
          Positioned(
            left: 20,
            top: 0,
            bottom: 0,
            child: Center(
              child: FloatingActionButton(
                onPressed: _toggleSos,
                backgroundColor: _isSosActive ? Colors.green : const Color(0xFFD32F2F),
                elevation: 10,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: _isSosActive ? [Colors.greenAccent, Colors.green] : [Colors.redAccent, const Color(0xFFB71C1C)],
                      center: Alignment.center,
                      radius: 0.8,
                    ),
                    boxShadow: [
                      BoxShadow(color: _isSosActive ? Colors.green.withOpacity(0.6) : Colors.red.withOpacity(0.6), blurRadius: 20, spreadRadius: 5),
                    ],
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
        ],
      ),
    );
  }

  // دالة SOS (مبسطة للاختصار، تأكد من وجودها كاملة في ملفك)
  Future<void> _toggleSos() async {
    try { HapticFeedback.vibrate(); } catch (e) { debugPrint("$e"); }
    if (!_isSosActive) {
      try { await TorchLight.enableTorch(); } catch (e) { debugPrint("$e"); }
      try { await _audioPlayer.play(UrlSource('https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3')); } catch (e) { debugPrint("$e"); }
      setState(() => _isSosActive = true);
    } else {
      try { await TorchLight.disableTorch(); } catch (e) { debugPrint("$e"); }
      try { await _audioPlayer.stop(); } catch (e) { debugPrint("$e"); }
      setState(() => _isSosActive = false);
    }
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
    return Stack(
      fit: StackFit.expand,
      children: [
        if (post['type'] == 'image' && post['imagePath'] != null)
          Image.file(File(post['imagePath']), fit: BoxFit.cover)
        else
          Container(color: Colors.black),

        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.center, colors: [Colors.black.withOpacity(0.8), Colors.transparent]),
          ),
        ),

        Positioned(
          bottom: 20,
          left: 16,
          right: 80,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                child: Text(post['tag'] ?? 'عام', style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(post['sender'] ?? 'مجهول', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(width: 4),
                  const Icon(Icons.verified, color: Colors.blue, size: 20),
                ],
              ),
              const SizedBox(height: 8),
              Text(post['text'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
        ),

        Positioned(
          bottom: 20,
          right: 16,
          child: Column(
            children: [
              _buildActionButton(Icons.favorite, (post['likes'] ?? 0).toString(), Colors.red),
              const SizedBox(height: 16),
              _buildActionButton(Icons.comment, (post['comments'] ?? 0).toString(), Colors.white),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => Share.share(post['text'] ?? ''),
                child: _buildActionButton(Icons.share, 'مشاركة', Colors.white),
              ),
            ],
          ),
        ),
      ],
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
