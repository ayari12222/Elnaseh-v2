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

// كلاس لتمثيل النص (يدعم نصوص متعددة وتأثيرات)
class TextLayer {
  String text;
  Color color;
  Color backgroundColor;
  double fontSize;
  String font;
  bool isBold;
  Offset position;
  TextAlign textAlign;
  bool hasShadow;
  bool hasGlow;

  TextLayer({
    required this.text,
    this.color = Colors.white,
    this.backgroundColor = Colors.transparent,
    this.fontSize = 24.0,
    this.font = 'Cairo',
    this.isBold = true,
    required this.position,
    this.textAlign = TextAlign.center,
    this.hasShadow = true,
    this.hasGlow = false,
  });
}

class _PostStudioScreenState extends State<PostStudioScreen> {
  File? _selectedImage;
  final ScreenshotController _screenshotController = ScreenshotController();
  
  List<TextLayer> _textLayers = [];
  int _activeTextIndex = -1;
  
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();
  
  final List<String> _fonts = ['Cairo', 'Tajawal', 'Almarai', 'Changa', 'Amiri'];
  
  bool _isUploading = false;
  bool _isEditingText = false;

  // أنماط جاهزة (مثل تيك توك)
  final List<Map<String, dynamic>> _styles = [
    {'name': 'Classic', 'color': Colors.white, 'bg': Colors.transparent, 'shadow': true},
    {'name': 'Elegance', 'color': Colors.amber, 'bg': Colors.transparent, 'shadow': true},
    {'name': 'Neon', 'color': Colors.cyanAccent, 'bg': Colors.transparent, 'shadow': false, 'glow': true},
    {'name': 'Retro', 'color': Colors.redAccent, 'bg': Colors.yellow, 'shadow': false},
  ];

  @override
  void initState() {
    super.initState();
    _textFocusNode.addListener(() {
      setState(() => _isEditingText = _textFocusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
        if (_textLayers.isEmpty) _addNewText();
      });
    }
  }

  void _addNewText() {
    setState(() {
      _textLayers.add(TextLayer(text: '', position: const Offset(100, 250)));
      _activeTextIndex = _textLayers.length - 1;
      _textController.text = '';
      _textFocusNode.requestFocus();
    });
  }

  void _updateActiveText() {
    if (_activeTextIndex >= 0 && _activeTextIndex < _textLayers.length) {
      setState(() => _textLayers[_activeTextIndex].text = _textController.text);
    }
  }

  Future<void> _saveToGallery() async {
    try {
      FocusScope.of(context).unfocus();
      setState(() => _activeTextIndex = -1);
      await Future.delayed(const Duration(milliseconds: 300));
      
      final Uint8List? imageBytes = await _screenshotController.capture();
      if (imageBytes != null) {
        await ImageGallerySaverPlus.saveImage(imageBytes, name: 'elnaseh_post');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ تم الحفظ في المعرض'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الحفظ: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _publishPost() async {
    if (_selectedImage == null) return;
    FocusScope.of(context).unfocus();
    setState(() => _activeTextIndex = -1);
    await Future.delayed(const Duration(milliseconds: 300));

    setState(() => _isUploading = true);
    try {
      final Uint8List? imageBytes = await _screenshotController.capture();
      if (imageBytes == null) throw Exception("فشل التقاط الصورة");

      final String fileName = 'post_${DateTime.now().millisecondsSinceEpoch}.png';
      final Reference storageRef = FirebaseStorage.instance.ref().child('posts/$fileName');
      await storageRef.putData(imageBytes);
      final String downloadUrl = await storageRef.getDownloadURL();

      String allText = _textLayers.map((t) => t.text).where((t) => t.isNotEmpty).join(' ');

      await FirebaseFirestore.instance.collection('posts').add({
        'title': 'منشور جديد',
        'content': allText.isEmpty ? 'تصميم جديد' : allText,
        'imageUrl': downloadUrl,
        'tag': 'معلومات',
        'sender': 'الدفاع المدني',
        'likes': 0,
        'comments': 0,
        'timestamp': FieldValue.serverTimestamp(),
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

  void _showColorPicker({required bool isBackground}) {
    if (_activeTextIndex < 0) return;
    final layer = _textLayers[_activeTextIndex];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(isBackground ? 'لون الخلفية' : 'لون النص', style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: isBackground ? layer.backgroundColor : layer.color,
            onColorChanged: (color) => setState(() {
              if (isBackground) _textLayers[_activeTextIndex].backgroundColor = color;
              else _textLayers[_activeTextIndex].color = color;
            }),
            pickerAreaHeightPercent: 0.7,
          ),
        ),
        actions: [
          TextButton(onPressed: () { Navigator.pop(ctx); }, child: const Text('إغلاق', style: TextStyle(color: Colors.cyanAccent))),
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
          IconButton(icon: const Icon(Icons.save, color: Colors.greenAccent), onPressed: _selectedImage != null ? _saveToGallery : null),
          IconButton(
            icon: _isUploading ? const CircularProgressIndicator(color: Colors.cyanAccent) : const Icon(Icons.send, color: Colors.cyanAccent),
            onPressed: _isUploading ? null : _publishPost,
          ),
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
          const Text('اختر صورة للبدء', style: TextStyle(color: Colors.white, fontSize: 18)),
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
        // منطقة الصورة
        Expanded(
          child: GestureDetector(
            onTap: () {
              FocusScope.of(context).unfocus();
              setState(() => _activeTextIndex = -1);
            },
            child: Screenshot(
              controller: _screenshotController,
              child: Container(
                color: Colors.black,
                child: Stack(
                  children: [
                    Positioned.fill(child: Image.file(_selectedImage!, fit: BoxFit.cover)),
                    ..._textLayers.asMap().entries.map((entry) {
                      final index = entry.key;
                      final layer = entry.value;
                      final isActive = index == _activeTextIndex;
                      
                      return Positioned(
                        left: layer.position.dx,
                        top: layer.position.dy,
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            setState(() {
                              _textLayers[index].position = Offset(
                                _textLayers[index].position.dx + details.delta.dx,
                                _textLayers[index].position.dy + details.delta.dy,
                              );
                            });
                          },
                          onTap: () {
                            setState(() {
                              _activeTextIndex = index;
                              _textController.text = layer.text;
                              _textFocusNode.requestFocus();
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            decoration: BoxDecoration(
                              color: layer.backgroundColor,
                              borderRadius: BorderRadius.circular(4),
                              border: isActive ? Border.all(color: Colors.white, width: 1) : null,
                            ),
                            child: Text(
                              layer.text.isEmpty ? 'اكتب هنا...' : layer.text,
                              textAlign: layer.textAlign,
                              style: GoogleFonts.getFont(
                                layer.font,
                                color: layer.color,
                                fontSize: layer.fontSize,
                                fontWeight: layer.isBold ? FontWeight.bold : FontWeight.normal,
                                shadows: layer.hasGlow 
                                    ? [Shadow(color: layer.color, blurRadius: 20)] 
                                    : (layer.hasShadow ? [const Shadow(color: Colors.black, blurRadius: 10)] : []),
                              ),
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
        ),

        // ✅ شريط الأدوات العلوي (يظهر فوق لوحة المفاتيح)
        if (_isEditingText && _activeTextIndex >= 0)
          Container(
            color: const Color(0xFF1E1E1E),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // أدوات التحكم
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // زر الخط
                      DropdownButton<String>(
                        value: _textLayers[_activeTextIndex].font,
                        dropdownColor: const Color(0xFF0A0E17),
                        style: const TextStyle(color: Colors.white),
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                        underline: Container(),
                        items: _fonts.map((font) => DropdownMenuItem(value: font, child: Text(font, style: const TextStyle(color: Colors.white)))).toList(),
                        onChanged: (val) => setState(() => _textLayers[_activeTextIndex].font = val!),
                      ),
                      // زر لون النص
                      IconButton(icon: Icon(Icons.color_lens, color: _textLayers[_activeTextIndex].color), onPressed: () => _showColorPicker(isBackground: false)),
                      // زر التظليل (خلفية)
                      IconButton(
                        icon: Icon(Icons.format_color_fill, color: _textLayers[_activeTextIndex].backgroundColor == Colors.transparent ? Colors.white : _textLayers[_activeTextIndex].backgroundColor),
                        onPressed: () => _showColorPicker(isBackground: true),
                      ),
                      // زر المحاذاة
                      IconButton(
                        icon: const Icon(Icons.format_align_center, color: Colors.white),
                        onPressed: () {
                          setState(() {
                            _textLayers[_activeTextIndex].textAlign = _textLayers[_activeTextIndex].textAlign == TextAlign.center
                                ? TextAlign.right
                                : (_textLayers[_activeTextIndex].textAlign == TextAlign.right ? TextAlign.left : TextAlign.center);
                          });
                        },
                      ),
                      // زر التأثيرات (توهج)
                      IconButton(
                        icon: Icon(Icons.auto_awesome, color: _textLayers[_activeTextIndex].hasGlow ? Colors.cyanAccent : Colors.white),
                        onPressed: () => setState(() => _textLayers[_activeTextIndex].hasGlow = !_textLayers[_activeTextIndex].hasGlow),
                      ),
                      // زر "تم"
                      IconButton(icon: const Icon(Icons.check, color: Colors.greenAccent), onPressed: () { FocusScope.of(context).unfocus(); setState(() => _activeTextIndex = -1); }),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // شريط الأنماط الجاهزة (Classic, Elegance, Neon, Retro)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _styles.map((style) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _textLayers[_activeTextIndex].color = style['color'];
                              _textLayers[_activeTextIndex].backgroundColor = style['bg'];
                              _textLayers[_activeTextIndex].hasShadow = style['shadow'] ?? false;
                              _textLayers[_activeTextIndex].hasGlow = style['glow'] ?? false;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0A0E17),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.grey),
                            ),
                            child: Text(style['name'], style: const TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),
                // حقل النص
                TextField(
                  controller: _textController,
                  focusNode: _textFocusNode,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  onChanged: (val) => _updateActiveText(),
                  decoration: InputDecoration(
                    hintText: 'اكتب النص أو الصقه...',
                    hintStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: const Color(0xFF0A0E17),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
          ),

        // الشريط السفلي (يظهر عند عدم التحرير)
        if (!_isEditingText)
          Container(
            color: const Color(0xFF1E1E1E),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  onPressed: _addNewText,
                  icon: const Icon(Icons.text_fields, color: Colors.cyanAccent),
                  label: const Text('إضافة نص', style: TextStyle(color: Colors.cyanAccent)),
                ),
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
