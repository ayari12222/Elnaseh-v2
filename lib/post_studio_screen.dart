import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class PostStudioScreen extends StatefulWidget {
  const PostStudioScreen({super.key});

  @override
  State<PostStudioScreen> createState() => _PostStudioScreenState();
}

class _PostStudioScreenState extends State<PostStudioScreen> {
  final TextEditingController _topTextController = TextEditingController();
  final TextEditingController _bottomTextController = TextEditingController();
  
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  // دالة اختيار الصورة
  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image != null) {
      setState(() => _selectedImage = File(image.path));
    }
  }

  // دالة النشر
  Future<void> _publishPost() async {
    if (_topTextController.text.isEmpty && _bottomTextController.text.isEmpty && _selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إضافة نص أو صورة'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. تسجيل الدخول بحساب المسؤول (لضمان صلاحيات الكتابة)
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: 'ayaribett22@gmail.com', // ✏️ إيميلك
        password: 'abiromri201',        // ✏️ كلمة السر
      );

      // 2. رفع الصورة إلى Firebase Storage (إذا وجدت)
      String imageUrl = '';
      if (_selectedImage != null) {
        final ref = FirebaseStorage.instance.ref().child('announcements/${DateTime.now().millisecondsSinceEpoch}.jpg');
        await ref.putFile(_selectedImage!);
        imageUrl = await ref.getDownloadURL();
      }

      // 3. حفظ المنشور في Firestore (يتم إنشاء الحقول تلقائياً)
      await FirebaseFirestore.instance.collection('announcements').add({
        'title': _topTextController.text.trim(),       // ✅ النص العلوي
        'content': _bottomTextController.text.trim(),  // ✅ النص السفلي
        'image_url': imageUrl,                         // ✅ رابط الصورة
        'type': imageUrl.isNotEmpty ? 'image' : 'text',
        'likes': 0,
        'comments': 0,
        'created_at': FieldValue.serverTimestamp(),    // ✅ تاريخ النشر
        'tag': 'الكل',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ تم النشر بنجاح!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context); // العودة للشاشة الرئيسية
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ خطأ: $e'), backgroundColor: Colors.red),
        );
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
        title: const Text('🎨 استوديو النشر', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1E1E1E),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('النص العلوي:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _topTextController,
              maxLines: 3,
              style: const TextStyle(color: Colors.black, backgroundColor: Colors.white),
              decoration: const InputDecoration(
                hintText: 'اكتب النص الذي سيظهر في الصندوق الأول...',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            
            const Text('النص السفلي:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _bottomTextController,
              maxLines: 3,
              style: const TextStyle(color: Colors.black, backgroundColor: Colors.white),
              decoration: const InputDecoration(
                hintText: 'اكتب النص الذي سيظهر في الصندوق الثاني...',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            
            // زر اختيار الصورة
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.image, color: Colors.white),
                  label: const Text('اختيار صورة من المعرض', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
                ),
                const SizedBox(width: 10),
                if (_selectedImage != null)
                  const Icon(Icons.check_circle, color: Colors.green, size: 28),
              ],
            ),
            
            // معاينة الصورة
            if (_selectedImage != null) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(_selectedImage!, height: 150, width: double.infinity, fit: BoxFit.cover),
              ),
            ],
            
            const SizedBox(height: 30),
            
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _publishPost,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.black)
                    : const Text('نشر الآن', style: TextStyle(fontSize: 18, color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
