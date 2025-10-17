import 'package:flutter/material.dart';
import 'package:router_os_client/router_os_client.dart';
import 'network_map_screen.dart';
import 'device_monitoring_screen.dart'; // Import the new screen

class NetworkToolsScreen extends StatelessWidget {
  final RouterOSClient client;

  const NetworkToolsScreen({super.key, required this.client});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('أدوات الشبكة'),
        backgroundColor: Theme.of(context).cardColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.map_outlined, size: 28),
              label: const Text('خريطة الشبكة'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00695C)),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => NetworkMapScreen(client: client),
                ));
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.devices_other, size: 28),
              label: const Text('مراقبة الأجهزة'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => DeviceMonitoringScreen(client: client),
                ));
              },
            ),
          ],
        ),
      ),
    );
  }
}
