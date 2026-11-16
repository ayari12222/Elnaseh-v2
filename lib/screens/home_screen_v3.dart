import 'package:flutter/material.dart';

class HomeScreenV3 extends StatefulWidget {
  const HomeScreenV3({super.key});

  @override
  State<HomeScreenV3> createState() => _HomeScreenV3State();
}

class _HomeScreenV3State extends State<HomeScreenV3> {
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
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shield, color: Colors.blueAccent, size: 28),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.warning, color: Colors.redAccent),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('SOS قيد التطوير...')),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.radar, color: Colors.white),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('الرادار قيد التطوير...')),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.bluetooth, color: Colors.blue),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('البلوتوث قيد التطوير...')),
                );
              },
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // شريط التصنيفات الأفقي (مثل تيك توك)
          Container(
            height: 50,
            color: const Color(0xFF1E1E1E),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                final isSelected = _selectedCategory == category;
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedCategory = category);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      category,
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.grey,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // قائمة المنشورات
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              itemCount: _filteredPosts.length,
              itemBuilder: (context, index) {
                final post = _filteredPosts[index];
                return _buildPost(post);
              },
            ),
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
              _buildActionButton(Icons.share, 'مشاركة', Colors.white),
              const SizedBox(height: 16),
              _buildActionButton(Icons.bookmark, 'حفظ', Colors.white),
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
