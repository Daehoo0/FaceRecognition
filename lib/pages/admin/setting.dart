import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:ta/pages/admin/absenmanual.dart';
import 'package:ta/pages/admin/jadwalsekolah.dart';
import 'package:ta/pages/admin/atur_jaringan.dart';
import 'package:ta/pages/admin/aturguru.dart';
import 'package:ta/pages/admin/keamanan.dart';
import 'package:ta/pages/admin/addfinger.dart';
import 'package:ta/pages/admin/absenfinger.dart';
import 'package:ta/pages/admin/registrasi.dart';

class SettingPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Pengaturan")),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade100, Colors.blue.shade50],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.macOS) {
              return _buildDesktopAndWebView(context, constraints.maxWidth);
            } else {
              return _buildMobileView(context);
            }
          },
        ),
      ),
    );
  }

  // 🔹 Tampilan Web & Desktop (GridView fleksibel)
  Widget _buildDesktopAndWebView(BuildContext context, double maxWidth) {
    int crossAxisCount = (maxWidth ~/ 220).clamp(2, 4); // Min 2, Max 4 kolom

    return Padding(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1, // Proporsi kotak tetap
        ),
        itemCount: _settingItems.length,
        itemBuilder: (context, index) {
          return _buildCard(_settingItems[index], context);
        },
      ),
    );
  }

  // 🔹 Tampilan Mobile (GridView agar responsif)
  Widget _buildMobileView(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180, // Setiap kartu maksimal selebar 180px
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1, // Proporsi tetap
        ),
        itemCount: _settingItems.length,
        itemBuilder: (context, index) {
          return _buildCard(_settingItems[index], context);
        },
      ),
    );
  }

  // 🔹 Data menu pengaturan
  final List<Map<String, dynamic>> _settingItems = [
    {'title': "Jaringan", 'icon': Icons.wifi, 'route': AturJaringanPage()},
    {'title': "Jadwal Sekolah", 'icon': Icons.calendar_today, 'route': SchedulePage()},
    {'title': "Jadwal Guru", 'icon': Icons.person, 'route': AturJadwalGuruPage()},
    {'title': "Ubah Kata Sandi", 'icon': Icons.lock, 'route': EditProfilePage()},
    {'title': "Absen", 'icon': Icons.check, 'route': Absenmanual()},
    {'title': "Registrasi Wajah", 'icon': Icons.face, 'route': DaftarUserRegisFacePage()},
    // {'title': "Absen Finger", 'icon': Icons.check, 'route': FingerprintPage()},
    // {'title': "Tambah Finger", 'icon': Icons.add_circle_rounded, 'route': AddFingerprintPage()},
  ];

  // 🔹 Widget untuk Card
  Widget _buildCard(Map<String, dynamic> item, BuildContext context) {
    return InkWell(
      onTap: () {
        if (item['route'] != null) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => item['route']),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("${item['title']} belum tersedia")),
          );
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withOpacity(0.2),
              blurRadius: 8,
              spreadRadius: 2,
              offset: Offset(2, 4),
            ),
          ],
        ),
        padding: EdgeInsets.all(16),
        height: 120,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item['icon'], size: 48, color: Colors.blue.shade700),
            SizedBox(height: 12),
            Text(
              item['title'],
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
