import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:torch_light/torch_light.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'radar_screen.dart';
import 'upload_screen.dart'; // استوديو النشر

class HomeScreenV9 extends StatefulWidget {
  const HomeScreenV9({super.key});
  @override
  State<HomeScreenV9> createState() => _HomeScreenV9State();
}

class _HomeScreenV9State extends State<HomeScreenV9> {
  int _currentIndex = 0;
  String _selectedCategory = 'الكل';
  final PageController _pageController = PageController();
  bool _isSosActive = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<String> _dynamicCategories = ['الكل'];
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _fetchCategories();
    _checkAdminStatus();
  }

  Future<void> _checkAdminStatus() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      DocumentSnapshot doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists && doc.get('role') == 'admin') setState(() => _isAdmin = true);
    }
  }

  Future<void> _fetchCategories() async {
    try {
      QuerySnapshot snapshot = await _firestore.collection('categories').orderBy('createdAt').get();
      List<String> fetchedCats = ['الكل'];
      for (var doc in snapshot.docs) fetchedCats.add(doc['name']);
      setState(() => _dynamicCategories = fetchedCats);
    } catch (e) { print("Error: $e"); }
  }

  Future<void> _toggleSos() async {
    if (!_isSosActive) {
      try { await TorchLight.enableTorch(); } catch (e) {}
      try { await _audioPlayer.play(UrlSource('https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3')); } catch (e) {}
      setState(() => _isSosActive = true);
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
        leading: PopupMenuButton<String>(
          icon: const Icon(Icons.menu, color: Colors.white),
          onSelected: (value) => setState(() => _selectedCategory = value),
          itemBuilder: (context) => _dynamicCategories.map((cat) => PopupMenuItem(value: cat, child: Text(cat))).toList(),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildCircleIcon(Icons.shield, Colors.blueAccent, () {}),
            _buildCircleIcon(Icons.warning, Colors.redAccent, _toggleSos),
            _buildCircleIcon(Icons.radar, Colors.white, () { Navigator.push(context, MaterialPageRoute(builder: (context) => const RadarScreen())); }),
            _buildCircleIcon(FontAwesomeIcons.bluetoothB, Colors.blue, () {}),
            _buildCircleIcon(Icons.notifications, Colors.white, () {}),
          ],
        ),
        actions: [
          if (_isAdmin) IconButton(icon: const Icon(Icons.add_circle, color: Colors.cyanAccent, size: 30), onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (context) => const UploadScreen())); }),
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
          // 🔴 تم التعديل هنا: البحث في مجموعة announcements
          StreamBuilder<QuerySnapshot>(
            stream: _selectedCategory == 'الكل'
                ? _firestore.collection('announcements').orderBy('createdAt', descending: true).snapshots()
                : _firestore.collection('announcements').where('tag', isEqualTo: _selectedCategory).orderBy('createdAt', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.cyanAccent));
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('لا توجد منشورات', style: TextStyle(color: Colors.white)));
              var posts = snapshot.data!.docs;
              return PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                itemCount: posts.length,
                itemBuilder: (context, index) => _buildPost(posts[index].data() as Map<String, dynamic>),
              );
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
                child: Container(
                  width: 70, height: 70,
                  decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: _isSosActive ? [Colors.greenAccent, Colors.green] : [Colors.redAccent, const Color(0xFFB71C1C)])),
                  child: Center(child: Text(_isSosActive ? 'إيقاف' : 'SOS', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20))),
                ),
              ),
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
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [color.withOpacity(0.6), Colors.black.withOpacity(0.8)]), border: Border.all(color: Colors.white.withOpacity(0.3))),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _buildPost(Map<String, dynamic> post) {
    // 🔴 تم التعديل هنا: استخدام أسماء الحقول من Firebase (content و image_url)
    return Stack(
      fit: StackFit.expand,
      children: [
        if (post['image_url'] != null && post['image_url'] != '')
          Image.network(post['image_url'], fit: BoxFit.cover)
        else
          Container(color: Colors.black),
        Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.center, colors: [Colors.black.withOpacity(0.8), Colors.transparent]))),
        Positioned(
          bottom: 20, left: 16, right: 80,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)), child: Text(post['tag'] ?? 'عام', style: const TextStyle(color: Colors.white, fontSize: 12))),
              const SizedBox(height: 8),
              Text(post['title'] ?? 'الناصح الرسمي', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 8),
              Text(post['content'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
        ),
        Positioned(
          bottom: 20, right: 16,
          child: Column(
            children: [
              _buildActionButton(Icons.favorite, (post['likes'] ?? 0).toString(), Colors.red),
              const SizedBox(height: 16),
              _buildActionButton(Icons.comment, (post['comments'] ?? 0).toString(), Colors.white),
              const SizedBox(height: 16),
              GestureDetector(onTap: () => Share.share(post['content'] ?? ''), child: _buildActionButton(Icons.share, 'مشاركة', Colors.white)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(IconData icon, String label, Color color) {
    return Column(children: [Icon(icon, color: color, size: 32), const SizedBox(height: 4), Text(label, style: const TextStyle(color: Colors.white, fontSize: 12))]);
  }
}
