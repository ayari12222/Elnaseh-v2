import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:screenshot/screenshot.dart'; // ✅ لأخذ لقطة للتصميم
import 'dart:io';
import 'dart:typed_data';

class PostStudioScreen extends StatefulWidget {
  const PostStudioScreen({super.key});

  @override
  State<PostStudioScreen> createState() => _PostStudioScreenState();
}

class _PostStudioScreenState extends State<PostStudioScreen> {
  final TextEditingController _textController = TextEditingController();
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();
  final ScreenshotController _screenshotController = ScreenshotController();
  bool _isLoading = false;

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image != null) {
      setState(() => _selectedImage = File(image.path));
    }
  }

  Future<void> _publishPost() async {
    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى اختيار صورة أولاً'), backgroundColor: Colors.red));
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. أخذ لقطة للتصميم (الصورة + النص)
      final Uint8List? imageBytes = await _screenshotController.capture();
      if (imageBytes == null) throw Exception('فشل التقاط التصميم');

      // 2. رفع الصورة النهائية إلى Firebase Storage
      String imageUrl = '';
      final ref = FirebaseStorage.instance.ref().child('announcements/${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putData(imageBytes);
      imageUrl = await ref.getDownloadURL();

      // 3. حفظ المنشور في Firestore
      await FirebaseFirestore.instance.collection('announcements').add({
        'title': '',
        'content': '',
        'image_url': imageUrl,
        'likes': 0,
        'comments': 0,
        'created_at': FieldValue.serverTimestamp(),
        'type': 'image',
        'tag': 'الكل',
      });

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
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('استوديو النشر', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: _isLoading 
                ? const CircularProgressIndicator(color: Colors.white)
                : const Icon(Icons.check, color: Colors.cyanAccent, size: 30),
            onPressed: _isLoading ? null : _publishPost,
          ),
        ],
      ),
      body: Screenshot(
        controller: _screenshotController,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_selectedImage != null)
              Image.file(_selectedImage!, fit: BoxFit.cover)
            else
              Container(
                color: const Color(0xFF1E1E1E),
                child: Center(
                  child: ElevatedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.image),
                    label: const Text('اختيار صورة من المعرض'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
                  ),
                ),
              ),

            // الكتابة فوق الصورة مباشرة
            Positioned(
              top: 100, left: 16, right: 16,
              child: TextField(
                controller: _textController,
                maxLines: null,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: Colors.black, blurRadius: 10, offset: Offset(0, 2))]
                ),
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  hintText: 'اكتب هنا...',
                  hintStyle: TextStyle(color: Colors.white70, fontSize: 20),
                  border: InputBorder.none,
                ),
              ),
            ),

            // زر تغيير الصورة
            Positioned(
              bottom: 30, left: 20, right: 20,
              child: ElevatedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.image),
                label: const Text('تغيير الصورة'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
