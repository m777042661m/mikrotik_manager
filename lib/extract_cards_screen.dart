import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'dart:io';
import 'process_image_screen.dart';
import 'mqtt_service.dart';

class ExtractCardsScreen extends StatefulWidget {
  const ExtractCardsScreen({super.key});

  @override
  State<ExtractCardsScreen> createState() => _ExtractCardsScreenState();
}

class _ExtractCardsScreenState extends State<ExtractCardsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _prefixController = TextEditingController();
  final _lengthController = TextEditingController();
  final _totalController = TextEditingController();

  List<String> _extractedCardNumbers = [];
  List<String> _imagePaths = [];

  // --- State for Al-Qahtani functionality ---
  late MqttService _mqttService;
  StreamSubscription? _mqttSubscription;
  bool _isNetworkLinked = false;
  Map<String, dynamic> _linkedData = {};
  String? _addCardsJobId;
  Timer? _addCardsTimer;
  bool _isJobAcknowledged = false;
  // ---

  final _documentScanner = DocumentScanner(
    options: DocumentScannerOptions(
      mode: ScannerMode.filter,
      documentFormat: DocumentFormat.jpeg,
      isGalleryImport: true,
      pageLimit: 10,
    ),
  );

  @override
  void initState() {
    super.initState();
    _checkLinkStatus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mqttService = Provider.of<MqttService>(context, listen: false);
    _setupMqttListener();
  }

  @override
  void dispose() {
    _prefixController.dispose();
    _lengthController.dispose();
    _totalController.dispose();
    _documentScanner.close();
    _mqttSubscription?.cancel();
    _addCardsTimer?.cancel();
    super.dispose();
  }

  // --- Al-Qahtani Methods ---

  Future<void> _checkLinkStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final isLinked = prefs.getBool('is_network_linked') ?? false;
    if (isLinked) {
      final dataString = prefs.getString('qahtani_linked_data');
      if (dataString != null) {
        if (mounted) {
          setState(() {
            _isNetworkLinked = true;
            _linkedData = jsonDecode(dataString);
          });
        }
      }
    }
  }

  void _setupMqttListener() {
    _mqttSubscription?.cancel();
    _mqttSubscription = _mqttService.messages.listen((message) {
      if (!mounted) return;
      
      final jobId = message['job_id'];
      if (_addCardsJobId == null || jobId != _addCardsJobId) return;

      final status = message['status'];

      switch(status) {
        case 'acknowledged':
          _addCardsTimer?.cancel();
          if (mounted) {
            setState(() {
              _isJobAcknowledged = true;
            });
            Navigator.of(context, rootNavigator: true).pop();
            _showWaitingDialog("تم استلام الطلب، جاري الإضافة إلى القحطاني...");
          }
          break;
        
        case 'job_status_response':
           final jobStatus = message['job_status'];
           if (jobStatus == 'not_found') {
             _addCardsTimer?.cancel();
             if (mounted) {
               Navigator.of(context, rootNavigator: true).pop(); 
               _showErrorDialog("فشل إرسال الطلب، الرجاء المحاولة مرة أخرى.");
             }
           }
           break;

        case 'cards_added_success':
          _addCardsTimer?.cancel();
          if (mounted) {
            Navigator.of(context, rootNavigator: true).pop(); 
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message['message'] ?? 'تمت العملية بنجاح.'),
                backgroundColor: Colors.green,
              ),
            );
          }
          break;

        case 'error':
          _addCardsTimer?.cancel();
          if (mounted) {
            Navigator.of(context, rootNavigator: true).pop(); 
            _showErrorDialog(message['message'] ?? 'حدث خطأ.');
          }
          break;
      }
    });
  }

  void _showAddCardsToQahtaniDialog(List<String> cards) {
    if (!_isNetworkLinked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الشبكة غير مرتبطة بحساب القحطاني')),
      );
      return;
    }

    String? selectedUnitId;
    final units = (_linkedData['network_details']?['units'] as List?) ?? [];

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('اختر فئة القحطاني'),
          content: DropdownButtonFormField<String>(
            hint: const Text('اختر الفئة'),
            items: units.map((unit) {
              return DropdownMenuItem<String>(
                value: unit['id'],
                child: Text(unit['name']),
              );
            }).toList(),
            onChanged: (value) {
              selectedUnitId = value;
            },
            validator: (value) => value == null ? 'الرجاء اختيار فئة' : null,
          ),
          actions: [
            TextButton(
              child: const Text('إلغاء'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: const Text('تأكيد وإضافة'),
              onPressed: () {
                if (selectedUnitId != null) {
                  Navigator.of(context).pop();
                  _sendCardsToQahtani(cards, selectedUnitId!);
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _sendCardsToQahtani(List<String> cards, String selectedUnitId) {
      _showWaitingDialog("جاري إرسال الكروت...");

      if (mounted) {
        setState(() {
          _addCardsJobId = _mqttService.generateUniqueId();
          _isJobAcknowledged = false;
        });
      }

      _addCardsTimer?.cancel();
      _addCardsTimer = Timer(const Duration(seconds: 10), _checkAddCardsStatus);

      final String cardsAsString = cards.join('\n');

      _mqttService.publish({
        'command': 'add_wifi_cards',
        'network_id': _linkedData['network_details']?['network_id'],
        'unit_id': selectedUnitId,
        'cards': cardsAsString,
        'job_id': _addCardsJobId,
      });
  }

  void _checkAddCardsStatus() {
    if (!mounted) return;
    if (_isJobAcknowledged) return;
    _mqttService.publish({
      'command': 'get_job_status',
      'job_id': _addCardsJobId,
    });
  }

  void _showWaitingDialog(String message) {
     if (!mounted) return;
     showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 20),
          Expanded(child: Text(message)),
        ]),
      ),
    );
  }

  void _showErrorDialog(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message),
          backgroundColor: Colors.redAccent),
    );
  }

  // --- Original Methods ---

  Future<void> _scanDocument({bool skipValidation = false}) async {
    if (!skipValidation && !_formKey.currentState!.validate()) {
      return;
    }
    try {
      final DocumentScanningResult result = await _documentScanner.scanDocument();
      if (result.images.isNotEmpty) {
        setState(() {
          _imagePaths.addAll(result.images);
        });
      }
    } catch (e) {
      print('Error during document scanning: $e');
    }
  }

  Future<void> _processImages() async {
    if (_imagePaths.isEmpty) return;

    final allExtractedNumbers = Set<String>.from(_extractedCardNumbers);
    for (final imagePath in _imagePaths) {
      final result = await Navigator.push<List<String>>(
        context,
        MaterialPageRoute(
          builder: (context) => ProcessImageScreen(
            imagePath: imagePath,
            prefix: _prefixController.text,
            length: int.parse(_lengthController.text),
            total: int.parse(_totalController.text),
          ),
        ),
      );
      if (result != null) {
        allExtractedNumbers.addAll(result);
      }
    }
    setState(() {
      _extractedCardNumbers = allExtractedNumbers.toList();
      _imagePaths = [];
    });
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null) {
      final path = result.files.single.path!;
      final file = File(path);
      final document = PdfDocument(inputBytes: file.readAsBytesSync());
      final text = PdfTextExtractor(document).extractText();
      document.dispose();
      final RegExp codeRegExp = RegExp(r'[a-zA-Z0-9]{6,}');
      final Set<String> cardNumbers =
          codeRegExp.allMatches(text).map((m) => m.group(0)!).toSet();
      setState(() {
        _extractedCardNumbers = cardNumbers.toList();
      });
    }
  }

  void _copyToClipboard(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('استخراج الكروت'),
        backgroundColor: Theme.of(context).cardColor,
      ),
      body: Center(
        child: _extractedCardNumbers.isNotEmpty
            ? Column( // --- RESULTS VIEW ---
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Text(
                      'تم العثور على ${_extractedCardNumbers.length} كرت:',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 2.8,
                        crossAxisSpacing: 6,
                        mainAxisSpacing: 6,
                      ),
                      itemCount: _extractedCardNumbers.length,
                      itemBuilder: (context, index) {
                        final cardNumber = _extractedCardNumbers[index];
                        return Card(
                          elevation: 2,
                          margin: EdgeInsets.zero,
                          child: InkWell(
                            onTap: () => _copyToClipboard(cardNumber, 'تم نسخ الرقم: $cardNumber'),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(4.0),
                                child: Text(
                                  cardNumber,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(
                      left: 4.0,
                      right: 4.0,
                      top: 8.0,
                      bottom: 8.0 + MediaQuery.of(context).viewPadding.bottom,
                    ),
                    child: Wrap(
                      spacing: 8.0,
                      runSpacing: 4.0,
                      alignment: WrapAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('البدء من جديد', style: TextStyle(fontSize: 11)),
                          onPressed: () => setState(() {
                            _extractedCardNumbers = [];
                            _prefixController.clear();
                            _lengthController.clear();
                            _totalController.clear();
                          }),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.add_to_queue, size: 16),
                          label: const Text('إضافة للقحطاني', style: TextStyle(fontSize: 11)),
                          onPressed: () => _showAddCardsToQahtaniDialog(_extractedCardNumbers),
                           style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.copy_all, size: 16),
                          label: const Text('نسخ الكل', style: TextStyle(fontSize: 11)),
                          onPressed: () {
                            final allCards = _extractedCardNumbers.join('\n');
                            _copyToClipboard(allCards, 'تم نسخ جميع الكروت (${_extractedCardNumbers.length})');
                          },
                           style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  )
                ],
              )
            : _imagePaths.isNotEmpty
                ? Column( // --- IMAGE PREVIEW VIEW ---
                    children: [
                      Expanded(
                        child: GridView.builder(
                          padding: const EdgeInsets.all(8),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 4,
                            mainAxisSpacing: 4,
                          ),
                          itemCount: _imagePaths.length,
                          itemBuilder: (context, index) {
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(_imagePaths[index]),
                                fit: BoxFit.cover,
                              ),
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(
                          left: 16.0,
                          right: 16.0,
                          top: 8.0,
                          bottom: 16.0 + MediaQuery.of(context).viewPadding.bottom,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _processImages,
                              icon: const Icon(Icons.check, size: 18),
                              label: const Text('استخراج', style: TextStyle(fontSize: 12)),
                               style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: () => _scanDocument(skipValidation: true),
                              icon: const Icon(Icons.add_a_photo, size: 18),
                              label: const Text('إضافة', style: TextStyle(fontSize: 12)),
                               style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: () =>
                                  setState(() => _imagePaths = []),
                              icon: const Icon(Icons.clear, size: 18),
                              label: const Text('مسح', style: TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : SingleChildScrollView( // --- INITIAL FORM VIEW ---
                    padding: const EdgeInsets.all(24.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(Icons.camera_alt_outlined,
                              size: 80, color: Colors.deepOrange),
                          const SizedBox(height: 20),
                          const Text(
                            'أدخل شروط المسح الضوئي للكروت',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                          const SizedBox(height: 32),
                          TextFormField(
                            controller: _prefixController,
                            decoration: const InputDecoration(
                              labelText: 'بادئة الكرت (بماذا يبدأ الرقم)',
                              prefixIcon: Icon(Icons.looks_one_outlined),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'الرجاء إدخال بادئة الكرت';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _lengthController,
                            decoration: const InputDecoration(
                              labelText: 'طول رقم الكرت (عدد الأرقام)',
                              prefixIcon: Icon(Icons.format_list_numbered),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'الرجاء إدخال طول الرقم';
                              }
                              if (int.tryParse(value) == null) {
                                return 'الرجاء إدخال رقم صحيح';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _totalController,
                            decoration: const InputDecoration(
                              labelText: 'العدد الإجمالي للكروت في الورقة',
                              prefixIcon: Icon(Icons.calculate_outlined),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'الرجاء إدخال العدد الإجمالي';
                              }
                              if (int.tryParse(value) == null) {
                                return 'الرجاء إدخال رقم صحيح';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              ElevatedButton.icon(
                                icon: const Icon(Icons.document_scanner, size: 18),
                                label: const Text('مسح ضوئي', style: TextStyle(fontSize: 12)),
                                onPressed: _scanDocument,
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                              ),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.picture_as_pdf, size: 18),
                                label: const Text('PDF', style: TextStyle(fontSize: 12)),
                                onPressed: _pickPdf,
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }
}
