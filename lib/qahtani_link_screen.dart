import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mqtt_service.dart';

class QahtaniLinkScreen extends StatefulWidget {
  const QahtaniLinkScreen({super.key});

  @override
  State<QahtaniLinkScreen> createState() => _QahtaniLinkScreenState();
}

class _QahtaniLinkScreenState extends State<QahtaniLinkScreen> {
  late MqttService _mqttService;
  StreamSubscription? _mqttSubscription;

  final _accountIdController = TextEditingController();
  final _verificationCodeController = TextEditingController();
  
  // --- متغيرات جديدة لتتبع الحالة ---
  String? _correlationId; // سيستخدم كـ Job ID لعملية التحقق
  Timer? _verificationTimer;
  bool _isJobAcknowledged = false;
  // ---------------------------------

  // UI State
  bool _isLoading = true;
  bool _isLinked = false;
  bool _isAwaitingCode = false;
  String? _errorMessage;
  String _statusMessage = 'جاري تحميل البيانات...';

  // Linked Data
  Map<String, dynamic> _linkedData = {};

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mqttService = Provider.of<MqttService>(context, listen: false);
    _setupMqttListener();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    final isLinked = prefs.getBool('is_network_linked') ?? false;

    if (isLinked) {
      final dataString = prefs.getString('qahtani_linked_data');
      if (dataString != null && mounted) {
        setState(() {
          _linkedData = jsonDecode(dataString);
          _isLinked = true;
          _isLoading = false;
        });
      }
      Future.delayed(const Duration(milliseconds: 200), () {
        if(mounted) {
          _mqttService.publish({'command': 'get_latest_network_details'});
        }
      });
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _resetStateForNewVerification() {
    setState(() {
      _isLoading = false;
      _isAwaitingCode = false;
      _verificationCodeController.clear();
      _accountIdController.clear();
      _errorMessage = null;
    });
    _verificationTimer?.cancel();
    _correlationId = null;
    _isJobAcknowledged = false;
  }

  void _setupMqttListener() {
    _mqttSubscription?.cancel();
    _mqttSubscription = _mqttService.messages.listen((message) {
      if (!mounted) return;

      final status = message['status'];
      final job_id = message['job_id'] ?? message['correlation_id'];

      // تجاهل الرسائل التي لا تخص العملية الحالية
      if (_correlationId != null && job_id != _correlationId) return;

      switch (status) {
        // --- الحالات الجديدة لتتبع الطلب ---
        case 'acknowledged':
          print("✅ [التحقق] تم استلام الطلب من السكربت.");
          setState(() {
            _isJobAcknowledged = true;
            _statusMessage = 'تم استلام طلبك، جاري المعالجة...';
          });
          break;
        
        case 'job_status_response':
          final jobStatus = message['job_status'];
          print("ℹ️ [التحقق] حالة الطلب هي: $jobStatus");
          if (jobStatus == 'not_found' && _isAwaitingCode) {
            print("🔁 [التحقق] الطلب لم يوجد، جاري إعادة الإرسال...");
             _verificationTimer?.cancel();
            _confirmVerificationCode(); // إعادة إرسال الطلب
          }
          break;
        // ---------------------------------

        case 'code_sent':
          setState(() {
            _isLoading = false;
            _isAwaitingCode = true;
            _errorMessage = null;
            _statusMessage = message['message'] ?? 'تم إرسال الرمز.';
          });
          break;
        
        case 'success':
          _verificationTimer?.cancel();
          _handleSuccess(message['data']);
          break;
          
        case 'verification_failed':
          _verificationTimer?.cancel();
          setState(() {
            _isLoading = false;
            _errorMessage = message['message'] ?? 'فشل التحقق.';
            _isAwaitingCode = true; // ابق في شاشة الكود
          });
          break;
        
        case 'error':
          _verificationTimer?.cancel();
          setState(() {
            _isLoading = false;
            _errorMessage = message['message'] ?? 'حدث خطأ غير متوقع.';
            _isAwaitingCode = _isAwaitingCode; // ابق في نفس الحالة
          });
          break;
      }
    });
  }

  Future<void> _handleSuccess(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_network_linked', true);
    await prefs.setString('qahtani_linked_data', jsonEncode(data));
    if (mounted) {
      setState(() {
        _linkedData = data;
        _isLinked = true;
        _isLoading = false;
        _isAwaitingCode = false;
      });
    }
  }

  void _requestVerificationCode() {
    if (_accountIdController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'الرجاء إدخال رقم الحساب أولاً.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _statusMessage = 'جاري طلب رمز التحقق...';
      _correlationId = _mqttService.generateUniqueId();
    });
    _mqttService.publish({
      'command': 'request_verification_code',
      'account_id': _accountIdController.text.trim(),
      'correlation_id': _correlationId,
    });
  }

  // ==== تم تعديل هذه الدالة بالكامل ====
  void _confirmVerificationCode() {
    if (_verificationCodeController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'الرجاء إدخال رمز التحقق.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isJobAcknowledged = false; // إعادة تعيين عند كل محاولة
      _statusMessage = 'جاري إرسال الرمز للتأكيد...';
    });
    
    // إلغاء أي مؤقت سابق وبدء مؤقت جديد
    _verificationTimer?.cancel();
    _verificationTimer = Timer(const Duration(seconds: 7), _checkVerificationStatus);

    _mqttService.publish({
      'command': 'verify_code_and_get_details',
      'code': _verificationCodeController.text.trim(),
      'correlation_id': _correlationId, // استخدام نفس المعرف
    });
  }
  
  // ==== دالة جديدة لفحص حالة الطلب بعد انتهاء المهلة ====
  void _checkVerificationStatus() {
    if (!mounted || !_isLoading) return;

    // إذا استلمنا تأكيداً بالوصول، لا تفعل شيئاً وانتظر الرد
    if (_isJobAcknowledged) {
      print("⏰ [التحقق] انتهت المهلة، لكن الطلب تم استلامه. ننتظر الرد النهائي.");
      setState(() {
          _statusMessage = 'المعالجة تستغرق وقتاً أطول من المعتاد...';
      });
      return;
    }
    
    print("⏰ [التحقق] لم يتم استلام تأكيد، جاري فحص حالة الطلب...");
    setState(() {
        _statusMessage = 'الشبكة بطيئة، جاري التحقق من حالة الطلب...';
    });

    _mqttService.publish({
      'command': 'get_job_status',
      'job_id': _correlationId,
    });
  }


  Future<void> _unlinkAccount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('is_network_linked');
    await prefs.remove('qahtani_linked_data');
    _resetStateForNewVerification();
    setState(() {
      _isLinked = false;
      _linkedData = {};
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ربط الشبكة بالقحطاني'),
        backgroundColor: Theme.of(context).cardColor,
        actions: [
          if (_isLinked)
            IconButton(
              icon: const Icon(Icons.link_off),
              tooltip: 'إلغاء الربط',
              onPressed: _unlinkAccount,
            )
        ],
      ),
      body: Center(
        child: _isLoading
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_statusMessage, style: const TextStyle(fontSize: 16), textAlign: TextAlign.center,),
                ],
              )
            : _isLinked
                ? _buildLinkedView()
                : _buildUnlinkedView(),
      ),
    );
  }

  Widget _buildLinkedView() {
    final clientInfo = _linkedData['client_info'] ?? {};
    final networkDetails = _linkedData['network_details'] ?? {};
    final units = networkDetails['units'] as List? ?? [];

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          const Icon(Icons.cloud_done, color: Colors.green, size: 80),
          const SizedBox(height: 16),
          const Center(
              child: Text('الشبكة مرتبطة بنجاح',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.green))),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(Icons.person),
              title: Text(clientInfo['name'] ?? 'غير متوفر'),
              subtitle: const Text('اسم العميل'),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.router),
              title: Text(networkDetails['network_name'] ?? 'غير متوفر'),
              subtitle: const Text('اسم الشبكة'),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.confirmation_number),
              title: Text(_linkedData['account_id'] ?? 'غير متوفر'),
              subtitle: const Text('رقم حساب القحطاني'),
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text('الفئات (الباقات) المتاحة:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
          if (units.isEmpty) const Center(child: Text('لا توجد فئات متاحة حالياً.'))
          else ...units
              .map((unit) => Card(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: ListTile(
                      leading: const Icon(Icons.wifi_tethering,
                          color: Colors.cyan),
                      title: Text(unit['name'] ?? 'فئة غير مسماة'),
                    ),
                  ))
              .toList(),
        ],
      ),
    );
  }

  Widget _buildUnlinkedView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.link_off, color: Colors.orange, size: 80),
          const SizedBox(height: 16),
          Center(
              child: Text(
                  _isAwaitingCode ? 'التحقق بخطوتين' : 'ربط حساب جديد',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold))),
          const SizedBox(height: 24),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Text(_errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.redAccent, fontSize: 16)),
            ),
          if (_isAwaitingCode)
            Text(_statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.amber, fontSize: 16)),
          const SizedBox(height: 16),
          if (!_isAwaitingCode)
            TextField(
              controller: _accountIdController,
              decoration: const InputDecoration(
                  labelText: 'أدخل رقم حسابك في القحطاني',
                  prefixIcon: Icon(Icons.person_pin)),
              keyboardType: TextInputType.number,
            )
          else
            TextField(
              controller: _verificationCodeController,
              decoration: const InputDecoration(
                  labelText: 'أدخل رمز التحقق المرسل إلى هاتفك',
                  prefixIcon: Icon(Icons.password)),
              keyboardType: TextInputType.number,
            ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isAwaitingCode
                ? _confirmVerificationCode
                : _requestVerificationCode,
            child:
                Text(_isAwaitingCode ? 'تأكيد الرمز' : 'طلب رمز التحقق'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _accountIdController.dispose();
    _verificationCodeController.dispose();
    _mqttSubscription?.cancel();
    _verificationTimer?.cancel();
    super.dispose();
  }
}