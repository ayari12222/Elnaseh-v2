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
import '../upload_screen.dart';
import 'login_screen.dart'; // لضمان العودة عند تسجيل الخروج

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

  final FirebaseAuth _auth = FirebaseAuth.instance;
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
    User? user = _auth.currentUser;
    if (user != null) {
      DocumentSnapshot doc =
          await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists && doc.get('role') == 'admin') {
        setState(() => _isAdmin = true);
      }
    }
  }

  Future<void> _fetchCategories() async {
    try {
      QuerySnapshot snapshot =
          await _firestore.collection('categories').orderBy('createdAt').get();
      List<String> fetchedCats = ['الكل'];
      for (var doc in snapshot.docs) {
        fetchedCats.add(doc['name']);
      }
      setState(() {
        _dynamicCategories = fetchedCats;
      });
    } catch (e) {
      print("خطأ في جلب التصنيفات: $e");
    }
  }

  // --- دوال SOS ---
  Future<bool> _showPermissionDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: const Row(
              children: [
                Icon(Icons.flash_on, color: Colors.amber, size: 30),
                SizedBox(width: 10),
                Text('تفعيل الفلاش للطوارئ',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
            content: const Text(
              'لتشغيل الفلاش تلقائياً في حالات الطوارئ، يرجى السماح للتطبيق بالوصول إلى الكاميرا.\n\n'
              'هذا الإذن يُطلب مرة واحدة فقط ولن يتم استخدامه إلا لتشغيل الفلاش.',
              style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child:
                    const Text('لاحقاً', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () => Navigator.pop(context, true),
                child:
                    const Text('السماح', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _toggleSos() async {
    try {
      HapticFeedback.vibrate();
    } catch (e) {
      debugPrint("$e");
    }

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
        try {
          await TorchLight.enableTorch();
        } catch (e) {
          debugPrint("$e");
        }
        try {
          await _audioPlayer.play(UrlSource(
              'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3'));
        } catch (e) {
          debugPrint("$e");
        }
        setState(() => _isSosActive = true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تم رفض إذن الكاميرا. لا يمكن تشغيل الفلاش.'),
              backgroundColor: Colors.redAccent),
        );
      }
    } else {
      try {
        await TorchLight.disableTorch();
      } catch (e) {
        debugPrint("$e");
      }
      try {
        await _audioPlayer.stop();
      } catch (e) {
        debugPrint("$e");
      }
      try {
        HapticFeedback.vibrate();
      } catch (e) {
        debugPrint("$e");
      }
      setState(() => _isSosActive = false);
    }
  }

  // --- واجهة إدارة الناشرين ---
  Future<void> _showAddPublisherDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('إضافة ناشر جديد',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'البريد الإلكتروني للناشر',
            hintStyle: TextStyle(color: Colors.grey),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('إضافة')),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        // البحث عن المستخدم بالبريد الإلكتروني في Firestore
        QuerySnapshot query = await _firestore
            .collection('users')
            .where('email', isEqualTo: result)
            .get();

        if (query.docs.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('المستخدم غير موجود. يجب أن يسجل أولاً.'),
                backgroundColor: Colors.red));
          }
          return;
        }

        // تحديث دور المستخدم إلى مدير (ناشر)
        String uid = query.docs.first.id;
        await _firestore.collection('users').doc(uid).update({'role': 'admin'});

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('✅ تمت إضافة الناشر بنجاح'),
              backgroundColor: Colors.green));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('❌ فشل: $e'), backgroundColor: Colors.red));
        }
      }
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
          onSelected: (String value) {
            if (value == 'ADD_NEW') {
              _showAddCategoryDialog();
            } else if (value == 'MANAGE_PUBLISHERS') {
              _showAddPublisherDialog(); // فتح نافذة إضافة ناشر
            } else if (value == 'LOGOUT') {
              _auth.signOut();
              Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const LoginScreen()));
            } else {
              setState(() => _selectedCategory = value);
            }
          },
          itemBuilder: (context) {
            List<PopupMenuEntry<String>> items =
                _dynamicCategories.map((String category) {
              return PopupMenuItem<String>(value: category, child: Text(category));
            }).toList();

            if (_isAdmin) {
              items.add(const PopupMenuDivider());
              items.add(
                const PopupMenuItem<String>(
                  value: 'ADD_NEW',
                  child: Row(
                    children: [
                      Icon(Icons.add, color: Colors.greenAccent),
                      SizedBox(width: 8),
                      Text('إضافة تصنيف جديد',
                          style: TextStyle(color: Colors.greenAccent)),
                    ],
                  ),
                ),
              );
              items.add(
                const PopupMenuItem<String>(
                  value: 'MANAGE_PUBLISHERS',
                  child: Row(
                    children: [
                      Icon(Icons.person_add, color: Colors.blueAccent),
                      SizedBox(width: 8),
                      Text('إدارة الناشرين',
                          style: TextStyle(color: Colors.blueAccent)),
                    ],
                  ),
                ),
              );
              items.add(const PopupMenuDivider());
              items.add(
                const PopupMenuItem<String>(
                  value: 'LOGOUT',
                  child: Row(
                    children: [
                      Icon(Icons.logout, color: Colors.redAccent),
                      SizedBox(width: 8),
                      Text('تسجيل الخروج',
                          style: TextStyle(color: Colors.redAccent)),
                    ],
                  ),
                ),
              );
            }
            return items;
          },
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildCircleIcon(Icons.shield, Colors.blueAccent, () {}),
            const SizedBox(width: 8),
            _buildCircleIcon(Icons.warning, Colors.redAccent, _toggleSos),
            const SizedBox(width: 8),
            _buildCircleIcon(Icons.radar, Colors.white, () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (context) => const RadarScreen()));
            }),
            const SizedBox(width: 8),
            _buildCircleIcon(FontAwesomeIcons.bluetoothB, Colors.blue, () {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('البلوتوث قيد التطوير...')));
            }),
            const SizedBox(width: 8),
            _buildCircleIcon(Icons.notifications, Colors.white, () {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('الإشعارات قيد التطوير...')));
            }),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (String value) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$value قيد التطوير...')));
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'الإعدادات', child: Text('الإعدادات')),
              PopupMenuItem(value: 'حول التطبيق', child: Text('حول التطبيق')),
              PopupMenuItem(value: 'مساعدة', child: Text('مساعدة')),
            ],
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
          StreamBuilder<QuerySnapshot>(
            stream: _selectedCategory == 'الكل'
                ? _firestore
                    .collection('posts')
                    .orderBy('createdAt', descending: true)
                    .snapshots()
                : _firestore
                    .collection('posts')
                    .where('tag', isEqualTo: _selectedCategory)
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: Colors.cyanAccent));
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(
                    child: Text('لا توجد منشورات حالياً',
                        style: TextStyle(color: Colors.white)));
              }
              var posts = snapshot.data!.docs;
              return PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                itemCount: posts.length,
                itemBuilder: (context, index) {
                  var post = posts[index].data() as Map<String, dynamic>;
                  return _buildPost(post);
                },
              );
            },
          ),
          if (_isAdmin)
            Positioned(
              top: 20,
              right: 20,
              child: FloatingActionButton(
                mini: true,
                backgroundColor: Colors.blueAccent,
                onPressed: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => UploadScreen()));
                },
                child: const Icon(Icons.add, color: Colors.white),
              ),
            ),
          Positioned(
            left: 20,
            top: 0,
            bottom: 0,
            child: Center(
              child: FloatingActionButton(
                onPressed: _toggleSos,
                backgroundColor:
                    _isSosActive ? Colors.green : const Color(0xFFD32F2F),
                elevation: 10,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: _isSosActive
                          ? [Colors.greenAccent, Colors.green]
                          : [Colors.redAccent, const Color(0xFFB71C1C)],
                      center: Alignment.center,
                      radius: 0.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: _isSosActive
                              ? Colors.green.withOpacity(0.6)
                              : Colors.red.withOpacity(0.6),
                          blurRadius: 20,
                          spreadRadius: 5),
                    ],
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      _isSosActive ? 'إيقاف' : 'SOS',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 20,
                          letterSpacing: 1.5),
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

  Future<void> _showAddCategoryDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('إضافة تصنيف جديد',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'اسم التصنيف (مثلاً: طقس، إخلاء)',
            hintStyle: TextStyle(color: Colors.grey),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('إضافة')),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        await _firestore.collection('categories').add({
          'name': result,
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': _auth.currentUser?.uid,
        });
        _fetchCategories();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('تم إضافة التصنيف: $result')));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('فشل الإضافة: $e'), backgroundColor: Colors.red));
      }
    }
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
            colors: [color.withOpacity(0.6), Colors.black.withOpacity(0.8)],
          ),
          border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 10,
                spreadRadius: 1,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _buildPost(Map<String, dynamic> post) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (post['imageUrl'] != null)
          Image.network(
            post['imageUrl'],
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              color: Colors.black,
              child: const Center(
                  child: Icon(Icons.image, size: 80, color: Colors.grey)),
            ),
          )
        else
          Container(color: Colors.black),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.center,
              colors: [Colors.black.withOpacity(0.8), Colors.transparent],
            ),
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
                decoration: BoxDecoration(
                  color: post['tag'] == 'عاجل'
                      ? Colors.red
                      : (post['tag'] == 'معلومات' ? Colors.blue : Colors.orange),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(post['tag'] ?? 'عام',
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(post['sender'] ?? 'مجهول',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18)),
                  const SizedBox(width: 4),
                  const Icon(Icons.verified, color: Colors.blue, size: 20),
                ],
              ),
              const SizedBox(height: 8),
              Text(post['text'] ?? '',
                  style: const TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
        ),
        Positioned(
          bottom: 20,
          right: 16,
          child: Column(
            children: [
              _buildActionButton(
                  Icons.favorite, (post['likes'] ?? 0).toString(), Colors.red),
              const SizedBox(height: 16),
              _buildActionButton(Icons.comment,
                  (post['comments'] ?? 0).toString(), Colors.white),
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
