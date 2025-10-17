// lib/saved_files_screen.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'card_list_screen.dart';
import 'pdf_generator.dart';      // <-- ١. استيراد جديد
import 'pdf_templates_screen.dart'; // <-- ٢. استيراد جديد

class SavedFile {
  final String path;
  final String profileName;
  final int userCount;
  final DateTime date;

  SavedFile({
    required this.path,
    required this.profileName,
    required this.userCount,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'profileName': profileName,
        'userCount': userCount,
        'date': date.toIso8601String(),
      };

  factory SavedFile.fromJson(Map<String, dynamic> json) => SavedFile(
        path: json['path'],
        profileName: json['profileName'],
        userCount: json['userCount'],
        date: DateTime.parse(json['date']),
      );
}

class SavedFilesScreen extends StatefulWidget {
  const SavedFilesScreen({super.key});

  @override
  State<SavedFilesScreen> createState() => _SavedFilesScreenState();
}

class _SavedFilesScreenState extends State<SavedFilesScreen> {
  List<SavedFile> _savedFiles = [];
  bool _isLoading = true;

  // --- ٣. متغيرات جديدة لحالة الربط ---
  bool _isNetworkLinked = false;
  Map<String, dynamic> _linkedData = {};
  // ---------------------------------

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() { _isLoading = true; });
    await _loadLinkStatus(); // تحميل حالة الربط
    await _loadSavedFiles(); // تحميل الملفات
    setState(() { _isLoading = false; });
  }

  Future<void> _loadSavedFiles() async {
    final prefs = await SharedPreferences.getInstance();
    final filesJson = prefs.getStringList('saved_files') ?? [];
    if (mounted) {
       _savedFiles = filesJson
        .map((jsonString) => SavedFile.fromJson(jsonDecode(jsonString)))
        .toList();
      _savedFiles.sort((a, b) => b.date.compareTo(a.date));
    }
  }
  
  // --- ٤. دالة جديدة لتحميل بيانات الربط ---
  Future<void> _loadLinkStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final isLinked = prefs.getBool('is_network_linked') ?? false;
    if (isLinked) {
      final dataString = prefs.getString('qahtani_linked_data');
      if (dataString != null && mounted) {
        setState(() {
          _isNetworkLinked = true;
          _linkedData = jsonDecode(dataString);
        });
      }
    }
  }
  // ---------------------------------------

  Future<void> _shareFile(String path) async {
    try {
      await Share.shareXFiles([XFile(path)]);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشلت عملية المشاركة.'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteFile(SavedFile fileToDelete) async {
    try {
      final file = File(fileToDelete.path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // تجاهل الخطأ إذا فشل حذف الملف الفعلي
    }

    _savedFiles.remove(fileToDelete);
    final prefs = await SharedPreferences.getInstance();
    final updatedFilesJson =
        _savedFiles.map((file) => jsonEncode(file.toJson())).toList();
    await prefs.setStringList('saved_files', updatedFilesJson);
    setState(() {});
  }

  Future<void> _viewFile(String path) async {
    try {
      final file = File(path);
      final fileContent = await file.readAsString();
      // إزالة أي أسطر فارغة قد تنتج عن الانقسام
      final cardList = fileContent.split('\n').where((line) => line.trim().isNotEmpty).toList();

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            // --- ٥. تمرير بيانات الربط للشاشة التالية ---
            builder: (context) => CardListScreen(
              cardList: cardList,
              isNetworkLinked: _isNetworkLinked,
              linkedData: _linkedData,
            ),
            // ----------------------------------------
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل عرض الملف.'), backgroundColor: Colors.red),
      );
    }
  }
  
  // --- ٦. دالة جديدة للمشاركة كملف PDF ---
  Future<void> _shareAsPdf(SavedFile savedFile) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري تحضير ملف PDF...')),
    );

    try {
      // البحث عن القالب المطابق لاسم الفئة
      final prefs = await SharedPreferences.getInstance();
      final templatesJson = prefs.getStringList('pdf_templates') ?? [];
      final relevantTemplateJson = templatesJson.firstWhere(
        (json) => PdfTemplate.fromJson(jsonDecode(json)).profileName == savedFile.profileName,
      );
      final relevantTemplate = PdfTemplate.fromJson(jsonDecode(relevantTemplateJson));

      // قراءة أسماء المستخدمين من الملف النصي
      final file = File(savedFile.path);
      final fileContent = await file.readAsString();
      final cardUsernames = fileContent.split('\n').where((line) => line.trim().isNotEmpty).toList();

      // استدعاء دالة إنشاء ومشاركة الـ PDF
      await PdfGenerator.sharePdf(
        context,
        cardUsernames: cardUsernames,
        template: relevantTemplate,
      );

    } on StateError { // يتم إطلاقه بواسطة .firstWhere إذا لم يتم العثور على عنصر
       ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('لم يتم العثور على قالب PDF لهذه الفئة "${savedFile.profileName}".'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل إنشاء ملف PDF.'), backgroundColor: Colors.red),
      );
    }
  }
  // ----------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ملفات الكروت المحفوظة'),
        backgroundColor: Theme.of(context).cardColor,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _savedFiles.isEmpty
              ? const Center(
                  child: Text(
                    'لا توجد ملفات محفوظة.',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  itemCount: _savedFiles.length,
                  itemBuilder: (context, index) {
                    final file = _savedFiles[index];
                    final formattedDate = DateFormat('yyyy-MM-dd – hh:mm a').format(file.date);
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: ListTile(
                        leading: const Icon(Icons.description, color: Colors.cyan, size: 30),
                        title: Text('فئة: ${file.profileName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('العدد: ${file.userCount} كرت\nالتاريخ: $formattedDate'),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.visibility, color: Colors.blueAccent),
                              onPressed: () => _viewFile(file.path),
                              tooltip: 'عرض',
                            ),
                            // --- ٧. زر المشاركة كـ PDF الجديد ---
                             IconButton(
                              icon: const Icon(Icons.picture_as_pdf, color: Colors.orangeAccent),
                              onPressed: () => _shareAsPdf(file),
                              tooltip: 'مشاركة كـ PDF',
                            ),
                            // ----------------------------------
                            IconButton(
                              icon: const Icon(Icons.share, color: Colors.greenAccent),
                              onPressed: () => _shareFile(file.path),
                              tooltip: 'مشاركة كملف نصي',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                              onPressed: () => _deleteFile(file),
                              tooltip: 'حذف',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}