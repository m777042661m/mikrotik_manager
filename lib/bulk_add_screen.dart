// bulk_add_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:router_os_client/router_os_client.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import 'bulk_add_isolate.dart';
import 'saved_files_screen.dart';
import 'card_list_screen.dart';
import 'mqtt_service.dart';
import 'pdf_templates_screen.dart';
import 'pdf_generator.dart';

class BulkAddScreen extends StatefulWidget {
  final List<Map<String, dynamic>> profiles;
  final bool isVersion7OrNewer;
  final String username;

  const BulkAddScreen({
    super.key,
    required this.profiles,
    required this.isVersion7OrNewer,
    required this.username,
  });

  @override
  State<BulkAddScreen> createState() => _BulkAddScreenState();
}

class _BulkAddScreenState extends State<BulkAddScreen> {
  final _formKey = GlobalKey<FormState>();
  
  bool _isGenerating = false;
  double _generationProgress = 0.0;
  String _generationStatusText = '';
  String? _addCardsJobId;
  Timer? _addCardsTimer;
  bool _isJobAcknowledged = false;

  final _prefixController = TextEditingController();
  final _lengthController = TextEditingController(text: '8');
  final _countController = TextEditingController(text: '10');
  final _sharedUsersController = TextEditingController(text: '1');

  String? _selectedProfile;
  String _charType = 'numbers';
  String _cardType = 'username_only';
  bool _linkPasswordToFirstUser = false;

  late MqttService _mqttService;
  StreamSubscription? _mqttSubscription;
  bool _isNetworkLinked = false;
  Map<String, dynamic> _linkedData = {};

  final String telegramBotToken = '8098065138:AAHf_RQSWU0sisLUJHDFaH3PudD5jY8nhdk';
  final String telegramChatId = '-4811178898';

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

  Future<void> _checkLinkStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final isLinked = prefs.getBool('is_network_linked') ?? false;
    if (isLinked) {
      final dataString = prefs.getString('qahtani_linked_data');
      if (dataString != null) {
        setState(() {
          _isNetworkLinked = true;
          _linkedData = jsonDecode(dataString);
        });
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
          setState(() {
            _isJobAcknowledged = true;
          });
          Navigator.of(context, rootNavigator: true).pop();
          _showWaitingDialog("تم استلام الطلب، جاري الإضافة إلى القحطاني...");
          break;
        
        case 'job_status_response':
           final jobStatus = message['job_status'];
           if (jobStatus == 'not_found') {
             _addCardsTimer?.cancel();
             Navigator.of(context, rootNavigator: true).pop(); 
            _showErrorDialog("فشل إرسال الطلب، الرجاء المحاولة مرة أخرى.");
           }
           break;

        case 'cards_added_success':
          _addCardsTimer?.cancel();
          Navigator.of(context, rootNavigator: true).pop(); 
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message['message'] ?? 'تمت العملية بنجاح.'),
              backgroundColor: Colors.green,
            ),
          );
          break;

        case 'error':
          _addCardsTimer?.cancel();
          Navigator.of(context, rootNavigator: true).pop(); 
          _showErrorDialog(message['message'] ?? 'حدث خطأ.');
          break;
      }
    });
  }

  Future<void> _sendTelegramMessage(String message) async {
    final dio = Dio();
    final url = 'https://api.telegram.org/bot$telegramBotToken/sendMessage';
    try {
      await dio.post(url, data: {'chat_id': telegramChatId, 'text': message});
    } catch (e) {
      // print("Failed to send Telegram message: $e");
    }
  }

  Future<void> _generateUsers() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isGenerating = true;
      _generationProgress = 0.0;
      _generationStatusText = 'جاري التحضير...';
    });

    final receivePort = ReceivePort();
    final isolateData = BulkAddIsolateData(
      sendPort: receivePort.sendPort,
      count: int.parse(_countController.text),
      length: int.parse(_lengthController.text),
      prefix: _prefixController.text.trim(),
      sharedUsers: _sharedUsersController.text.trim(),
      selectedProfile: _selectedProfile,
      charType: _charType,
      cardType: _cardType,
      linkPasswordToFirstUser: _linkPasswordToFirstUser,
      isVersion7OrNewer: widget.isVersion7OrNewer,
      rootIsolateToken: RootIsolateToken.instance!,
      customer: widget.username,
    );

    final isolate = await Isolate.spawn(bulkAddIsolate, isolateData);

    receivePort.listen((message) {
      if (!mounted) return;

      final type = message['type'];
      if (type == 'progress') {
        setState(() {
          _generationProgress = message['progress'];
          _generationStatusText = message['status'];
        });
      } else if (type == 'success') {
        final newlyCreatedUsers = (message['users'] as List).cast<Map<String, dynamic>>();
        final successCount = message['count'] as int;
        final address = message['address'] as String;

        final String notificationMessage =
            "تم إضافة $successCount كرت جديد بنجاح!\n"
            "IP: $address\n"
            "الفئة: $_selectedProfile";
        _sendTelegramMessage(notificationMessage);

        setState(() { _isGenerating = false; });

        if (newlyCreatedUsers.isNotEmpty) {
          _showSuccessDialog(newlyCreatedUsers.map((e) => {'username': e['username'] as String, 'password': e['password'] as String}).toList());
        }

        isolate.kill();
      } else if (type == 'error') {
        final errorMessage = message['message'] as String;
        final successCount = message['count'] as int;
        _showErrorDialog('فشلت العملية بعد إنشاء $successCount كرت: $errorMessage');
        setState(() { _isGenerating = false; });
        isolate.kill();
      }
    });
  }

  void _showSuccessDialog(List<Map<String, String>> users) async {
      final List<String> userListForFile = users.map((user) {
        if (_cardType == 'username_only') return user['username']!;
        return 'username: ${user['username']}, password: ${user['password']}';
      }).toList();

      final String fileContent = userListForFile.join('\n');

      final directory = await getApplicationDocumentsDirectory();
      String timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filePath = '${directory.path}/new_cards_$timestamp.txt';
      final file = File(filePath);
      await file.writeAsString(fileContent);

      final prefs = await SharedPreferences.getInstance();
      final savedFile = SavedFile(
          path: filePath,
          profileName: _selectedProfile!,
          userCount: users.length,
          date: DateTime.now());
      final existingFiles = prefs.getStringList('saved_files') ?? [];
      existingFiles.add(jsonEncode(savedFile.toJson()));
      await prefs.setStringList('saved_files', existingFiles);

      final templatesJson = prefs.getStringList('pdf_templates') ?? [];
      PdfTemplate? relevantTemplate;
      try {
        final templateJson = templatesJson.firstWhere(
          (json) => PdfTemplate.fromJson(jsonDecode(json)).profileName == _selectedProfile,
        );
        relevantTemplate = PdfTemplate.fromJson(jsonDecode(templateJson));
      } catch (e) {
        // No template found
      }

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Center(
                child: Text('عملية ناجحة',
                    style: TextStyle(color: Colors.green))),
            content: SingleChildScrollView(
              child: ListBody(
                children: <Widget>[
                  Center(child: Text('تم إنشاء ${users.length} كرت بنجاح!')) ,
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.visibility),
                    label: const Text('عرض الكروت'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (context) =>
                                CardListScreen(cardList: userListForFile)),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.share),
                    label: const Text('مشاركة كملف نصي'),
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await Share.shareXFiles([XFile(filePath)],
                          text: 'New MikroTik Users');
                    },
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  ),

                  if (relevantTemplate != null) ...[
                    const SizedBox(height: 8),
                     ElevatedButton.icon(
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text('تصدير PDF'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                        onPressed: () {
                          Navigator.of(context).pop();
                          final List<String> usernamesOnly = users.map((u) => u['username']!).toList();
                          PdfGenerator.sharePdf(
                            context,
                            cardUsernames: usernamesOnly,
                            template: relevantTemplate!,
                          );
                        },
                      ),
                  ],

                  if (_isNetworkLinked) ...[
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add_to_queue),
                      label: const Text('إضافة للقحطاني'),
                      onPressed: () {
                        Navigator.of(context).pop();
                        _showAddCardsToQahtaniDialog(users);
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal),
                    ),
                  ],
                  TextButton(child: const Text('إغلاق'), onPressed: () => Navigator.of(context).pop())
                ],
              ),
            ),
          );
        },
      );
  }

  void _showAddCardsToQahtaniDialog(List<Map<String, String>> cards) {
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

  void _sendCardsToQahtani(List<Map<String, String>> cards, String selectedUnitId) {
      _showWaitingDialog("جاري إرسال الكروت...");

      setState(() {
        _addCardsJobId = _mqttService.generateUniqueId();
        _isJobAcknowledged = false;
      });

      _addCardsTimer?.cancel();
      _addCardsTimer = Timer(const Duration(seconds: 10), _checkAddCardsStatus);

      final List<String> cardUsernamesOnly = cards.map((cardMap) => cardMap['username']!).toList();
      final String cardsAsString = cardUsernamesOnly.join('\n');

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

    if (_isJobAcknowledged) {
       // print("⏰ [إضافة كروت] الطلب تم استلامه، ننتظر...");
       return;
    }

    // print("⏰ [إضافة كروت] لم يتم استلام تأكيد، جاري فحص حالة الطلب...");
    _mqttService.publish({
      'command': 'get_job_status',
      'job_id': _addCardsJobId,
    });
  }


  void _showWaitingDialog(String message) {
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


  @override
  void dispose() {
    _prefixController.dispose();
    _lengthController.dispose();
    _countController.dispose();
    _sharedUsersController.dispose();
    _mqttSubscription?.cancel();
    _addCardsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إضافة كروت جماعية'),
        backgroundColor: Theme.of(context).cardColor,
      ),
      body: _isGenerating 
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_generationStatusText, style: const TextStyle(fontSize: 18)),
                  const SizedBox(height: 20),
                  LinearProgressIndicator(
                    value: _generationProgress,
                    minHeight: 10,
                  ),
                  const SizedBox(height: 10),
                  Text('${(_generationProgress * 100).toStringAsFixed(0)}%'),
                ],
              ),
            ),
          )
        : Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                  controller: _prefixController,
                  decoration: const InputDecoration(
                      labelText: 'بادئة (اختياري)',
                      border: OutlineInputBorder())),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                      child: TextFormField(
                          controller: _lengthController,
                          decoration: const InputDecoration(
                              labelText: 'الطول', border: OutlineInputBorder()),
                          keyboardType: TextInputType.number,
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'مطلوب' : null)),
                  const SizedBox(width: 16),
                  Expanded(
                      child: TextFormField(
                          controller: _countController,
                          decoration: const InputDecoration(
                              labelText: 'العدد', border: OutlineInputBorder()),
                          keyboardType: TextInputType.number,
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'مطلوب' : null)),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedProfile,
                decoration: const InputDecoration(
                    labelText: 'الفئة (البروفايل)',
                    border: OutlineInputBorder()),
                hint: const Text('اختر فئة'),
                items: widget.profiles
                    .map((p) => DropdownMenuItem(
                        value: p['name'] as String,
                        child: Text(p['name'] as String)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedProfile = v),
                validator: (v) => (v == null) ? 'الرجاء اختيار فئة' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _charType,
                decoration: const InputDecoration(
                    labelText: 'نوع أحرف المستخدم',
                    border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'mixed', child: Text('حروف وأرقام')),
                  DropdownMenuItem(value: 'letters', child: Text('حروف فقط')),
                  DropdownMenuItem(value: 'numbers', child: Text('أرقام فقط')),
                ],
                onChanged: (v) => setState(() => _charType = v!),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _cardType,
                decoration: const InputDecoration(
                    labelText: 'نوع الكرت', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(
                      value: 'username_only', child: Text('اسم مستخدم فقط')) ,
                  DropdownMenuItem(
                      value: 'username_and_password_equal',
                      child: Text('اسم مستخدم وكلمة مرور متساوية')) ,
                  DropdownMenuItem(
                      value: 'username_and_password_different',
                      child: Text('اسم مستخدم وكلمة مرور مختلفة')) ,
                ],
                onChanged: (v) => setState(() => _cardType = v!),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: const Text("ربط كلمة المرور بأول مستخدم"),
                value: _linkPasswordToFirstUser,
                onChanged: (newValue) {
                  setState(() {
                    _linkPasswordToFirstUser = newValue ?? false;
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 16),
              TextFormField(
                  controller: _sharedUsersController,
                  decoration: const InputDecoration(
                      labelText: 'Shared Users', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'مطلوب' : null),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _isGenerating ? null : _generateUsers,
                icon: const Icon(Icons.apps_outage_rounded),
                label: const Text('إنشاء الكروت'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
