import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  
  final TextEditingController _topTextController = TextEditingController();
  final TextEditingController _bottomTextController = TextEditingController();

  String _topText = '';
  String _bottomText = '';
  
  Color _topTextColor = Colors.white;
  double _topFontSize = 24.0;
  Offset _topTextPosition = const Offset(50, 150);

  Color _bottomTextColor = Colors.black;
  double _bottomFontSize = 20.0;
  Offset _bottomTextPosition = const Offset(50, 600);
  Color _bottomBoxColor = Colors.white;
  double _bottomBoxOpacity = 1.0;

  String _selectedFont = 'Cairo';
  final List<String> _fonts = ['Cairo', 'Tajawal', 'Almarai', 'Changa', 'Amiri'];

  List<Map<String, dynamic>> _stickers = [];
  bool _isUploading = false;

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) setState(() => _selectedImage = File(image.path));
  }

  void _addSticker(String stickerType) {
    setState(() {
      _stickers.add({
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'type': stickerType,
        'position': const Offset(100, 300),
        'scale': 1.0,
      });
    });
  }

  Future<void> _saveToGallery() async {
    try {
      final Uint8List? imageBytes = await _screenshotController.capture();
      if (imageBytes != null) {
        await ImageGallerySaverPlus.saveImage(imageBytes, name: 'elnaseh_post');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ تم حفظ التصميم في المعرض!'), backgroundColor: Colors.green));
      }
    } catch (e) { debugPrint(e.toString()); }
  }

  Future<void> _publishPost() async {
    if (_selectedImage == null) return;
    setState(() => _isUploading = true);
    try {
      final Uint8List? imageBytes = await _screenshotController.capture();
      if (imageBytes == null) throw Exception("فشل التقاط الصورة");

      final String fileName = 'post_${DateTime.now().millisecondsSinceEpoch}.png';
      final Reference storageRef = FirebaseStorage.instance.ref().child('posts/$fileName');
      await storageRef.putData(imageBytes);
      final String downloadUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance.collection('announcements').add({
        'title': _topText.isEmpty ? 'منشور جديد' : _topText,
        'content': _bottomText.isEmpty ? 'تصميم جديد' : _bottomText,
        'image_url': downloadUrl,
        'tag': 'معلومات',
        'likes': 0,
        'comments': 0,
        'created_at': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ تم النشر بنجاح!'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل النشر: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showColorPicker({required Function(Color) onColorChanged, required Color currentColor}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('اختر اللون', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(child: ColorPicker(pickerColor: currentColor, onColorChanged: onColorChanged, pickerAreaHeightPercent: 0.7)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً', style: TextStyle(color: Colors.cyanAccent)))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        title: const Text('استوديو النشر الاحترافي', style: TextStyle(color: Colors.cyanAccent)),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.cyanAccent),
        actions: [
          IconButton(icon: const Icon(Icons.save, color: Colors.greenAccent), onPressed: _selectedImage != null ? _saveToGallery : null),
          IconButton(icon: _isUploading ? const CircularProgressIndicator(color: Colors.cyanAccent) : const Icon(Icons.send, color: Colors.cyanAccent), onPressed: _isUploading ? null : _publishPost),
        ],
      ),
      body: _selectedImage == null ? _buildImagePickerView() : _buildStudioView(),
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15)),
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
                  Positioned.fill(child: Image.file(_selectedImage!, fit: BoxFit.cover)),
                  
                  // النص العلوي
                  if (_topText.isNotEmpty)
                    Positioned(
                      left: _topTextPosition.dx, top: _topTextPosition.dy,
                      child: GestureDetector(
                        onPanUpdate: (details) => setState(() => _topTextPosition += details.delta),
                        child: Text(
                          _topText,
                          style: GoogleFonts.getFont(_selectedFont, color: _topTextColor, fontSize: _topFontSize, fontWeight: FontWeight.bold, shadows: [const Shadow(color: Colors.black, blurRadius: 10)]),
                        ),
                      ),
                    ),
                  
                  // النص السفلي مع الصندوق
                  if (_bottomText.isNotEmpty)
                    Positioned(
                      left: _bottomTextPosition.dx, top: _bottomTextPosition.dy,
                      child: GestureDetector(
                        onPanUpdate: (details) => setState(() => _bottomTextPosition += details.delta),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: _bottomBoxColor.withOpacity(_bottomBoxOpacity), borderRadius: BorderRadius.circular(8)),
                          child: Text(_bottomText, style: GoogleFonts.getFont(_selectedFont, color: _bottomTextColor, fontSize: _bottomFontSize, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  
                  // الملصقات
                  ..._stickers.map((sticker) {
                    return Positioned(
                      left: sticker['position'].dx, top: sticker['position'].dy,
                      child: GestureDetector(
                        onPanUpdate: (details) => setState(() => sticker['position'] += details.delta),
                        child: Transform.scale(
                          scale: sticker['scale'],
                          child: Icon(
                            sticker['type'] == 'sos' ? Icons.sos : sticker['type'] == 'warning' ? Icons.warning_amber_rounded : Icons.info,
                            color: Colors.redAccent, size: 50,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ),
        ),
        
        // لوحة التحكم السفلية
        Container(
          color: const Color(0xFF1E1E1E),
          height: 250,
          child: DefaultTabController(
            length: 3,
            child: Column(
              children: [
                const TabBar(labelColor: Colors.cyanAccent, unselectedLabelColor: Colors.grey, tabs: [Tab(text: 'النص'), Tab(text: 'الصندوق'), Tab(text: 'الملصقات')]),
                Expanded(
                  child: TabBarView(
                    children: [
                      // تبويب النص
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(child: TextField(controller: _topTextController, style: const TextStyle(color: Colors.white), onChanged: (val) => setState(() => _topText = val), decoration: const InputDecoration(hintText: 'النص العلوي...', hintStyle: TextStyle(color: Colors.grey)))),
                                IconButton(icon: const Icon(Icons.color_lens, color: Colors.cyanAccent), onPressed: () => _showColorPicker(onColorChanged: (c) => setState(() => _topTextColor = c), currentColor: _topTextColor)),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(child: TextField(controller: _bottomTextController, style: const TextStyle(color: Colors.white), onChanged: (val) => setState(() => _bottomText = val), decoration: const InputDecoration(hintText: 'النص السفلي...', hintStyle: TextStyle(color: Colors.grey)))),
                                IconButton(icon: const Icon(Icons.color_lens, color: Colors.cyanAccent), onPressed: () => _showColorPicker(onColorChanged: (c) => setState(() => _bottomTextColor = c), currentColor: _bottomTextColor)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // تبويب الصندوق
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          children: [
                            const Text('لون الصندوق:', style: TextStyle(color: Colors.white)),
                            IconButton(icon: const Icon(Icons.color_lens, color: Colors.cyanAccent), onPressed: () => _showColorPicker(onColorChanged: (c) => setState(() => _bottomBoxColor = c), currentColor: _bottomBoxColor)),
                            Expanded(child: Slider(value: _bottomBoxOpacity, onChanged: (val) => setState(() => _bottomBoxOpacity = val), activeColor: Colors.cyanAccent)),
                          ],
                        ),
                      ),
                      // تبويب الملصقات
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Wrap(
                          spacing: 20,
                          children: [
                            IconButton(icon: const Icon(Icons.sos, color: Colors.red, size: 40), onPressed: () => _addSticker('sos')),
                            IconButton(icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 40), onPressed: () => _addSticker('warning')),
                            IconButton(icon: const Icon(Icons.info, color: Colors.blue, size: 40), onPressed: () => _addSticker('info')),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
