import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:screenshot/screenshot.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ✅ لحفظ المسودة

class QuickPostScreen extends StatefulWidget {
  const QuickPostScreen({super.key});

  @override
  State<QuickPostScreen> createState() => _QuickPostScreenState();
}

class _QuickPostScreenState extends State<QuickPostScreen> {
  File? _selectedImage;
  final ScreenshotController _screenshotController = ScreenshotController();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();

  String _text = '';
  Color _textColor = Colors.white;
  double _fontSize = 24.0;
  bool _isTextVisible = true;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    // ✅ استرجاع المسودة عند فتح الشاشة
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForDraft();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  // ✅ دالة استرجاع المسودة
  Future<void> _checkForDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final String? draftImagePath = prefs.getString('draft_image');
    final String? draftText = prefs.getString('draft_text');

    if (draftImagePath != null && File(draftImagePath).existsSync()) {
      setState(() {
        _selectedImage = File(draftImagePath);
        _text = draftText ?? '';
        _textController.text = _text;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('📝 تم استرجاع مسودتك السابقة'), backgroundColor: Colors.blue),
        );
      }
    }
  }

  // ✅ دالة حفظ المسودة
  Future<void> _saveDraft() async {
    if (_selectedImage == null) return;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('draft_image', _selectedImage!.path);
    await prefs.setString('draft_text', _text);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ تم حفظ المنشور كمسودة'), backgroundColor: Colors.green),
      );
    }
  }

  // ✅ دالة حذف المسودة
  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('draft_image');
    await prefs.remove('draft_text');
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => _selectedImage = File(image.path));
    }
  }

  Future<void> _publishPost() async {
    if (_selectedImage == null) return;

    FocusScope.of(context).unfocus();
    setState(() => _isTextVisible = false); // إخفاء النص مؤقتاً أثناء الالتقاط
    await Future.delayed(const Duration(milliseconds: 300));

    setState(() => _isUploading = true);
    try {
      final Uint8List? imageBytes = await _screenshotController.capture();
      if (imageBytes == null) throw Exception("فشل التقاط الصورة");

      final String fileName = 'post_${DateTime.now().millisecondsSinceEpoch}.png';
      final Reference storageRef = FirebaseStorage.instance.ref().child('posts/$fileName');
      await storageRef.putData(imageBytes);
      final String downloadUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance.collection('posts').add({
        'title': 'منشور جديد',
        'content': _text.isEmpty ? 'منشور جديد' : _text,
        'imageUrl': downloadUrl,
        'tag': 'معلومات',
        'sender': 'الدفاع المدني',
        'likes': 0,
        'comments': 0,
        'timestamp': FieldValue.serverTimestamp(),
      });

      await _clearDraft(); // ✅ مسح المسودة بعد النشر الناجح

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ تم النشر بنجاح!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل النشر: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
        setState(() => _isTextVisible = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _selectedImage == null
          ? _buildImagePickerView()
          : _buildTikTokStyleEditor(),
    );
  }

  Widget _buildImagePickerView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.add_photo_alternate, size: 100, color: Colors.white),
          const SizedBox(height: 20),
          const Text('اختر صورة للبدء', style: TextStyle(color: Colors.white, fontSize: 18)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
            ),
            onPressed: _pickImage,
            icon: const Icon(Icons.photo_library, color: Colors.white),
            label: const Text('اختيار من المعرض', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildTikTokStyleEditor() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. الصورة الأساسية (يمكن التقاطها)
        GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Screenshot(
            controller: _screenshotController,
            child: Container(
              color: Colors.black,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.file(_selectedImage!, fit: BoxFit.cover),
                  ),
                  // 2. النص فوق الصورة
                  if (_isTextVisible && _text.isNotEmpty)
                    Positioned(
                      top: 100, left: 20, right: 20,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5), // خلفية شفافة للنص
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _text,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.getFont(
                              'Cairo',
                              color: _textColor,
                              fontSize: _fontSize,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),

        // 3. الشريط العلوي (إغلاق + حفظ + إعدادات)
        Positioned(
          top: 40, left: 10, right: 10,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // زر الإغلاق (يحفظ المسودة تلقائياً)
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () async {
                  if (_selectedImage != null) {
                    await _saveDraft();
                  }
                  if (mounted) Navigator.pop(context);
                },
              ),
              // زر حفظ المسودة اليدوي
              IconButton(
                icon: const Icon(Icons.save, color: Colors.white, size: 28),
                onPressed: _saveDraft,
                tooltip: 'حفظ كمسودة',
              ),
              const Icon(Icons.settings, color: Colors.white, size: 30),
            ],
          ),
        ),

        // 4. الأزرار الجانبية (مثل تيك توك)
        Positioned(
          right: 10, top: 150,
          child: Column(
            children: [
              _buildSideButton(Icons.text_fields, 'نص', () => _textFocusNode.requestFocus()),
              _buildSideButton(Icons.color_lens, 'لون', () {
                setState(() => _textColor = _textColor == Colors.white ? Colors.red : Colors.white);
              }),
              _buildSideButton(Icons.format_size, 'حجم', () {
                setState(() => _fontSize = _fontSize == 24 ? 32 : 24);
              }),
            ],
          ),
        ),

        // 5. الشريط السفلي (حقل النص وزر النشر)
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.only(bottom: 20, top: 10, left: 16, right: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black.withOpacity(0.9), Colors.transparent],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // حقل النص (يظهر فوق لوحة المفاتيح)
                TextField(
                  controller: _textController,
                  focusNode: _textFocusNode,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                  onChanged: (val) => setState(() => _text = val),
                  decoration: InputDecoration(
                    hintText: 'اكتب هنا...',
                    hintStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.2),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
                const SizedBox(height: 10),
                // أزرار النشر
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.image, color: Colors.white),
                      label: const Text('تغيير الصورة', style: TextStyle(color: Colors.white)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                      ),
                      onPressed: _isUploading ? null : _publishPost,
                      child: _isUploading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Suivant', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSideButton(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
