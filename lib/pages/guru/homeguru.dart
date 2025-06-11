import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Tambahkan import ini untuk kIsWeb
import 'package:ta/pages/login.dart';
import 'package:ta/pages/guru/izin.dart';
import 'package:ta/pages/guru/kehadiran.dart';
import 'package:ta/pages/guru/absen.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class HomeGuru extends StatefulWidget {
  final Map<String, dynamic> userData;

  const HomeGuru({Key? key, required this.userData}) : super(key: key);
  @override
  _HomeGuruState createState() => _HomeGuruState();
}

class _HomeGuruState extends State<HomeGuru> {
  int _selectedIndex = 0;
  User? _user;
  Map<String, dynamic>? userData;
  int absenMasuk = 0;
  int absenPulang = 0;

  // Fungsi untuk mengecek apakah platform mendukung face recognition
  bool get _isFaceRecognitionSupported {
    if (kIsWeb) return false; // Web tidak mendukung
    if (Platform.isWindows) return false; // Windows tidak mendukung
    return Platform.isAndroid || Platform.isIOS; // Hanya Android dan iOS
  }

  // Pages berdasarkan platform
  List<Widget> get _pages {
    if (_isFaceRecognitionSupported) {
      return [
        KehadiranPage(),
        FaceAbsensiPage(),
        IzinPage(),
      ];
    } else {
      return [
        KehadiranPage(),
        IzinPage(),
      ];
    }
  }

  // Page titles berdasarkan platform
  List<String> get _pageTitles {
    if (_isFaceRecognitionSupported) {
      return [
        'List User',
        'Report',
        'Setting',
      ];
    } else {
      return [
        'List User',
        'Setting',
      ];
    }
  }

  // Navigation items berdasarkan platform
  List<Widget> get _navigationItems {
    if (_isFaceRecognitionSupported) {
      return [
        Icon(Icons.report, size: 30, color: Colors.white),
        Icon(Icons.face, size: 30, color: Colors.white),
        Icon(Icons.send, size: 30, color: Colors.white),
        Icon(Icons.logout, size: 30, color: Colors.white),
      ];
    } else {
      return [
        Icon(Icons.report, size: 30, color: Colors.white),
        Icon(Icons.send, size: 30, color: Colors.white),
        Icon(Icons.logout, size: 30, color: Colors.white),
      ];
    }
  }

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<String> getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      return androidInfo.id ?? 'Unknown';
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      return iosInfo.identifierForVendor ?? 'Unknown';
    } else {
      return 'Unknown';
    }
  }

  Future<void> _loadUserData() async {
    _user = FirebaseAuth.instance.currentUser;
    if (_user != null) {
      try {
        DocumentReference userRef = FirebaseFirestore.instance
            .collection('users')
            .doc(_user!.uid);

        DocumentSnapshot userDoc = await userRef.get();

        if (!userDoc.exists || userDoc.data() == null) return;

        userData = userDoc.data() as Map<String, dynamic>;

        // Skip device check untuk web dan windows
        if (!kIsWeb && !Platform.isWindows) {
          String deviceId = await getDeviceId();

          if (userData!['device'] == null || userData!['device'] == '' || userData!['device'].toString().trim().isEmpty) {
            // Field 'device' belum ada atau kosong, simpan deviceId sekarang
            await userRef.update({'device': deviceId});
          } else if (userData!['device'] != deviceId) {
            // Jika device tidak cocok, tampilkan alert
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: Text("Peringatan"),
                content: Text("Anda sedang login di perangkat yang bukan milik Anda."),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text("OK"),
                  ),
                ],
              ),
            );
          }
        }

        // Simpan token FCM
        final token = await FirebaseMessaging.instance.getToken();
        await userRef.update({'fcm_token': token});

        // Get current date information
        DateTime now = DateTime.now();
        String today = DateFormat('yyyy-MM-dd').format(now);
        String dayOfWeek = DateFormat('EEEE').format(now);
        String currentMonth = DateFormat('MMMM').format(now);

        // Skip if today is Sunday
        if (dayOfWeek == 'Sunday') return;

        // Check if today is a red day (holiday)
        DocumentSnapshot redDayDoc = await FirebaseFirestore.instance
            .collection('red_days')
            .doc(today)
            .get();

        if (redDayDoc.exists) return; // Skip if today is a holiday

        // Get all users with specific roles
        QuerySnapshot usersSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('role', whereIn: ['Guru', 'Staff', 'Kepala Sekolah'])
            .get();

        // Process each user
        for (var userDoc in usersSnapshot.docs) {
          Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
          String userId = userDoc.id;
          String userName = userData['name'] ?? "Anonymous";

          // Check if user has this day as their off day
          List<dynamic>? hariLiburUser = userData['hari_libur'];
          if (hariLiburUser != null && hariLiburUser.contains(dayOfWeek)) {
            continue; // Skip this user if today is their day off
          }

          // Check if user has approved absence request for today
          QuerySnapshot izinSnapshot = await FirebaseFirestore.instance
              .collection('izin')
              .where('user_id', isEqualTo: userId)
              .where('tanggal', isEqualTo: today)
              .where('jenis', isEqualTo: 'Tidak Masuk')
              .where('status', isEqualTo: 'Diterima')
              .get();

          if (izinSnapshot.docs.isNotEmpty) {
            continue; // Skip this user if they have approved absence
          }

          // Create attendance document for this user if it doesn't exist
          DocumentReference userAttendanceRef = FirebaseFirestore.instance
              .collection('absen')
              .doc('${userId}_$today');

          DocumentSnapshot attendanceSnapshot = await userAttendanceRef.get();

          if (!attendanceSnapshot.exists) {
            // Create new attendance record
            await userAttendanceRef.set({
              'user_id': userId,
              'user_name': userName,
              'tanggal': today,
              'absen_masuk': 0,
              'absen_pulang': 0,
              'waktu_masuk': null,
              'waktu_pulang': null,
              'keterangan': "Belum masuk",
              'hari': dayOfWeek,
              'bulan': currentMonth,
            });
          }
        }
      } catch (e) {
        print("Error loading user data: $e");
      }
    }
  }

  void _onNavigationTap(int index) {
    if (_isFaceRecognitionSupported) {
      // Logic untuk mobile (Android/iOS) - 4 items
      if (index == 3) {
        // Logout
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => LoginPage(),
          ),
              (route) => false,
        );
      } else {
        setState(() {
          _selectedIndex = index;
        });
      }
    } else {
      // Logic untuk web/windows - 3 items
      if (index == 2) {
        // Logout (index 2 karena tidak ada FaceAbsensi)
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => LoginPage(),
          ),
              (route) => false,
        );
      } else {
        setState(() {
          _selectedIndex = index;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: CurvedNavigationBar(
        backgroundColor: Colors.white,
        color: Colors.blue,
        buttonBackgroundColor: Colors.blueAccent,
        height: 60,
        index: _selectedIndex,
        items: _navigationItems,
        onTap: _onNavigationTap,
      ),
    );
  }
}