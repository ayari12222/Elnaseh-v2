import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:screenshot/screenshot.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QuickPostScreen extends StatefulWidget {
  const QuickPostScreen({super.key});

  @override
  State<QuickPostScreen> createState() => _QuickPostScreenState();
}

class TextLayer {
  String text;
  Color color;
  Color backgroundColor;
  double fontSize;
  String font;
  bool isBold;
  Offset position;
  TextAlign textAlign;

  TextLayer({
    required this.text,
    this.color = Colors.white,
    this.backgroundColor = Colors.transparent,
    this.fontSize = 24.0,
    this.font = 'Cairo',
    this.isBold = true,
    required this.position,
    this.textAlign = TextAlign.center,
  });
}

class _QuickPostScreenState extends State<QuickPostScreen> {
  File? _selectedImage;
  final ScreenshotController _screenshotController = ScreenshotController();
  
  List<TextLayer> _textLayers = [];
  int _activeTextIndex = -1;
  
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();
  
  final List<String> _fonts = ['Cairo', 'Tajawal', 'Almarai', 'Changa', 'Amiri'];
  
  bool _isUploading = false;
  bool _isEditingText = false;

  final List<Map<String, dynamic>> _styles = [
    {'name': 'Classic', 'color': Colors.white, 'bg': Colors.transparent},
    {'name': 'Elegance', 'color': Colors.amber, 'bg': Colors.transparent},
    {'name': 'Neon', 'color': Colors.cyanAccent, 'bg': Colors.transparent},
    {'name': 'Retro', 'color': Colors.redAccent, 'bg': Colors.yellow},
  ];

  @override
  void initState() {
    super.initState();
    _textFocusNode.addListener(() {
      setState(() => _isEditingText = _textFocusNode.hasFocus);
    });
    _checkDraft();
  }

  @override
  void dispose() {
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  // ✅ استرجاع المسودة
  Future<void> _checkDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final String? path = prefs.getString('quick_draft_image');
    final String? text = prefs.getString('quick_draft_text');
    if (path != null && File(path).existsSync()) {
      setState(() {
        _selectedImage = File(path);
        _textController.text = text ?? '';
        if (_textController.text.isNotEmpty) {
          _textLayers.add(TextLayer(text: _textController.text, position: const Offset(100, 250)));
          _activeTextIndex = 0;
        }
      });
    }
  }

  // ✅ حفظ المسودة
  Future<void> _saveDraft() async {
    if (_selectedImage == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('quick_draft_image', _selectedImage!.path);
    await prefs.setString('quick_draft_text', _textController.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ تم حفظ المسودة'), backgroundColor: Colors.green),
      );
    }
  }

  // ✅ حذف المسودة
  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('quick_draft_image');
    await prefs.remove('quick_draft_text');
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
        _textLayers.clear();
        _textController.clear();
        _addNewText();
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

  // 🛑 دالة النشر (محدثة لتعرض النجاح والفشل)
  Future<void> _publishPost() async {
    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ الرجاء اختيار صورة أولاً'), backgroundColor: Colors.red),
      );
      return;
    }

    // إخفاء لوحة المفاتيح والأدوات قبل التقاط الصورة
    FocusScope.of(context).unfocus();
    setState(() => _activeTextIndex = -1);
    await Future.delayed(const Duration(milliseconds: 300));

    setState(() => _isUploading = true);

    try {
      // 1. التقاط الصورة النهائية (الصورة + النص)
      final Uint8List? imageBytes = await _screenshotController.capture();
      if (imageBytes == null) throw Exception("فشل التقاط الصورة");

      // 2. رفع الصورة إلى Firebase Storage
      final String fileName = 'post_${DateTime.now().millisecondsSinceEpoch}.png';
      final Reference storageRef = FirebaseStorage.instance.ref().child('posts/$fileName');
      
      // ✅ التأكد من اكتمال الرفع
      final UploadTask uploadTask = storageRef.putData(imageBytes);
      final TaskSnapshot taskSnapshot = await uploadTask;
      if (taskSnapshot.state != TaskState.success) {
        throw Exception("فشل رفع الصورة، الحالة: ${taskSnapshot.state}");
      }

      // 3. جلب رابط الصورة
      final String downloadUrl = await storageRef.getDownloadURL();

      // 4. حفظ بيانات المنشور في Firestore
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

      // 5. حذف المسودة بعد النشر
      await _clearDraft();

      // ✅ إعلان النجاح
      if (mounted) {
        Navigator.pop(context); // العودة للشاشة الرئيسية
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم النشر بنجاح!'), 
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // ❌ إعلان الفشل
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ فشل النشر: $e'), 
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق', style: TextStyle(color: Colors.cyanAccent))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () async {
            await _saveDraft(); // ✅ حفظ المسودة عند الإغلاق
            if (mounted) Navigator.pop(context);
          },
        ),
        actions: [
          // زر حفظ المسودة اليدوي
          IconButton(
            icon: const Icon(Icons.save, color: Colors.amberAccent),
            onPressed: _saveDraft,
          ),
          // ✅ زر النشر (يتحول لتحميل أثناء النشر)
          IconButton(
            icon: _isUploading 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                : const Icon(Icons.send, color: Colors.redAccent),
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
          const Icon(Icons.add_photo_alternate, size: 100, color: Colors.white),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15)),
            onPressed: _pickImage,
            icon: const Icon(Icons.photo_library, color: Colors.white),
            label: const Text('اختيار من المعرض', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildStudioView() {
    return Column(
      children: [
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
                                shadows: [const Shadow(color: Colors.black, blurRadius: 10)],
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

        if (_isEditingText && _activeTextIndex >= 0)
          Container(
            color: const Color(0xFF1E1E1E),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.title, color: Colors.white),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFF1E1E1E),
                              title: const Text('اختر الخط', style: TextStyle(color: Colors.white)),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: _fonts.map((font) => ListTile(
                                  title: Text(font, style: TextStyle(color: Colors.white, fontFamily: font)),
                                  onTap: () {
                                    setState(() => _textLayers[_activeTextIndex].font = font);
                                    Navigator.pop(ctx);
                                  },
                                )).toList(),
                              ),
                            ),
                          );
                        },
                      ),
                      IconButton(icon: Icon(Icons.color_lens, color: _textLayers[_activeTextIndex].color), onPressed: () => _showColorPicker(isBackground: false)),
                      IconButton(
                        icon: Icon(Icons.format_color_fill, color: _textLayers[_activeTextIndex].backgroundColor == Colors.transparent ? Colors.white : _textLayers[_activeTextIndex].backgroundColor),
                        onPressed: () => _showColorPicker(isBackground: true),
                      ),
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
                      IconButton(icon: const Icon(Icons.check, color: Colors.greenAccent), onPressed: () { FocusScope.of(context).unfocus(); setState(() => _activeTextIndex = -1); }),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
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
