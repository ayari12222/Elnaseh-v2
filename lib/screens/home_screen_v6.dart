import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart'; // المكتبة التي تعمل
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class HomeScreenV6 extends StatefulWidget {
  const HomeScreenV6({super.key});

  @override
  State<HomeScreenV6> createState() => _HomeScreenV6State();
}

class _HomeScreenV6State extends State<HomeScreenV6> {
  int _currentIndex = 0;
  String _selectedCategory = 'الكل';
  final List<String> _categories = ['الكل', 'عاجل', 'معلومات', 'تحذير'];
  final PageController _pageController = PageController();

  final List<Map<String, dynamic>> _allPosts = [
    {
      'image': 'https://images.unsplash.com/photo-1582213782179-e0d53f98f2ca?w=800',
      'text': 'تحذير: زلزال بقوة 6.5 درجة يضرب المنطقة. يرجى التوجه إلى المناطق المفتوحة.',
      'sender': 'الدفاع المدني',
      'tag': 'عاجل',
      'tagColor': 'red',
      'likes': 1250,
      'comments': 45,
      'type': 'image',
    },
    {
      'image': 'https://images.unsplash.com/photo-1547683905-f686c993aae5?w=800',
      'text': 'إرشادات السلامة: حافظ على الهدوء، وابتعد عن النوافذ والأجسام المتساقطة.',
      'sender': 'الهلال الأحمر',
      'tag': 'معلومات',
      'tagColor': 'blue',
      'likes': 890,
      'comments': 12,
      'type': 'image',
    },
    {
      'image': '',
      'text': 'تنبيه: سيتم قطع المياه عن المنطقة الشرقية لمدة 3 ساعات.',
      'sender': 'شركة المياه',
      'tag': 'تحذير',
      'tagColor': 'orange',
      'likes': 340,
      'comments': 5,
      'type': 'text',
    },
  ];

  List<Map<String, dynamic>> get _filteredPosts {
    if (_selectedCategory == 'الكل') return _allPosts;
    return _allPosts.where((post) => post['tag'] == _selectedCategory).toList();
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
            setState(() => _selectedCategory = value);
          },
          itemBuilder: (context) => _categories.map((String category) {
            return PopupMenuItem<String>(
              value: category,
              child: Text(category),
            );
          }).toList(),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // الأيقونات الاحترافية
            _buildCircleIcon(Icons.shield, Colors.blueAccent, () {}),
            const SizedBox(width: 8),
            _buildCircleIcon(Icons.warning, Colors.redAccent, () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('SOS قيد التطوير...')),
              );
            }),
            const SizedBox(width: 8),
            _buildCircleIcon(Icons.radar, Colors.white, () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('الرادار قيد التطوير...')),
              );
            }),
            const SizedBox(width: 8),
            // شعار البلوتوث الحقيقي
            _buildCircleIcon(FontAwesomeIcons.bluetoothB, Colors.blue, () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تشغيل البلوتوث قيد التطوير...')),
              );
            }),
            const SizedBox(width: 8),
            _buildCircleIcon(Icons.notifications, Colors.white, () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('الإشعارات قيد التطوير...')),
              );
            }),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (String value) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$value قيد التطوير...')),
              );
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'الإعدادات', child: Text('الإعدادات')),
              PopupMenuItem(value: 'حول التطبيق', child: Text('حول التطبيق')),
              PopupMenuItem(value: 'مساعدة', child: Text('مساعدة')),
            ],
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: _filteredPosts.length,
        itemBuilder: (context, index) {
          final post = _filteredPosts[index];
          return _buildPost(post);
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
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('SOS قيد التطوير...')),
          );
        },
        backgroundColor: const Color(0xFFD32F2F),
        child: const Text(
          'SOS',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  // الدالة الاحترافية للأيقونات
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
            colors: [
              color.withOpacity(0.6),
              Colors.black.withOpacity(0.8),
            ],
          ),
          border: Border.all(
            color: Colors.white.withOpacity(0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: 10,
              spreadRadius: 1,
              offset: const Offset(0, 4),
            ),
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
        if (post['type'] == 'image')
          Image.network(
            post['image'],
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              color: Colors.black,
              child: const Center(
                child: Icon(Icons.image, size: 80, color: Colors.grey),
              ),
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
                  color: post['tagColor'] == 'red' ? Colors.red : (post['tagColor'] == 'blue' ? Colors.blue : Colors.orange),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  post['tag'],
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    post['sender'],
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.verified, color: Colors.blue, size: 20),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                post['text'],
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),

        Positioned(
          bottom: 20,
          right: 16,
          child: Column(
            children: [
              _buildActionButton(Icons.favorite, post['likes'].toString(), Colors.red),
              const SizedBox(height: 16),
              _buildActionButton(Icons.comment, post['comments'].toString(), Colors.white),
              const SizedBox(height: 16),
              
              GestureDetector(
                onTap: () {
                  Share.share(post['text']);
                },
                child: _buildActionButton(Icons.share, 'مشاركة', Colors.white),
              ),
              
              const SizedBox(height: 16),
              
              // زر الحفظ (سهم التحميل)
              GestureDetector(
                onTap: () async {
                  if (post['image'] != null && post['image'].toString().isNotEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('جاري حفظ الصورة...')),
                    );

                    try {
                      var response = await http.get(Uri.parse(post['image']));
                      final result = await ImageGallerySaver.saveImage(
                        Uint8List.fromList(response.bodyBytes),
                        quality: 100,
                        name: "Elnaseh_${DateTime.now().millisecondsSinceEpoch}",
                      );

                      if (result['isSuccess']) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('✅ تم حفظ الصورة في المعرض بنجاح')),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('❌ فشل حفظ الصورة')),
                        );
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('خطأ: $e')),
                      );
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('هذا المنشور نصي فقط، لا توجد صورة لحفظها')),
                    );
                  }
                },
                child: _buildActionButton(Icons.download, 'حفظ', Colors.white),
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
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    );
  }
}
