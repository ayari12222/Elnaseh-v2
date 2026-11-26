import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✅ لدعم Clipboard
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:screenshot/screenshot.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class PostStudioScreen extends StatefulWidget {
  const PostStudioScreen({super.key});

  @override
  State<PostStudioScreen> createState() => _PostStudioScreenState();
}

class _PostStudioScreenState extends State<PostStudioScreen> {
  File? _selectedImage;
  final ScreenshotController _screenshotController = ScreenshotController();
  
  // ✅ متحكم النص لدعم اللصق والتعديل
  final TextEditingController _textController = TextEditingController();

  String _text = '';
  Color _textColor = Colors.white;
  double _fontSize = 24.0;
  String _selectedFont = 'Cairo';
  Offset _textPosition = const Offset(50, 400);
  
  final List<String> _fonts = ['Cairo', 'Tajawal', 'Almarai', 'Changa', 'Amiri'];
  
  bool _isUploading = false;

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => _selectedImage = File(image.path));
    }
  }

  Future<void> _saveToGallery() async {
    try {
      final Uint8List? imageBytes = await _screenshotController.capture();
      if (imageBytes != null) {
        await ImageGallerySaverPlus.saveImage(imageBytes, name: 'elnaseh_post');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ تم حفظ التصميم في المعرض!'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الحفظ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _publishPost() async {
    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء اختيار صورة أولاً'), backgroundColor: Colors.red),
      );
      return;
    }

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
        'content': _text.isEmpty ? 'تصميم جديد من الناصح' : _text,
        'imageUrl': downloadUrl,
        'tag': 'معلومات',
        'sender': 'الدفاع المدني',
        'likes': 0,
        'comments': 0,
        'timestamp': FieldValue.serverTimestamp(),
      });

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
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showColorPicker() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('اختر لون النص', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: _textColor,
            onColorChanged: (color) => setState(() => _textColor = color),
            pickerAreaHeightPercent: 0.7,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('حسناً', style: TextStyle(color: Colors.cyanAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        title: const Text('استوديو النشر', style: TextStyle(color: Colors.cyanAccent)),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.cyanAccent),
        actions: [
          IconButton(
            icon: const Icon(Icons.save, color: Colors.greenAccent),
            tooltip: 'حفظ في المعرض',
            onPressed: _selectedImage != null ? _saveToGallery : null,
          ),
          IconButton(
            icon: _isUploading 
                ? const CircularProgressIndicator(color: Colors.cyanAccent) 
                : const Icon(Icons.send, color: Colors.cyanAccent),
            tooltip: 'نشر',
            onPressed: _isUploading ? null : _publishPost,
          ),
        ],
      ),
      body: _selectedImage == null 
          ? _buildImagePickerView() 
          : _buildStudioView(),
    );
  }

  Widget _buildImagePickerView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.add_photo_alternate, size: 100, color: Colors.cyanAccent),
          const SizedBox(height: 20),
          const Text('اختر صورة للبدء في التصميم', style: TextStyle(color: Colors.white, fontSize: 18)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent,
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
            ),
            onPressed: _pickImage,
            icon: const Icon(Icons.photo_library, color: Colors.black),
            label: const Text('اختيار من المعرض', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildStudioView() {
    return Column(
      children: [
        Expanded(
          child: Screenshot(
            controller: _screenshotController,
            child: Container(
              color: Colors.black,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.file(_selectedImage!, fit: BoxFit.cover),
                  ),
                  Positioned(
                    left: _textPosition.dx,
                    top: _textPosition.dy,
                    child: GestureDetector(
                      onPanUpdate: (details) {
                        setState(() {
                          _textPosition = Offset(
                            _textPosition.dx + details.delta.dx,
                            _textPosition.dy + details.delta.dy,
                          );
                        });
                      },
                      child: Text(
                        _text.isEmpty ? 'اكتب النص هنا...' : _text,
                        style: GoogleFonts.getFont(
                          _selectedFont,
                          color: _textColor,
                          fontSize: _fontSize,
                          fontWeight: FontWeight.bold,
                          shadows: [const Shadow(color: Colors.black, blurRadius: 10)],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Container(
          color: const Color(0xFF1E1E1E),
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              // ✅ حقل النص مع زر اللصق
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 2,
                      onChanged: (val) => setState(() => _text = val),
                      decoration: InputDecoration(
                        hintText: 'اكتب النص هنا أو الصقه...',
                        hintStyle: const TextStyle(color: Colors.grey),
                        filled: true,
                        fillColor: const Color(0xFF0A0E17),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  // ✅ زر اللصق السريع
                  IconButton(
                    icon: const Icon(Icons.paste, color: Colors.cyanAccent),
                    tooltip: 'لصق',
                    onPressed: () async {
                      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
                      if (clipboardData != null && clipboardData.text != null) {
                        setState(() {
                          _text = clipboardData.text!;
                          _textController.text = _text;
                        });
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.color_lens, color: Colors.cyanAccent),
                    onPressed: _showColorPicker,
                  ),
                  Expanded(
                    child: Slider(
                      value: _fontSize,
                      min: 12,
                      max: 60,
                      activeColor: Colors.cyanAccent,
                      onChanged: (val) => setState(() => _fontSize = val),
                    ),
                  ),
                  DropdownButton<String>(
                    value: _selectedFont,
                    dropdownColor: const Color(0xFF0A0E17),
                    style: const TextStyle(color: Colors.white),
                    items: _fonts.map((font) => DropdownMenuItem(value: font, child: Text(font))).toList(),
                    onChanged: (val) => setState(() => _selectedFont = val!),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.image, color: Colors.orangeAccent),
                label: const Text('تغيير الصورة', style: TextStyle(color: Colors.orangeAccent)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
