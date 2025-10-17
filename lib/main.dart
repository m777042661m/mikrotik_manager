// main.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:router_os_client/router_os_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:marquee_widget/marquee_widget.dart';

// --- افترض أن هذه الملفات موجودة في مشروعك ---
import 'add_user_screen.dart';
import 'bulk_add_screen.dart';
import 'saved_files_screen.dart';
import 'mqtt_service.dart';
import 'qahtani_link_screen.dart';
import 'profile_screen.dart';
import 'pdf_templates_screen.dart';
import 'check_user_screen.dart';
import 'network_map_screen.dart';
import 'network_doctor_screen.dart';
import 'extract_cards_screen.dart';
import 'mikrotik_connector.dart';
// -----------------------------------------

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => MqttService(),
      child: const MyApp(),
    ),
  );
}

// A global key for the ScaffoldMessenger
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      title: 'MikroTik Manager',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF8A56AC), // لون بنفسجي مميز
        scaffoldBackgroundColor: const Color(0xFF2C2444), // خلفية بنفسجية داكنة
        fontFamily: 'Tajawal',
        cardColor: const Color(0xFF3E355F), // لون البطاقات
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFFE0D7F1)),
          bodyMedium: TextStyle(color: Color(0xFFB0A8C1)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF8A56AC), // لون أساسي للأزرار
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(fontSize: 18, fontFamily: 'Tajawal', fontWeight: FontWeight.bold),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF3E355F),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.0),
            borderSide: BorderSide.none,
          ),
          hintStyle: const TextStyle(color: Color(0xFFB0A8C1)),
          labelStyle: const TextStyle(color: Color(0xFFE0D7F1)),
          prefixIconColor: const Color(0xFFB0A8C1),
        ),
        iconTheme: const IconThemeData(
          color: Color(0xFFB0A8C1),
        ),
      ),
      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _ipController = TextEditingController();
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  final _portController = TextEditingController(text: '8728');

  bool _isLoading = false;
  String _errorMessage = '';
  bool _rememberMe = true;
  String _adText = 'يوجد لدينا تاجير خطوط فيبر سرعه الخط 100 ميجا';
  bool _isPasswordObscured = true;
  bool _isScanning = false;

  final String telegramBotToken = '8098065138:AAHf_RQSWU0sisLUJHDFaH3PudD5jY8nhdk';
  final String telegramChatId = '-4811178898';

  // --- جميع الدوال والوظائف الأصلية تبقى كما هي ---
  Future<void> _sendTelegramMessage(String message) async {
    final dio = Dio();
    final url = 'https://api.telegram.org/bot$telegramBotToken/sendMessage';
    try {
      await dio.post(url, data: {'chat_id': telegramChatId, 'text': message});
    } catch (e) {
      // Failed to send Telegram message
    }
  }

  Future<void> _fetchAdFromTelegram() async {
    final prefs = await SharedPreferences.getInstance();
    final dio = Dio();
    final url = 'https://api.telegram.org/bot$telegramBotToken/getUpdates';
    try {
      final response = await dio.get(url, queryParameters: {'chat_id': telegramChatId});
      if (response.statusCode == 200 && response.data != null) {
        final updates = response.data['result'] as List;
        if (updates.isNotEmpty) {
          for (var update in updates.reversed) {
            final messageText = update['message']['text'] as String?;
            if (messageText != null && messageText.startsWith('اعلان')) {
              final newAd = messageText.substring('اعلان'.length).trim();
              if (newAd.isNotEmpty) {
                if (_adText != newAd) {
                  setState(() => _adText = newAd);
                  await prefs.setString('ad_text', newAd);
                }
                break;
              }
            }
          }
        }
      }
    } catch (e) {
      print('Failed to fetch ad from Telegram: $e');
    }
  }

  Future<void> _launchUrl() async {
    final Uri url = Uri.parse('https://play.google.com/store/apps/details?id=alkahtani.yemoney');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح الرابط. يرجى التحقق من وجود المتجر.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _launchPrivacyPolicy() async {
    final Uri url = Uri.parse('https://m777042661m.github.io/mikrotik_manager/privacy_policy.html');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح رابط سياسة الخصوصية.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _loadSavedCredentials();
      await _loadAdText();
      await _fetchAdFromTelegram();
      await _discoverGateway();
    } catch (e, s) {
      print('Error in initState: $e\n$s');
    }
  }

  Future<void> _discoverGateway() async {
    if (_ipController.text.isNotEmpty) {
      return;
    }
    await _forceDiscoverGateway();
  }

  Future<void> _forceDiscoverGateway() async {
    setState(() {
      _isScanning = true;
      _errorMessage = 'جاري البحث عن بوابة الشبكة...';
    });
    try {
      final gatewayIp = await NetworkInfo().getWifiGatewayIP();
      if (gatewayIp != null && gatewayIp.isNotEmpty) {
        if (mounted) {
          setState(() {
            _ipController.text = gatewayIp;
            _errorMessage = 'تم العثور على بوابة الشبكة!';
          });
        }
      } else {
        if (mounted) setState(() => _errorMessage = 'لم يتم العثور على بوابة. تأكد من اتصالك بشبكة Wi-Fi.');
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'حدث خطأ أثناء محاولة اكتشاف الشبكة.');
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('remember_me') ?? false) {
      setState(() {
        _ipController.text = prefs.getString('ip') ?? '';
        _userController.text = prefs.getString('user') ?? '';
        _passwordController.text = prefs.getString('pass') ?? '';
        _portController.text = prefs.getString('port') ?? '8728';
        _rememberMe = true;
      });
    }
  }

  Future<void> _loadAdText() async {
    final prefs = await SharedPreferences.getInstance();
    final savedAd = prefs.getString('ad_text');
    if (savedAd != null) {
      setState(() => _adText = savedAd);
    }
  }

  Future<void> _handleCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remember_me', _rememberMe);
    if (_rememberMe) {
      await prefs.setString('ip', _ipController.text);
      await prefs.setString('user', _userController.text);
      await prefs.setString('pass', _passwordController.text);
      await prefs.setString('port', _portController.text);
    } else {
      await prefs.remove('ip');
      await prefs.remove('user');
      await prefs.remove('pass');
      await prefs.remove('port');
    }
  }

  Future<void> _login() async {
    if (_ipController.text.isEmpty || _userController.text.isEmpty) {
      setState(() => _errorMessage = 'الرجاء إدخال IP واسم المستخدم');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    RouterOSClient? client;
    try {
      await _handleCredentials();
      client = await MikrotikConnector.connect();
      _sendTelegramMessage('تم الدخول إلى التطبيق بنجاح عبر عنوان IP: ${_ipController.text}');
      final response = await client.talk(['/system/resource/print']);
      bool isVersion7OrNewer = false;
      if (response.isNotEmpty && response[0]['version'] != null) {
        final version = response[0]['version'] as String;
        try {
          isVersion7OrNewer = int.parse(version.split('.').first) >= 7;
        } catch (e) {
          isVersion7OrNewer = false;
        }
      }
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => HomeScreen(isVersion7OrNewer: isVersion7OrNewer, username: _userController.text),
          ),
        );
      }
    } on MikrotikCredentialsMissingException catch (e) {
      if (mounted) setState(() => _errorMessage = 'خطأ في بيانات الدخول: ${e.message}');
    } on MikrotikConnectionException catch (e) {
      if (mounted) setState(() => _errorMessage = 'خطأ في الاتصال: ${e.message}');
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'فشل الاتصال. تحقق من البيانات أو الشبكة.\n(الخطأ: ${e.toString()})');
    } finally {
      client?.close();
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const adTextStyle = TextStyle(color: Color(0xFFB0A8C1), fontSize: 14);

    Widget adWidget = Marquee(child: Text(_adText, style: adTextStyle, textDirection: TextDirection.rtl));

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Icon(Icons.router_outlined, size: 80, color: Theme.of(context).primaryColor),
              const SizedBox(height: 16),
              const Text('MikroTik Manager', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 8),
              Text('إدارة شبكتك بسهولة وأمان', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Theme.of(context).textTheme.bodyMedium?.color)),
              const SizedBox(height: 32),

              if (_errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(_errorMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent, fontSize: 16)),
                ),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _ipController,
                      decoration: const InputDecoration(labelText: 'IP Address', prefixIcon: Icon(Icons.lan)),
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _portController,
                      decoration: const InputDecoration(labelText: 'Port'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    height: 58,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3E355F),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _isScanning
                        ? const Padding(padding: EdgeInsets.all(12.0), child: CircularProgressIndicator())
                        : IconButton(
                            icon: const Icon(Icons.search),
                            onPressed: _forceDiscoverGateway,
                            tooltip: 'بحث عن البوابة',
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(controller: _userController, decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_outline))),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: _isPasswordObscured,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_isPasswordObscured ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _isPasswordObscured = !_isPasswordObscured),
                  ),
                ),
              ),

              CheckboxListTile(
                title: const Text("تذكرني"),
                value: _rememberMe,
                onChanged: (newValue) => setState(() => _rememberMe = newValue ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                activeColor: Theme.of(context).primaryColor,
              ),

              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isLoading ? null : _login,
                child: _isLoading
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                    : const Text('اتصال', style: TextStyle(fontSize: 18)),
              ),

              const SizedBox(height: 8),
              TextButton(
                onPressed: _launchPrivacyPolicy,
                child: Text(
                  'سياسة الخصوصية',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.white.withOpacity(0.7),
                  ),
                ),
              ),

              const SizedBox(height: 24),
              adWidget,
              const SizedBox(height: 16),

              Column(
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.phone, color: Colors.green, size: 18),
                      SizedBox(width: 8),
                      Text('777042661', style: TextStyle(color: Color(0xFFB0A8C1), fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _launchUrl,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('تحميل تطبيق القحطاني تيليكوم', style: TextStyle(color: Colors.cyanAccent.withOpacity(0.8), fontSize: 14)),
                        const SizedBox(width: 8),
                        Icon(Icons.shop, color: Colors.cyanAccent.withOpacity(0.8), size: 24),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('جميع الحقوق محفوظة © القحطاني تيليكوم', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF5A5278), fontSize: 12)),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

// --- HomeScreen with new UI ---
enum MikrotikMode { userManager, hotspot }

class HomeScreen extends StatefulWidget {
  final bool isVersion7OrNewer;
  final String username;

  const HomeScreen({
    super.key,
    required this.isVersion7OrNewer,
    required this.username,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

// --- Data class for Service items ---
class ServiceItem {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  ServiceItem({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<Map<String, dynamic>> _profiles = [];
  bool _isLoadingProfiles = true;
  final MikrotikMode _selectedMode = MikrotikMode.userManager;
  bool _isNetworkLinked = false;
  String _clientName = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchProfiles();
    _loadLinkStatus();
  }

  Future<void> _loadLinkStatus() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      final isLinked = prefs.getBool('is_network_linked') ?? false;
      String clientName = '';
      if (isLinked) {
        final dataString = prefs.getString('qahtani_linked_data');
        if (dataString != null) {
          try {
            final data = jsonDecode(dataString);
            clientName = data['client_info']?['name'] ?? '';
          } catch (e) {
            print('Error decoding qahtani_linked_data: $e');
          }
        }
      }
      setState(() {
        _isNetworkLinked = isLinked;
        _clientName = clientName;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      if (!mounted) return;
      _loadLinkStatus(); // Reload status on resume
      context.read<MqttService>().checkAndReconnect();
      final isLinked = _isNetworkLinked; // Use the state variable
      if (isLinked) {
        Future.delayed(const Duration(seconds: 1), () {
          if (!mounted) return;
          context.read<MqttService>().publish({'command': 'get_latest_network_details'});
        });
      }
    }
  }

  Future<void> _fetchProfiles() async {
    setState(() => _isLoadingProfiles = true);
    RouterOSClient? client;
    try {
      client = await MikrotikConnector.connect();
      final command = _selectedMode == MikrotikMode.userManager
          ? '/tool/user-manager/profile/print'
          : '/ip/hotspot/user/profile/print';
      final response = await client.talk([command]);
      if (mounted) {
        setState(() {
          _profiles = response.map((p) => Map<String, dynamic>.from(p)).toList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red));
      }
    } finally {
      client?.close();
      if (mounted) setState(() => _isLoadingProfiles = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- قائمة الخدمات لتسهيل إدارتها ---
    final List<ServiceItem> services = [
      ServiceItem(
        title: 'إضافة كرت فردي',
        icon: Icons.person_add_alt_1,
        color: const Color(0xFF5C6BC0), // Indigo
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) =>
                AddUserScreen(profiles: _profiles, isVersion7OrNewer: widget.isVersion7OrNewer, customer: widget.username),
          ));
        },
      ),
      ServiceItem(
        title: 'إضافة كروت جماعية',
        icon: Icons.groups,
        color: const Color(0xFF4CAF50), // Green
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) =>
                BulkAddScreen(profiles: _profiles, isVersion7OrNewer: widget.isVersion7OrNewer, username: widget.username),
          ));
        },
      ),
      ServiceItem(
        title: 'ربط الشبكة',
        icon: Icons.link,
        color: const Color(0xFF42A5F5), // Blue
        onTap: () {
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (context) => const QahtaniLinkScreen()));
        },
      ),
      ServiceItem(
        title: 'طبيب الشبكة',
        icon: Icons.local_hospital_outlined,
        color: const Color(0xFF42A5F5), // Blue
        onTap: () {
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (context) => const NetworkDoctorScreen()));
        },
      ),
      ServiceItem(
        title: 'الملفات المحفوظة',
        icon: Icons.folder_copy,
        color: const Color(0xFFFFA726), // Orange
        onTap: () {
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (context) => const SavedFilesScreen()));
        },
      ),
      ServiceItem(
        title: 'إدارة قوالب PDF',
        icon: Icons.picture_as_pdf,
        color: const Color(0xFF78909C), // Blue Grey
        onTap: () {
          Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => PdfTemplatesScreen(profiles: _profiles)));
        },
      ),
      ServiceItem(
        title: 'استخراج الكروت',
        icon: Icons.document_scanner_outlined,
        color: const Color(0xFFEF5350), // Red
        onTap: () {
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (context) => const ExtractCardsScreen()));
        },
      ),
      ServiceItem(
        title: 'فحص الكرت',
        icon: Icons.search_sharp,
        color: const Color(0xFFAB47BC), // Purple
        onTap: () {
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (context) => const CheckUserScreen()));
        },
      ),
      ServiceItem(
        title: 'الملف الشخصي',
        icon: Icons.account_circle,
        color: const Color(0xFF29B6F6), // Light Blue
        onTap: () {
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (context) => const ProfileScreen()));
        },
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text('الرئيسية', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: CircleAvatar(
            backgroundColor: Theme.of(context).cardColor,
            child: const Icon(Icons.person_outline, color: Colors.white),
          ),
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.notifications_none_rounded),
              onPressed: () {},
              tooltip: 'الإشعارات'),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'تسجيل الخروج',
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
      body: _isLoadingProfiles
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- بطاقة الحالة ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_isNetworkLinked && _clientName.isNotEmpty ? 'العميل' : 'مرحباً بك',
                              style: TextStyle(
                                  color: Theme.of(context).textTheme.bodyMedium?.color, fontSize: 16)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _isNetworkLinked && _clientName.isNotEmpty
                                      ? _clientName
                                      : 'لوحة تحكم MikroTik',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis, // to handle long names
                                ),
                              ),
                              const Icon(Icons.settings_ethernet, color: Colors.white70, size: 28),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // --- عنوان قسم الخدمات ---
                  const Padding(
                    padding: EdgeInsets.only(top: 24.0, right: 24.0, left: 24.0, bottom: 12.0),
                    child: Text(
                      'الخدمات الأساسية',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),

                  // --- شبكة الخدمات ---
                  GridView.builder(
                    padding: const EdgeInsets.all(16.0),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, // 3 أعمدة لمظهر أفضل على معظم الشاشات
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.9, // تعديل النسبة لتناسب المحتوى
                    ),
                    itemCount: services.length,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemBuilder: (context, index) {
                      final service = services[index];
                      return _buildServiceGridItem(
                        title: service.title,
                        icon: service.icon,
                        iconBgColor: service.color,
                        onTap: service.onTap,
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildServiceGridItem({
    required String title,
    required IconData icon,
    required Color iconBgColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        // --- التغيير هنا: تم استخدام لون الأيقونة مع شفافية لخلفية الزر ---
        color: iconBgColor.withOpacity(0.1),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                // --- التغيير هنا: تم زيادة وضوح خلفية الأيقونة للتباين ---
                color: iconBgColor.withOpacity(0.25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 32, color: iconBgColor),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium?.color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
