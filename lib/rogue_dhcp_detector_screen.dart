import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';

class RogueDhcpDetectorScreen extends StatefulWidget {
  const RogueDhcpDetectorScreen({super.key});

  @override
  State<RogueDhcpDetectorScreen> createState() => _RogueDhcpDetectorScreenState();
}

class _RogueDhcpDetectorScreenState extends State<RogueDhcpDetectorScreen> {
  bool _isScanning = false;
  final Set<String> _rogueServers = <String>{};
  final Set<String> _allServers = <String>{}; // To show all responses
  String _status = 'اضغط على زر الفحص لبدء البحث عن خوادم DHCP غير المصرح بها.';
  String? _gatewayIp;

  @override
  void initState() {
    super.initState();
    _getGatewayIp();
  }

  Future<void> _getGatewayIp() async {
    try {
      _gatewayIp = await NetworkInfo().getWifiGatewayIP();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'خطأ في الحصول على IP الراوتر: $e';
      });
    }
  }

  Future<void> _startScan() async {
    if (_gatewayIp == null) {
      setState(() {
        _status = 'لا يمكن بدء الفحص. لم يتم تحديد IP الراوتر. تأكد من اتصالك بالـ Wi-Fi.';
      });
      return;
    }

    setState(() {
      _isScanning = true;
      _rogueServers.clear();
      _allServers.clear(); // Clear all servers list
      _status = 'جاري الفحص... (قد يستغرق 10 ثوانٍ)';
    });

    RawDatagramSocket? socket;
    try {
      // Bind to any address on port 68 (DHCP client port)
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 68);
      socket.broadcastEnabled = true;

      // Listen for DHCP offers
      socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket?.receive();
          if (datagram != null) {
            final serverIp = _extractDhcpServerIp(datagram.data);
            if (serverIp != null) {
              if (mounted) {
                setState(() {
                  _allServers.add(serverIp); // Add any responding server
                  if (serverIp != _gatewayIp) {
                    _rogueServers.add(serverIp); // If not the gateway, it's rogue
                  }
                });
              }
            }
          }
        }
      });

      // Build and send DHCP DISCOVER packet
      final discoverPacket = _buildDiscoverPacket();
      socket.send(discoverPacket, InternetAddress('255.255.255.255'), 67);

      // Wait for 10 seconds to collect offers
      await Future.delayed(const Duration(seconds: 10));

    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'حدث خطأ أثناء الفحص: $e';
        });
      }
    } finally {
      socket?.close();
      if (mounted) {
        setState(() {
          _isScanning = false;
          if (_allServers.isEmpty) {
             _status = 'اكتمل الفحص. لم يتم تلقي أي ردود من أي خادم DHCP.';
          } else if (_rogueServers.isEmpty) {
            _status = 'اكتمل الفحص. تم العثور على خادم شرعي واحد فقط. شبكتك تبدو نظيفة.';
          } else {
            _status = 'اكتمل الفحص! تم العثور على خوادم دخيلة.';
          }
        });
      }
    }
  }

  String? _extractDhcpServerIp(Uint8List data) {
    try {
      // The DHCP options start at offset 240
      int optionOffset = 240;
      
      // Basic validation: Check for magic cookie
      if (data.length < 240 || data[236] != 99 || data[237] != 130 || data[238] != 83 || data[239] != 99) {
        return null; // Not a valid DHCP packet
      }

      while (optionOffset < data.length - 1) {
        final option = data[optionOffset];
        if (option == 255) break; // End of options
        if (option == 0) { // Padding
          optionOffset++;
          continue;
        }
        
        // Ensure we can read the length byte
        if (optionOffset + 1 >= data.length) break;
        final len = data[optionOffset + 1];
        
        // Ensure the full option is within the packet bounds
        if (optionOffset + 2 + len > data.length) break;

        if (option == 54 && len == 4) { // Option 54: Server Identifier
          final serverIpBytes = data.sublist(optionOffset + 2, optionOffset + 2 + len);
          return InternetAddress.fromRawAddress(serverIpBytes).address;
        }
        
        // Move to the next option
        optionOffset += (2 + len);
      }
    } catch (e) {
      // Error parsing packet. In a real app, you might want to log this.
    }
    return null;
  }

  Uint8List _buildDiscoverPacket() {
    final random = Random();
    final xid = Uint8List(4); // Transaction ID
    for (int i = 0; i < 4; i++) {
      xid[i] = random.nextInt(256);
    }

    // Generate a random MAC address for chaddr
    final chaddr = Uint8List(16);
    for (int i = 0; i < 6; i++) {
      chaddr[i] = random.nextInt(256);
    }
    // Set the locally administered bit to avoid conflicts
    chaddr[0] |= 0x02;

    final builder = BytesBuilder();
    // Message type: Boot Request (1)
    builder.addByte(1);
    // Hardware type: Ethernet (1)
    builder.addByte(1);
    // Hardware address length: 6
    builder.addByte(6);
    // Hops: 0
    builder.addByte(0);
    // Transaction ID (xid)
    builder.add(xid);
    // Seconds elapsed: 0
    builder.add([0, 0]);
    // Bootp flags: Broadcast (0x8000)
    builder.add([128, 0]);
    // Client IP, Your IP, Server IP, Gateway IP: all 0.0.0.0
    builder.add(List.filled(16, 0));
    // Client hardware address (chaddr)
    builder.add(chaddr);
    // Server host name (sname): 64 bytes, unused
    builder.add(List.filled(64, 0));
    // Boot file name (file): 128 bytes, unused
    builder.add(List.filled(128, 0));
    // Magic cookie: DHCP
    builder.add([99, 130, 83, 99]);

    // DHCP Options
    // Option 53: DHCP Message Type = DHCP Discover
    builder.add([53, 1, 1]);
    // Option 55: Parameter Request List
    builder.add([55, 4, 1, 3, 6, 15]); // Subnet Mask, Router, DNS, Domain Name
    // End Option
    builder.addByte(255);

    return builder.toBytes();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('كاشف DHCP الدخيل'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: _isScanning ? null : _startScan,
              icon: _isScanning
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search),
              label: Text(_isScanning ? 'جاري الفحص...' : 'بدء الفحص'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _status,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            
            if (_allServers.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text('الخوادم المستجيبة:', style: Theme.of(context).textTheme.titleSmall),
              ),
            if (_allServers.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: _allServers.length,
                  itemBuilder: (context, index) {
                    final serverIp = _allServers.elementAt(index);
                    final isRogue = _rogueServers.contains(serverIp);
                    return Card(
                      color: isRogue ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                      child: ListTile(
                        leading: Icon(Icons.router, color: isRogue ? Colors.redAccent : Colors.green),
                        title: Text(serverIp),
                        subtitle: Text(isRogue ? 'خادم DHCP دخيل' : 'خادم DHCP شرعي (الراوتر)'),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
