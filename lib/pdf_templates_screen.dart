import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'edit_pdf_template_screen.dart';

// موديل بسيط لتسهيل التعامل مع بيانات القالب
class PdfTemplate {
  final String profileName;
  final String imagePath;
  final double textXRatio; // نسبة موقع النص أفقياً
  final double textYRatio; // نسبة موقع النص عمودياً
  final int cardsPerPage;
  final double imageWidth; // عرض الصورة الأصلي
  final double imageHeight; // طول الصورة الأصلي
  // --- ✨ تعديل: إضافة متغيرات لحفظ أبعاد المربع ---
  final double markerWidthRatio;
  final double markerHeightRatio;


  PdfTemplate({
    required this.profileName,
    required this.imagePath,
    required this.textXRatio,
    required this.textYRatio,
    required this.cardsPerPage,
    required this.imageWidth,
    required this.imageHeight,
    // --- ✨ تعديل: إضافة المتغيرات الجديدة للكونستركتور ---
    required this.markerWidthRatio,
    required this.markerHeightRatio,
  });

  Map<String, dynamic> toJson() => {
        'profileName': profileName,
        'imagePath': imagePath,
        'textXRatio': textXRatio,
        'textYRatio': textYRatio,
        'cardsPerPage': cardsPerPage,
        'imageWidth': imageWidth,
        'imageHeight': imageHeight,
        // --- ✨ تعديل: إضافة المتغيرات الجديدة لـ JSON ---
        'markerWidthRatio': markerWidthRatio,
        'markerHeightRatio': markerHeightRatio,
      };

  factory PdfTemplate.fromJson(Map<String, dynamic> json) => PdfTemplate(
        profileName: json['profileName'],
        imagePath: json['imagePath'],
        textXRatio: json['textXRatio']?.toDouble() ?? 0.5,
        textYRatio: json['textYRatio']?.toDouble() ?? 0.5,
        cardsPerPage: json['cardsPerPage'],
        imageWidth: json['imageWidth']?.toDouble() ?? 1.0,
        imageHeight: json['imageHeight']?.toDouble() ?? 1.0,
        // --- ✨ تعديل: قراءة المتغيرات الجديدة من JSON مع قيم افتراضية ---
        markerWidthRatio: json['markerWidthRatio']?.toDouble() ?? 0.3,
        markerHeightRatio: json['markerHeightRatio']?.toDouble() ?? 0.1,
      );
}

class PdfTemplatesScreen extends StatefulWidget {
  final List<Map<String, dynamic>> profiles;

  const PdfTemplatesScreen({super.key, required this.profiles});

  @override
  State<PdfTemplatesScreen> createState() => _PdfTemplatesScreenState();
}

class _PdfTemplatesScreenState extends State<PdfTemplatesScreen> {
  List<PdfTemplate> _templates = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final templatesJson = prefs.getStringList('pdf_templates') ?? [];
    if (!mounted) return;
    setState(() {
      _templates = templatesJson
          .map((jsonString) => PdfTemplate.fromJson(jsonDecode(jsonString)))
          .toList();
      _isLoading = false;
    });
  }

  Future<void> _deleteTemplate(PdfTemplate templateToDelete) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text(
            'هل أنت متأكد من رغبتك في حذف قالب الفئة "${templateToDelete.profileName}"؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child:
                  const Text('حذف', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );

    if (shouldDelete != true) return;

    try {
      final file = File(templateToDelete.imagePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // تجاهل الخطأ
    }

    _templates.removeWhere((t) => t.profileName == templateToDelete.profileName);
    final prefs = await SharedPreferences.getInstance();
    final updatedTemplatesJson =
        _templates.map((t) => jsonEncode(t.toJson())).toList();
    await prefs.setStringList('pdf_templates', updatedTemplatesJson);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('تم حذف القالب بنجاح'),
            backgroundColor: Colors.green),
      );
    }
  }

  void _navigateAndReload(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => screen));
    _loadTemplates(); // إعادة التحميل بعد العودة من شاشة الإضافة/التعديل
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة قوالب PDF'),
        backgroundColor: Theme.of(context).cardColor,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _templates.isEmpty
              ? _buildEmptyView()
              : RefreshIndicator(
                  onRefresh: _loadTemplates,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _templates.length,
                    itemBuilder: (context, index) {
                      final template = _templates[index];
                      return _buildTemplateCard(template);
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () =>
            _navigateAndReload(EditPdfTemplateScreen(profiles: widget.profiles)),
        tooltip: 'إضافة قالب جديد',
        child: const Icon(Icons.add),
      ),
    );
  }

  // --- виджет جديد لبناء بطاقة القالب ---
  Widget _buildTemplateCard(PdfTemplate template) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- معاينة الصورة ---
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 150,
                width: double.infinity,
                color: Colors.grey.shade800,
                child: Image.file(
                  File(template.imagePath),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return const Center(
                        child: Icon(Icons.image_not_supported,
                            color: Colors.grey, size: 40));
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            // --- اسم الفئة ---
            Text(
              'قالب فئة: ${template.profileName}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            // --- عدد الكروت ---
            Text(
              'عدد الكروت بالصفحة: ${template.cardsPerPage}',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade400),
            ),
            const Divider(height: 24),
            // --- أزرار الإجراءات ---
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _deleteTemplate(template),
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.redAccent, size: 20),
                  label: const Text('حذف',
                      style: TextStyle(color: Colors.redAccent)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _navigateAndReload(EditPdfTemplateScreen(
                    profiles: widget.profiles,
                    existingTemplate: template,
                  )),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  label: const Text('تعديل'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  // --- виджет لعرض الشاشة الفارغة ---
  Widget _buildEmptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.style_outlined, size: 80, color: Colors.grey.shade600),
            const SizedBox(height: 20),
            const Text(
              'لا توجد قوالب محفوظة',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'اضغط على زر الإضافة (+) في الأسفل لإنشاء قالب PDF جديد خاص بك.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }
}