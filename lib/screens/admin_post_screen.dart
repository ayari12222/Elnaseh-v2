import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminPostScreen extends StatefulWidget {
  const AdminPostScreen({super.key});

  @override
  State<AdminPostScreen> createState() => _AdminPostScreenState();
}

class _AdminPostScreenState extends State<AdminPostScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _imageUrlController = TextEditingController();
  String _selectedTag = 'عاجل';
  bool _isLoading = false;

  Future<void> _publishPost() async {
    if (_titleController.text.trim().isEmpty || _contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى ملء العنوان والمحتوى'), backgroundColor: Colors.orange));
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance.collection('announcements').add({
        'title': _titleController.text.trim(),
        'content': _contentController.text.trim(),
        'image_url': _imageUrlController.text.trim(),
        'tag': _selectedTag,
        'likes': 0,
        'comments': 0,
        'created_at': FieldValue.serverTimestamp(),
      });

      _titleController.clear();
      _contentController.clear();
      _imageUrlController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ تم النشر بنجاح'), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('لوحة التحكم - نشر تنبيه', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1E1E1E),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _titleController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'العنوان (النص العلوي)', labelStyle: TextStyle(color: Colors.grey), filled: true, fillColor: Color(0xFF1E1E1E), border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _contentController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'المحتوى (النص السفلي)', labelStyle: TextStyle(color: Colors.grey), filled: true, fillColor: Color(0xFF1E1E1E), border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _imageUrlController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'رابط الصورة (اختياري)', labelStyle: TextStyle(color: Colors.grey), filled: true, fillColor: Color(0xFF1E1E1E), border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedTag,
                dropdownColor: const Color(0xFF1E1E1E),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'التصنيف', labelStyle: TextStyle(color: Colors.grey), filled: true, fillColor: Color(0xFF1E1E1E), border: OutlineInputBorder()),
                items: ['عاجل', 'معلومات', 'تحذير'].map((tag) => DropdownMenuItem(value: tag, child: Text(tag))).toList(),
                onChanged: (val) => setState(() => _selectedTag = val!),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                  onPressed: _isLoading ? null : _publishPost,
                  child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('نشر الآن', style: TextStyle(color: Colors.white, fontSize: 18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
