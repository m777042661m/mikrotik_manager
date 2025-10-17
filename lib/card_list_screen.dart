// lib/card_list_screen.dart

import 'dart:async';

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'mqtt_service.dart';

class CardListScreen extends StatefulWidget {
  final List<String> cardList;
  final bool isNetworkLinked;
  final Map<String, dynamic> linkedData;

  const CardListScreen({
    super.key,
    required this.cardList,
    this.isNetworkLinked = false,
    this.linkedData = const {},
  });

  @override
  State<CardListScreen> createState() => _CardListScreenState();
}

class _CardListScreenState extends State<CardListScreen> {
  late MqttService _mqttService;
  StreamSubscription? _mqttSubscription;
  String? _addCardsJobId;
  Timer? _addCardsTimer;
  bool _isJobAcknowledged = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mqttService = Provider.of<MqttService>(context, listen: false);
    _setupMqttListener();
  }

  Future<void> _shareCardsAsTextFile() async {
    final String fileContent = widget.cardList.join('\n');
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/shared_cards.txt';
    final file = File(filePath);
    await file.writeAsString(fileContent);

    await Share.shareXFiles([XFile(filePath)], text: 'الكروت المضافة حديثاً');
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
          setState(() => _isJobAcknowledged = true);
          Navigator.of(context, rootNavigator: true).pop();
          _showWaitingDialog("تم استلام الطلب، جاري الإضافة إلى القحطاني...");
          break;
        
        case 'job_status_response':
           if (message['job_status'] == 'not_found') {
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

  String _extractUsername(String cardLine) {
    if (cardLine.toLowerCase().contains('username:')) {
      try {
        return cardLine.split(',')[0].split(':')[1].trim();
      } catch (e) {
        return cardLine.trim();
      }
    }
    return cardLine.trim();
  }

  void _showAddCardsToQahtaniDialog() {
    String? selectedUnitId;
    final units = (widget.linkedData['network_details']?['units'] as List?) ?? [];

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
            onChanged: (value) => selectedUnitId = value,
            validator: (value) => value == null ? 'الرجاء اختيار فئة' : null,
          ),
          actions: [
            TextButton(child: const Text('إلغاء'), onPressed: () => Navigator.of(context).pop()),
            ElevatedButton(
              child: const Text('تأكيد وإضافة'),
              onPressed: () {
                if (selectedUnitId != null) {
                  Navigator.of(context).pop();
                  _sendCardsToQahtani(selectedUnitId!);
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _sendCardsToQahtani(String selectedUnitId) {
      _showWaitingDialog("جاري إرسال الكروت...");

      setState(() {
        _addCardsJobId = _mqttService.generateUniqueId();
        _isJobAcknowledged = false;
      });

      _addCardsTimer?.cancel();
      _addCardsTimer = Timer(const Duration(seconds: 10), _checkAddCardsStatus);
      
      final List<String> cardUsernamesOnly = widget.cardList.map(_extractUsername).toList();
      final String cardsAsString = cardUsernamesOnly.join('\n');

      _mqttService.publish({
        'command': 'add_wifi_cards',
        'network_id': widget.linkedData['network_details']?['network_id'],
        'unit_id': selectedUnitId,
        'cards': cardsAsString,
        'job_id': _addCardsJobId, // <-- هذا هو السطر الذي تم تصحيحه
      });
  }

  void _checkAddCardsStatus() {
    if (!mounted || _isJobAcknowledged) return;
    _mqttService.publish({'command': 'get_job_status', 'job_id': _addCardsJobId});
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
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  @override
  void dispose() {
    _mqttSubscription?.cancel();
    _addCardsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> bottomButtons = [
      Expanded(
        child: ElevatedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: widget.cardList.join('\n')));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تم نسخ جميع الكروت!')),
            );
          },
          icon: const Icon(Icons.copy_all),
          label: const Text('نسخ الكل'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: ElevatedButton.icon(
          onPressed: _shareCardsAsTextFile,
          icon: const Icon(Icons.share),
          label: const Text('مشاركة الكل'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
        ),
      ),
    ];

    if (widget.isNetworkLinked) {
      bottomButtons.add(const SizedBox(width: 8));
      bottomButtons.add(
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _showAddCardsToQahtaniDialog,
            icon: const Icon(Icons.add_to_queue),
            label: const Text('إضافة للقحطاني'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('الكروت المضافة حديثاً'),
        backgroundColor: Theme.of(context).cardColor,
      ),
      body: ListView.builder(
        itemCount: widget.cardList.length,
        itemBuilder: (context, index) {
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: ListTile(
              title: Text(widget.cardList[index]),
              trailing: IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.cardList[index]));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم نسخ الكرت!')),
                  );
                },
                tooltip: 'نسخ',
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: BottomAppBar(
        color: Theme.of(context).cardColor,
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: bottomButtons,
        ),
      ),
    );
  }
}