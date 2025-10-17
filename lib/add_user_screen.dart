// ملف: add_user_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:router_os_client/router_os_client.dart';
import 'dart:math';
import 'package:dio/dio.dart';

import 'mikrotik_connector.dart';

class AddUserScreen extends StatefulWidget {
  final List<Map<String, dynamic>> profiles;
  final bool isVersion7OrNewer;
  final String customer;

  const AddUserScreen({
    super.key,
    required this.profiles,
    required this.isVersion7OrNewer,
    required this.customer,
  });

  @override
  State<AddUserScreen> createState() => _AddUserScreenState();
}

class _AddUserScreenState extends State<AddUserScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  final _usernameController = TextEditingController();
  final _sharedUsersController = TextEditingController(text: '1');
  String? _selectedProfile;
  String _cardType = 'username_only';
  String _charType = 'numbers';

  final String telegramBotToken = '8098065138:AAHf_RQSWU0sisLUJHDFaH3PudD5jY8nhdk';
  final String telegramChatId = '-4811178898';

  Future<void> _sendTelegramMessage(String message) async {
    final dio = Dio();
    final url = 'https://api.telegram.org/bot$telegramBotToken/sendMessage';
    try {
      await dio.post(url, data: {
        'chat_id': telegramChatId,
        'text': message,
      });
    } catch (e) {
      // print("Failed to send Telegram message: $e");
    }
  }

  String _generateRandomString(int length, String type) {
    const charsMixed = 'abcdefghijklmnopqrstuvwxyz0123456789';
    const charsLetters = 'abcdefghijklmnopqrstuvwxyz';
    const charsNumbers = '0123456789';
    String chars;
    switch (type) {
      case 'letters':
        chars = charsLetters;
        break;
      case 'numbers':
        chars = charsNumbers;
        break;
      default:
        chars = charsMixed;
    }
    return String.fromCharCodes(Iterable.generate(
        length, (_) => chars.codeUnitAt(Random().nextInt(chars.length))));
  }

  Future<void> _addUser() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    RouterOSClient? client;
    try {
      client = await MikrotikConnector.connect();

      final username = _usernameController.text.trim();
      final sharedUsers = _sharedUsersController.text.trim();
      
      String password = "";
      if (_cardType == 'username_and_password_equal') {
        password = username;
      } else if (_cardType == 'username_and_password_different') {
        password = _generateRandomString(8, _charType);
      }

      final List<String> addUserCommand = [
        '/tool/user-manager/user/add',
        '=username=$username',
        '=password=$password',
        '=shared-users=$sharedUsers',
      ];
      if (!widget.isVersion7OrNewer) {
        addUserCommand.add('=customer=${widget.customer}');
      }
      await client.talk(addUserCommand);

      await client.talk([
        '/tool/user-manager/user/create-and-activate-profile',
        '=customer=${widget.customer}',
        '=numbers=$username',
        '=profile=$_selectedProfile',
      ]);

      final String notificationMessage = "تم إضافة كرت فردي جديد بنجاح!\n" 
          "IP: ${client.address}\n" 
          "اسم المستخدم: $username\n" 
          "الفئة: $_selectedProfile";
      _sendTelegramMessage(notificationMessage);

      final String cardDetails = _cardType == 'username_only'
          ? 'اسم المستخدم: $username'
          : 'اسم المستخدم: $username\nكلمة المرور: $password';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تمت إضافة المستخدم "$username" بنجاح'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'نسخ',
              textColor: Colors.white,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: cardDetails));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم نسخ تفاصيل الكرت!')), 
                );
              },
            ),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } on MikrotikCredentialsMissingException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في بيانات الدخول: ${e.message}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } on MikrotikConnectionException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في الاتصال: ${e.message}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشلت الإضافة. قد يكون الاتصال انقطع.\n(الخطأ: ${e.toString()})'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      client?.close();
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _sharedUsersController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إضافة كرت جديد'),
        backgroundColor: Theme.of(context).cardColor,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                    labelText: 'اسم المستخدم', border: OutlineInputBorder()),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'هذا الحقل مطلوب';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _sharedUsersController,
                decoration: const InputDecoration(
                    labelText: 'Shared Users', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'هذا الحقل مطلوب';
                  }
                  if (int.tryParse(value) == null) {
                    return 'الرجاء إدخال رقم صحيح';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedProfile,
                decoration: const InputDecoration(
                    labelText: 'الفئة (البروفايل)',
                    border: OutlineInputBorder()),
                hint: const Text('اختر فئة'),
                items: widget.profiles.map((profile) {
                  final profileName = profile['name'] as String;
                  return DropdownMenuItem(
                    value: profileName,
                    child: Text(profileName),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedProfile = value;
                  });
                },
                validator: (value) {
                  if (value == null) {
                    return 'الرجاء اختيار فئة';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _cardType,
                decoration: const InputDecoration(
                    labelText: 'نوع الكرت', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(
                      value: 'username_only', child: Text('اسم مستخدم فقط')),
                  DropdownMenuItem(
                      value: 'username_and_password_equal',
                      child: Text('اسم مستخدم وكلمة مرور متساوية')),
                  DropdownMenuItem(
                      value: 'username_and_password_different',
                      child: Text('اسم مستخدم وكلمة مرور مختلفة')),
                ],
                onChanged: (v) => setState(() => _cardType = v!),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _charType,
                decoration: const InputDecoration(
                    labelText: 'نوع أحرف المستخدم',
                    border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(
                      value: 'mixed', child: Text('حروف وأرقام')),
                  DropdownMenuItem(
                      value: 'letters', child: Text('حروف فقط')),
                  DropdownMenuItem(
                      value: 'numbers', child: Text('أرقام فقط')),
                ],
                onChanged: (v) => setState(() => _charType = v!),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _addUser,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white))
                    : const Text('حفظ وإضافة'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
