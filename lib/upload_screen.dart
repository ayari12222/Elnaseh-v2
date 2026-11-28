import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _imageFile;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  String _selectedCategory = 'عاجل';
  bool _isUploading = false;

  final List<String> _availableCategories = ['عاجل', 'معلومات', 'تحذير'];

  Future<void> _pickImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(source: source, imageQuality: 80);
    if (pickedFile != null) {
      setState(() => _imageFile = File(pickedFile.path));
    }
  }

  Future<void> _publishPost() async {
    if (_imageFile == null) {
      _showError('الرجاء اختيار صورة أولاً');
      return;
    }
    if (_contentController.text.trim().isEmpty) {
      _showError('الرجاء كتابة نص المنشور');
      return;
    }

    setState(() => _isUploading = true);

    try {
      // 1. رفع الصورة إلى Firebase Storage
      final ref = FirebaseStorage.instance
          .ref()
          .child('announcements')
          .child('${DateTime.now().millisecondsSinceEpoch}.jpg');
      
      await ref.putFile(_imageFile!);
      final imageUrl = await ref.getDownloadURL();

      // 2. حفظ المنشور في Firestore
      await FirebaseFirestore.instance.collection('announcements').add({
        'title': _titleController.text.trim(),
        'content': _contentController.text.trim(),
        'image_url': imageUrl,
        'tag': _selectedCategory,
        'likes': 0,
        'comments': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'type': 'image',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم النشر بنجاح'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      _showError('فشل النشر: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('نشر منشور جديد', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // اختيار الصورة
            GestureDetector(
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: const Color(0xFF1E1E1E),
                  builder: (context) => SafeArea(
                    child: Wrap(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.photo_library, color: Colors.cyanAccent),
                          title: const Text('المعرض', style: TextStyle(color: Colors.white)),
                          onTap: () { Navigator.pop(context); _pickImage(ImageSource.gallery); },
                        ),
                        ListTile(
                          leading: const Icon(Icons.camera_alt, color: Colors.cyanAccent),
                          title: const Text('الكاميرا', style: TextStyle(color: Colors.white)),
                          onTap: () { Navigator.pop(context); _pickImage(ImageSource.camera); },
                        ),
                      ],
                    ),
                  ),
                );
              },
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withOpacity(0.3)),
                ),
                child: _imageFile == null
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate, size: 60, color: Colors.cyanAccent),
                          SizedBox(height: 10),
                          Text('اضغط لاختيار صورة', style: TextStyle(color: Colors.white70)),
                        ],
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(_imageFile!, fit: BoxFit.cover),
                      ),
              ),
            ),
            const SizedBox(height: 20),

            // حقل العنوان
            TextField(
              controller: _titleController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'العنوان (اختياري)',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),

            // حقل المحتوى
            TextField(
              controller: _contentController,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'اكتب نص المنشور هنا...',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 20),

            // اختيار التصنيف
            const Text('اختر التصنيف:', style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _availableCategories.map((cat) {
                bool isSelected = _selectedCategory == cat;
                return ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  onSelected: (val) => setState(() => _selectedCategory = cat),
                  selectedColor: Colors.redAccent,
                  labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white70),
                  backgroundColor: const Color(0xFF1E1E1E),
                );
              }).toList(),
            ),
            const SizedBox(height: 30),

            // زر النشر
            ElevatedButton(
              onPressed: _isUploading ? null : _publishPost,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isUploading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('نشر الآن', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
