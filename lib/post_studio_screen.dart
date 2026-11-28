import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart'; 
import 'package:google_fonts/google_fonts.dart'; 
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

  // إعدادات النص
  Color _textColor = Colors.black;
  double _fontSize = 22.0;
  TextAlign _textAlign = TextAlign.center;
  bool _isTopTextActive = true; 

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image != null) {
      setState(() => _selectedImage = File(image.path));
    }
  }

  // دالة فتح لوحة الألوان
  void _pickColor() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('اختر لون النص', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: _textColor,
            onColorChanged: (color) {
              setState(() => _textColor = color);
            },
            pickerAreaHeightPercent: 0.7,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('تم', style: TextStyle(color: Colors.cyanAccent)),
          ),
        ],
      ),
    );
  }

  Future<void> _publishPost() async {
    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار صورة أولاً'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      String imageUrl = '';
      final ref = FirebaseStorage.instance.ref().child('announcements/${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putFile(_selectedImage!);
      imageUrl = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('announcements').add({
        'title': _topTextController.text.trim(),
        'content': _bottomTextController.text.trim(),
        'image_url': imageUrl,
        'likes': 0,
        'comments': 0,
        'created_at': FieldValue.serverTimestamp(),
        'type': 'image',
        'tag': 'الكل',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ تم النشر بنجاح!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('🎨 استوديو النشر', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1E1E1E),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: _isLoading 
                ? const CircularProgressIndicator(color: Colors.white)
                : const Icon(Icons.check, color: Colors.cyanAccent, size: 30),
            onPressed: _isLoading ? null : _publishPost,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. الصورة (تملأ الشاشة)
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

          // 2. حقول الكتابة فوق الصورة
          if (_selectedImage != null) ...[
            Positioned(
              top: 60, left: 16, right: 80, // ترك مساحة للأزرار على اليمين
              child: GestureDetector(
                onTap: () => setState(() => _isTopTextActive = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(8),
                    border: _isTopTextActive ? Border.all(color: Colors.cyanAccent, width: 2) : null,
                  ),
                  child: TextField(
                    controller: _topTextController,
                    style: GoogleFonts.cairo(
                      color: _textColor,
                      fontSize: _fontSize,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: _textAlign,
                    decoration: const InputDecoration(
                      hintText: 'النص العلوي...',
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
            ),

            Positioned(
              bottom: 120, left: 16, right: 80, // ترك مساحة للأزرار على اليمين
              child: GestureDetector(
                onTap: () => setState(() => _isTopTextActive = false),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(8),
                    border: !_isTopTextActive ? Border.all(color: Colors.cyanAccent, width: 2) : null,
                  ),
                  child: TextField(
                    controller: _bottomTextController,
                    style: GoogleFonts.cairo(
                      color: _textColor,
                      fontSize: _fontSize,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: _textAlign,
                    decoration: const InputDecoration(
                      hintText: 'النص السفلي...',
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
            ),
          ],

          // 3. الأدوات على أقصى اليمين (تحت بعضها)
          if (_selectedImage != null)
            Positioned(
              right: 10,
              top: 150, // نبدأ من الأعلى قليلاً
              child: Column(
                children: [
                  // زر فتح لوحة الألوان
                  _buildToolButton(
                    icon: Icons.color_lens,
                    color: _textColor == Colors.white ? Colors.black : Colors.white,
                    backgroundColor: _textColor,
                    onTap: _pickColor,
                  ),
                  const SizedBox(height: 15),

                  // أزرار المحاذاة
                  _buildToolButton(
                    icon: Icons.format_align_center,
                    onTap: () => setState(() => _textAlign = TextAlign.center),
                  ),
                  const SizedBox(height: 8),
                  _buildToolButton(
                    icon: Icons.format_align_right,
                    onTap: () => setState(() => _textAlign = TextAlign.right),
                  ),
                  const SizedBox(height: 8),
                  _buildToolButton(
                    icon: Icons.format_align_left,
                    onTap: () => setState(() => _textAlign = TextAlign.left),
                  ),
                  const SizedBox(height: 15),

                  // أزرار تكبير وتصغير الخط
                  _buildToolButton(
                    icon: Icons.text_increase,
                    onTap: () => setState(() => _fontSize += 2),
                  ),
                  const SizedBox(height: 8),
                  _buildToolButton(
                    icon: Icons.text_decrease,
                    onTap: () => setState(() => _fontSize = _fontSize > 12 ? _fontSize - 2 : 12),
                  ),
                  const SizedBox(height: 15),

                  // زر تغيير الصورة
                  _buildToolButton(
                    icon: Icons.image,
                    onTap: _pickImage,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // تصميم زر الأداة (مثل تيك توك)
  Widget _buildToolButton({required IconData icon, required VoidCallback onTap, Color color = Colors.white, Color? backgroundColor}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 45,
        height: 45,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: backgroundColor ?? Colors.black.withOpacity(0.5),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 5, spreadRadius: 1),
          ],
        ),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }
}
