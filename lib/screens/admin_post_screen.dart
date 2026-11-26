import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class AdminPostScreen extends StatefulWidget {
  const AdminPostScreen({super.key});

  @override
  State<AdminPostScreen> createState() => _AdminPostScreenState();
}

class _AdminPostScreenState extends State<AdminPostScreen> {
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _senderController = TextEditingController();
  
  String _selectedTag = 'عاجل';
  bool _isLoading = false;
  
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  Future<void> _publishPost() async {
    if (_textController.text.trim().isEmpty || _senderController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى ملء جميع الحقول المطلوبة'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    // محاكاة عملية النشر (لأن Firebase معطل مؤقتاً)
    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ تم النشر تجريبياً (Firebase معطل)'), backgroundColor: Colors.green),
      );
      Navigator.pop(context);
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('📝 نشر منشور جديد', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1E1E1E),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('نص المنشور:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _textController,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'اكتب التحذير أو الإرشادات هنا...',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 16),
            
            const Text('اسم الجهة المرسلة:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _senderController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'مثال: الدفاع المدني',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 16),

            // زر اختيار الصورة (يعمل الآن)
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.image, color: Colors.white),
                  label: const Text('اختيار صورة', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
                ),
                const SizedBox(width: 10),
                if (_selectedImage != null)
                  const Icon(Icons.check_circle, color: Colors.green),
              ],
            ),
            const SizedBox(height: 16),

            const Text('التصنيف:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedTag,
              dropdownColor: const Color(0xFF1E1E1E),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              items: ['عاجل', 'معلومات', 'تحذير'].map((String value) {
                return DropdownMenuItem<String>(value: value, child: Text(value));
              }).toList(),
              onChanged: (val) {
                setState(() {
                  _selectedTag = val!;
                });
              },
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _publishPost,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('نشر الآن', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
