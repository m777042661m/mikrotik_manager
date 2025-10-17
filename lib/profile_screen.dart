import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  bool _isLinked = false;
  Map<String, dynamic> _profileData = {};

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    final isLinked = prefs.getBool('is_network_linked') ?? false;

    if (isLinked) {
      final dataString = prefs.getString('qahtani_linked_data');
      if (dataString != null) {
        setState(() {
          _profileData = jsonDecode(dataString);
          _isLinked = true;
        });
      }
    }
    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الملف الشخصي للشبكة'),
        backgroundColor: Theme.of(context).cardColor,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isLinked
              ? _buildProfileView()
              : _buildNotLinkedView(),
    );
  }

  Widget _buildProfileView() {
    final clientInfo = _profileData['client_info'] ?? {};
    final networkDetails = _profileData['network_details'] ?? {};
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          const Icon(Icons.account_circle, size: 100, color: Colors.deepOrange),
          const SizedBox(height: 16),
          _buildInfoCard(
            context,
            title: clientInfo['name'] ?? 'غير متوفر',
            subtitle: 'اسم العميل',
            icon: Icons.person_outline,
          ),
          _buildInfoCard(
            context,
            title: clientInfo['phone']?.toString() ?? 'غير متوفر',
            subtitle: 'رقم هاتف العميل',
            icon: Icons.phone_outlined,
          ),
          _buildInfoCard(
            context,
            title: _profileData['account_id'] ?? 'غير متوفر',
            subtitle: 'رقم حساب القحطاني',
            icon: Icons.confirmation_number_outlined,
          ),
          _buildInfoCard(
            context,
            title: networkDetails['network_name'] ?? 'غير متوفر',
            subtitle: 'اسم الشبكة المرتبطة',
            icon: Icons.wifi_outlined,
          ),
           _buildInfoCard(
            context,
            title: networkDetails['network_id'] ?? 'غير متوفر',
            subtitle: 'معرّف الشبكة (Network ID)',
            icon: Icons.hub_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, {required String title, required String subtitle, required IconData icon}) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).primaryColor, size: 30),
        title: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: Colors.grey[400]),
        ),
      ),
    );
  }

  Widget _buildNotLinkedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 80, color: Colors.amber),
            const SizedBox(height: 20),
            const Text(
              'لم يتم ربط الشبكة!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'الرجاء الذهاب إلى شاشة "ربط الشبكة بالقحطاني" لإكمال عملية الربط أولاً.',
              style: TextStyle(fontSize: 16, color: Colors.grey[400]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}