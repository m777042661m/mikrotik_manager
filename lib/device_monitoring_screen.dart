import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:router_os_client/router_os_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

enum DeviceStatus { online, offline }

class Device {
  String id;
  String name;
  String ip;
  DeviceStatus status;

  Device({
    required this.id,
    required this.name,
    required this.ip,
    this.status = DeviceStatus.offline,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ip': ip,
        'status': status.toString().split('.').last,
      };

  factory Device.fromJson(Map<String, dynamic> json) => Device(
        id: json['id'],
        name: json['name'],
        ip: json['ip'],
        status: json['status'] == 'online' ? DeviceStatus.online : DeviceStatus.offline,
      );
}

class DeviceMonitoringScreen extends StatefulWidget {
  final RouterOSClient client;

  const DeviceMonitoringScreen({super.key, required this.client});

  @override
  State<DeviceMonitoringScreen> createState() => _DeviceMonitoringScreenState();
}

class _DeviceMonitoringScreenState extends State<DeviceMonitoringScreen> {
  List<Device> _allDevices = [];
  List<Device> _displayedDevices = [];
  bool _isLoading = false;
  final Uuid _uuid = const Uuid();
  bool _showingDisconnectedOnly = false; // Added this line

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() { _isLoading = true; });
    final prefs = await SharedPreferences.getInstance();
    final String? devicesJson = prefs.getString('monitored_devices');
    if (devicesJson != null) {
      final List<dynamic> decodedData = jsonDecode(devicesJson);
      _allDevices = decodedData.map((json) => Device.fromJson(json)).toList();
    }
    _displayedDevices = List.from(_allDevices); // Initially display all loaded devices
    setState(() { _isLoading = false; });
  }

  Future<void> _saveDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final String devicesJson = jsonEncode(_allDevices.map((device) => device.toJson()).toList());
    await prefs.setString('monitored_devices', devicesJson);
  }

  Future<void> _fetchDevices() async {
    setState(() { _isLoading = true; });
    try {
      final neighborResponse = await widget.client.talk(['/ip/neighbor/print']);
      Set<String> currentOnlineIps = {};

      for (var neighbor in neighborResponse) {
        final String? ip = neighbor['address'];
        final String? macAddress = neighbor['mac-address'];
        final String? identity = neighbor['identity'];

        if (ip != null) {
          currentOnlineIps.add(ip);

          // Check if device already exists in _allDevices
          bool found = false;
          for (var device in _allDevices) {
            if (device.ip == ip) {
              device.status = DeviceStatus.online;
              found = true;
              break;
            }
          }

          if (!found) {
            // Add new device
            _allDevices.add(Device(
              id: _uuid.v4(),
              name: identity ?? macAddress ?? 'Unknown Device',
              ip: ip,
              status: DeviceStatus.online,
            ));
          }
        }
      }

      // Update status for all devices in _allDevices
      for (var device in _allDevices) {
        if (!currentOnlineIps.contains(device.ip)) {
          device.status = DeviceStatus.offline;
        } else {
          device.status = DeviceStatus.online; // Ensure it's marked online if it was found
        }
      }

      // _displayedDevices = List.from(_allDevices); // Removed this line
      await _saveDevices();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم جلب الأجهزة بنجاح.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل جلب الأجهزة: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          // Apply the correct filter after fetching
          if (_showingDisconnectedOnly) {
            _displayedDevices = _allDevices.where((device) => device.status == DeviceStatus.offline).toList();
          } else {
            _displayedDevices = List.from(_allDevices);
          }
        });
      }
    }
  }

  void _showDisconnectedDevices() {
    setState(() {
      _displayedDevices = _allDevices.where((device) => device.status == DeviceStatus.offline).toList();
      _showingDisconnectedOnly = true; // Added this line
      if (_displayedDevices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد أجهزة غير متصلة حاليًا.'), backgroundColor: Colors.orange),
        );
      }
    });
  }

  void _showAllDevices() {
    setState(() {
      _displayedDevices = List.from(_allDevices);
      _showingDisconnectedOnly = false; // Added this line
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مراقبة الأجهزة'),
        backgroundColor: Theme.of(context).cardColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchDevices,
            tooltip: 'جلب الأجهزة',
          ),
          // New button for disconnected devices
          IconButton(
            icon: const Icon(Icons.link_off), // Icon for disconnected devices
            onPressed: _isLoading ? null : _showDisconnectedDevices,
            tooltip: 'عرض الأجهزة غير المتصلة',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'all') { // Only 'all' option remains here
                _showAllDevices();
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              // Removed 'disconnected' option
              const PopupMenuItem<String>(
                value: 'all',
                child: ListTile(leading: const Icon(Icons.devices), title: const Text('جميع الأجهزة')),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _displayedDevices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.devices_other, size: 80, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('لا توجد أجهزة للمراقبة', style: TextStyle(fontSize: 22)),
                      const SizedBox(height: 8),
                      const Text('اضغط على زر التحديث لجلب الأجهزة', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  itemCount: _displayedDevices.length,
                  itemBuilder: (context, index) {
                    final device = _displayedDevices[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4.0),
                      color: device.status == DeviceStatus.online ? Colors.green.shade800.withAlpha((255 * 0.8).round()) : Colors.grey.shade700.withAlpha((255 * 0.8).round()),
                      child: ListTile(
                        leading: Icon(
                          device.status == DeviceStatus.online ? Icons.circle : Icons.circle_outlined,
                          color: device.status == DeviceStatus.online ? Colors.greenAccent : Colors.grey,
                        ),
                        title: Text(
                          device.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        subtitle: const Text(
                          device.ip,
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              device.status == DeviceStatus.online ? 'متصل' : 'غير متصل',
                              style: TextStyle(
                                color: device.status == DeviceStatus.online ? Colors.greenAccent : Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (device.status == DeviceStatus.offline)
                              IconButton(
                                icon: const Icon(Icons.refresh, color: Colors.orange),
                                onPressed: () => _checkSingleDevice(device),
                                tooltip: 'فحص الجهاز',
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Future<void> _checkSingleDevice(Device device) async {
    setState(() { _isLoading = true; });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('جاري فحص ${device.name}...')),
    );

    try {
      final neighborResponse = await widget.client.talk(['/ip/neighbor/print']);
      Set<String> onlineIps = {};
      for (var neighbor in neighborResponse) {
        if (neighbor['address'] != null) {
          onlineIps.add(neighbor['address']!);
        }
      }

      final newStatus = onlineIps.contains(device.ip) ? DeviceStatus.online : DeviceStatus.offline;

      // Update status in _allDevices
      final deviceIndexInAll = _allDevices.indexWhere((d) => d.id == device.id);
      if (deviceIndexInAll != -1) {
        _allDevices[deviceIndexInAll].status = newStatus;
      }

      // Update status in _displayedDevices and re-filter if necessary
      if (mounted) {
        setState(() {
          final deviceIndexInDisplayed = _displayedDevices.indexWhere((d) => d.id == device.id);
          if (deviceIndexInDisplayed != -1) {
            _displayedDevices[deviceIndexInDisplayed].status = newStatus;
          }

          // Re-apply filter to _displayedDevices if currently filtered
          if (_showingDisconnectedOnly) {
            _displayedDevices = _allDevices.where((d) => d.status == DeviceStatus.offline).toList();
          } else {
            _displayedDevices = List.from(_allDevices);
          }
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم فحص ${device.name}: ${newStatus == DeviceStatus.online ? 'متصل' : 'غير متصل'}'), backgroundColor: newStatus == DeviceStatus.online ? Colors.green : Colors.red),
      );

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل فحص الجهاز: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }
}
