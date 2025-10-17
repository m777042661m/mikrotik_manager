// edit_pdf_template_screen.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'pdf_templates_screen.dart';

class EditPdfTemplateScreen extends StatefulWidget {
  final List<Map<String, dynamic>> profiles;
  final PdfTemplate? existingTemplate;

  const EditPdfTemplateScreen({
    super.key,
    required this.profiles,
    this.existingTemplate,
  });

  @override
  State<EditPdfTemplateScreen> createState() => _EditPdfTemplateScreenState();
}

class _EditPdfTemplateScreenState extends State<EditPdfTemplateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _imageKey = GlobalKey();

  File? _imageFile;
  Offset _offset = Offset.zero;
  Offset _normalizedOffset = const Offset(0.5, 0.5);

  double _markerWidth = 100.0;
  double _markerHeight = 25.0;


  String? _selectedProfile;
  final _cardsPerPageController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingTemplate != null) {
      final t = widget.existingTemplate!;
      _selectedProfile = t.profileName;
      _cardsPerPageController.text = t.cardsPerPage.toString();
      _imageFile = File(t.imagePath);
      _normalizedOffset = Offset(t.textXRatio, t.textYRatio);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyNormalizedOffset();
      });
    }
  }

  void _applyNormalizedOffset() {
    if (_imageKey.currentContext != null) {
      final RenderBox renderBox =
          _imageKey.currentContext!.findRenderObject() as RenderBox;
      final imageSize = renderBox.size;
      setState(() {
        _offset = Offset(
          _normalizedOffset.dx * imageSize.width,
          _normalizedOffset.dy * imageSize.height,
        );
        if (widget.existingTemplate != null) {
          _markerWidth = widget.existingTemplate!.markerWidthRatio * imageSize.width;
          _markerHeight = widget.existingTemplate!.markerHeightRatio * imageSize.height;
        }
      });
    }
  }

  Future<void> _pickImage() async {
    final pickedFile =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
        _offset = Offset.zero;
        _normalizedOffset = const Offset(0.5, 0.5);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_imageKey.currentContext != null) {
          final RenderBox renderBox = _imageKey.currentContext!.findRenderObject() as RenderBox;
          setState(() {
            _offset = Offset(renderBox.size.width / 2, renderBox.size.height / 2);
          });
        }
      });
    }
  }

  Future<void> _saveTemplate() async {
    if (!_formKey.currentState!.validate()) return;
    final imageContext = _imageKey.currentContext;

    if (_imageFile == null || imageContext == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('الرجاء اختيار صورة وانتظار تحميلها أولاً'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    setState(() => _isLoading = true);

    _updateNormalizedOffset();

    try {
      final RenderBox renderBox = imageContext.findRenderObject() as RenderBox;
      final imageSizeOnScreen = renderBox.size;

      final textXRatio = _normalizedOffset.dx;
      final textYRatio = _normalizedOffset.dy;
      final markerWidthRatio = _markerWidth / imageSizeOnScreen.width;
      final markerHeightRatio = _markerHeight / imageSizeOnScreen.height;

      // --- ✨ التحسين: تم تغيير قراءة الملف من متزامن إلى غير متزامن ---
      // هذا يمنع تجميد الواجهة عند التعامل مع صور كبيرة
      final imageBytes = await _imageFile!.readAsBytes();
      final decodedImage = await decodeImageFromList(imageBytes);
      final imageWidth = decodedImage.width.toDouble();
      final imageHeight = decodedImage.height.toDouble();

      final appDir = await getApplicationDocumentsDirectory();
      final fileName = p.basename(_imageFile!.path);
      final savedImage = await _imageFile!.copy(p.join(appDir.path, fileName));

      final newTemplate = PdfTemplate(
        profileName: _selectedProfile!,
        imagePath: savedImage.path,
        textXRatio: textXRatio,
        textYRatio: textYRatio,
        cardsPerPage: int.parse(_cardsPerPageController.text),
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        markerWidthRatio: markerWidthRatio,
        markerHeightRatio: markerHeightRatio,
      );

      final prefs = await SharedPreferences.getInstance();
      final templatesJson = prefs.getStringList('pdf_templates') ?? [];
      templatesJson.removeWhere((jsonString) {
        final t = PdfTemplate.fromJson(jsonDecode(jsonString));
        return t.profileName == newTemplate.profileName;
      });
      templatesJson.add(jsonEncode(newTemplate.toJson()));
      await prefs.setStringList('pdf_templates', templatesJson);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تم حفظ القالب بنجاح!'),
          backgroundColor: Colors.green,
        ));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('حدث خطأ أثناء الحفظ: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _updateNormalizedOffset() {
    if (_imageKey.currentContext != null) {
      final RenderBox renderBox =
          _imageKey.currentContext!.findRenderObject() as RenderBox;
      final imageSize = renderBox.size;

      final double dx = (_offset.dx / imageSize.width).clamp(0.0, 1.0);
      final double dy = (_offset.dy / imageSize.height).clamp(0.0, 1.0);

      setState(() {
        _normalizedOffset = Offset(dx, dy);
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_imageKey.currentContext != null && _offset == Offset.zero) {
        final RenderBox renderBox = _imageKey.currentContext!.findRenderObject() as RenderBox;
        setState(() {
          _offset = Offset(renderBox.size.width * _normalizedOffset.dx, renderBox.size.height * _normalizedOffset.dy);
        });
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(
            widget.existingTemplate == null ? 'إضافة قالب جديد' : 'تعديل قالب'),
        backgroundColor: Theme.of(context).cardColor,
      ),
      body: _isLoading
          ? const Center(
              child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('جاري حفظ القالب...'),
              ],
            ))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            value: _selectedProfile,
                            decoration: const InputDecoration(
                                labelText: 'اختر الفئة (البروفايل)',
                                prefixIcon: Icon(Icons.category_outlined)),
                            items: widget.profiles
                                .map((p) => DropdownMenuItem(
                                      value: p['name'] as String,
                                      child: Text(p['name'] as String),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedProfile = v),
                            validator: (v) =>
                                v == null ? 'الرجاء اختيار فئة' : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _cardsPerPageController,
                            decoration: const InputDecoration(
                                labelText: 'عدد الكروت في كل صفحة',
                                prefixIcon: Icon(Icons.view_module_outlined)),
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'الحقل مطلوب';
                              if (int.tryParse(v) == null ||
                                  int.parse(v) <= 0) {
                                return 'أدخل رقماً صحيحاً أكبر من صفر';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          const Text(
                              'حرك المربع لتحديد منطقة طباعة الرقم',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onPanUpdate: (details) {
                               if (_imageKey.currentContext == null) return;
                               final RenderBox renderBox = _imageKey.currentContext!.findRenderObject() as RenderBox;
                               final newOffset = _offset + details.delta;

                               final constrainedDx = newOffset.dx.clamp(0.0, renderBox.size.width);
                               final constrainedDy = newOffset.dy.clamp(0.0, renderBox.size.height);

                               setState(() {
                                 _offset = Offset(constrainedDx, constrainedDy);
                               });
                            },
                            child: Container(
                                constraints:
                                    const BoxConstraints(maxHeight: 300),
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: Colors.grey.shade700),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Stack(
                                  children: [
                                     ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: _imageFile == null
                                          ? const Center(
                                              child: Text(
                                                  'اختر صورة للقالب أولاً'))
                                          : Image.file(
                                              _imageFile!,
                                              key: _imageKey,
                                              fit: BoxFit.contain,
                                            ),
                                    ),
                                    if (_imageFile != null)
                                      Positioned(
                                        left: _offset.dx - (_markerWidth / 2),
                                        top: _offset.dy - (_markerHeight / 2),
                                        child: IgnorePointer(
                                          child: Container(
                                            width: _markerWidth,
                                            height: _markerHeight,
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                  color: Colors.redAccent,
                                                  width: 2),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              color: Colors.redAccent
                                                  .withAlpha((255 * 0.3).round()),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ),

                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Text('العرض:', style: TextStyle(fontWeight: FontWeight.bold)),
                              Expanded(
                                child: Slider(
                                  value: _markerWidth,
                                  min: 20.0,
                                  max: 300.0,
                                  divisions: 28,
                                  label: _markerWidth.round().toString(),
                                  onChanged: (double value) {
                                    setState(() {
                                      _markerWidth = value;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              const Text('الارتفاع:', style: TextStyle(fontWeight: FontWeight.bold)),
                              Expanded(
                                child: Slider(
                                  value: _markerHeight,
                                  min: 10.0,
                                  max: 150.0,
                                  divisions: 14,
                                  label: _markerHeight.round().toString(),
                                  onChanged: (double value) {
                                    setState(() {
                                      _markerHeight = value;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _pickImage,
                            icon: const Icon(Icons.image_outlined),
                            label: const Text('اختر/غير صورة القالب'),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _isLoading ? null : _saveTemplate,
                            icon: const Icon(Icons.save),
                            label: const Text('حفظ القالب'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 48),
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}