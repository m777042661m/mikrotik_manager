// lib/check_user_screen.dart

import 'package:flutter/material.dart';
import 'package:router_os_client/router_os_client.dart';

import 'mikrotik_connector.dart';

class CheckUserScreen extends StatefulWidget {
  const CheckUserScreen({super.key});

  @override
  State<CheckUserScreen> createState() => _CheckUserScreenState();
}

class _CheckUserScreenState extends State<CheckUserScreen> {
  final _usernameController = TextEditingController();
  bool _isLoading = false;
  Map<String, dynamic>? _userDetails;
  List<Map<String, dynamic>> _userSessions = [];
  String _statusMessage = 'أدخل اسم مستخدم للبحث';

  Future<void> _checkUser() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرجاء إدخال اسم مستخدم أولاً'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _userDetails = null;
      _userSessions = [];
      _statusMessage = 'جاري البحث عن "$username"...';
    });

    RouterOSClient? client;
    try {
      client = await MikrotikConnector.connect();

      final userResponse = await client.talk([
        '/tool/user-manager/user/print',
        '?username=$username',
      ]);

      if (userResponse.isEmpty || userResponse[0].isEmpty) {
        setState(() {
          _statusMessage = 'المستخدم "$username" غير موجود.';
          _isLoading = false;
        });
        return;
      }
      
      final details = Map<String, dynamic>.from(userResponse[0]);

      final sessionResponse = await client.talk([
        '/tool/user-manager/session/print',
        '?user=$username',
      ]);
      
      final sessions = sessionResponse
          .map((session) => Map<String, dynamic>.from(session))
          .toList();

      setState(() {
        _userDetails = details;
        _userSessions = sessions;
        _isLoading = false;
      });

    } on MikrotikCredentialsMissingException catch (e) {
      setState(() {
        _statusMessage = 'خطأ في بيانات الدخول: ${e.message}';
        _isLoading = false;
      });
    } on MikrotikConnectionException catch (e) {
      setState(() {
        _statusMessage = 'خطأ في الاتصال: ${e.message}';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'حدث خطأ: ${e.toString()}';
        _isLoading = false;
      });
    } finally {
      client?.close();
    }
  }

  String _formatBytes(String bytesStr) {
    final bytes = double.tryParse(bytesStr) ?? 0.0;
    if (bytes < 1024) return '${bytes.toStringAsFixed(2)} B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(2)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(2)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }
  
  String _formatDuration(String durationStr) {
      return durationStr.replaceAll('w', ' أسابيع ')
                        .replaceAll('d', ' أيام ')
                        .replaceAll('h', ' ساعات ')
                        .replaceAll('m', ' دقائق ')
                        .replaceAll('s', ' ثواني');
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('فحص الكرت'),
        backgroundColor: Theme.of(context).cardColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _usernameController,
              decoration: InputDecoration(
                labelText: 'اسم المستخدم للكرت',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _checkUser,
                ),
              ),
              onSubmitted: (_) => _checkUser(),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _isLoading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(_statusMessage),
                        ],
                      ),
                    )
                  : _userDetails == null
                      ? Center(child: Text(_statusMessage, style: const TextStyle(fontSize: 16, color: Colors.grey)))
                      : _buildUserDetails(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserDetails() {
    return ListView(
      children: [
        _buildInfoCard(
          'معلومات أساسية',
          Icons.person_outline,
          [
            _buildInfoTile('اسم المستخدم:', _userDetails!['username'] ?? 'N/A'),
            _buildInfoTile('الفئة (Profile):', _userDetails!['actual-profile'] ?? 'N/A'),
            _buildInfoTile('الحالة:', (_userDetails!['disabled'] == 'true') ? 'معطل' : 'نشط',
             valueColor: (_userDetails!['disabled'] == 'true') ? Colors.redAccent : Colors.green
            ),
             _buildInfoTile('الأجهزة المسموحة:', _userDetails!['shared-users'] ?? 'N/A'),
          ],
        ),
        _buildInfoCard(
          'حدود الاستخدام',
          Icons.data_usage_outlined,
          [
            _buildInfoTile('إجمالي الرفع:', _formatBytes(_userDetails!['upload-used'] ?? '0')),
            _buildInfoTile('إجمالي التنزيل:', _formatBytes(_userDetails!['download-used'] ?? '0')),
            _buildInfoTile('حد الرفع:', _formatBytes(_userDetails!['upload-limit'] ?? '0')),
            _buildInfoTile('حد التنزيل:', _formatBytes(_userDetails!['download-limit'] ?? '0')),
            _buildInfoTile('الوقت المستخدم:', _formatDuration(_userDetails!['uptime-used'] ?? '0s')),
            _buildInfoTile('حد الوقت:', _formatDuration(_userDetails!['uptime-limit'] ?? '0s')),
          ],
        ),
        if (_userSessions.isNotEmpty)
          _buildInfoCard(
            'الجلسات النشطة حالياً (${_userSessions.length})',
            Icons.wifi_tethering,
            _userSessions.expand((session) => [
              const Divider(),
              _buildInfoTile('عنوان الماك:', session['caller-id'] ?? 'N/A'),
              _buildInfoTile('عنوان IP:', session['ip-address'] ?? 'N/A'),
              _buildInfoTile('مدة الاتصال:', _formatDuration(session['uptime'] ?? '0s')),
              _buildInfoTile('الرفع في الجلسة:', _formatBytes(session['upload'] ?? '0')),
              _buildInfoTile('التنزيل في الجلسة:', _formatBytes(session['download'] ?? '0')),
            ]).toList()..removeAt(0),
          ),
      ],
    );
  }

  Widget _buildInfoCard(String title, IconData icon, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).primaryColor),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[400])),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
