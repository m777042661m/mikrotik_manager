import 'package:flutter/material.dart';
import 'network_map_screen.dart';
import 'rogue_dhcp_detector_screen.dart';

class NetworkDoctorScreen extends StatelessWidget {
  const NetworkDoctorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('طبيب الشبكة'),
        centerTitle: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(16.0),
        crossAxisSpacing: 16.0,
        mainAxisSpacing: 16.0,
        children: <Widget>[
          _buildServiceGridItem(
            title: 'خريطة الشبكة',
            icon: Icons.hub_outlined,
            iconBgColor: const Color(0xFF26A69A), // Teal
            context: context,
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (context) => const NetworkMapScreen()));
            },
          ),
          _buildServiceGridItem(
            title: 'كاشف DHCP الدخيل',
            icon: Icons.dvr,
            iconBgColor: const Color(0xFFEF5350), // Red
            context: context,
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (context) => const RogueDhcpDetectorScreen()));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildServiceGridItem({
    required String title,
    required IconData icon,
    required Color iconBgColor,
    required BuildContext context,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        color: iconBgColor.withOpacity(0.1),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
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
