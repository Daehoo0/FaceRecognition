import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:intl/intl.dart';
import 'package:ta/pages/admin/listuser.dart';
import 'package:ta/pages/admin/riport.dart';
import 'package:ta/pages/admin/setting.dart';
import 'package:ta/pages/login.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;

class HomeAdmin extends StatefulWidget {
  // @override
  // _HomeAdminState createState() => _HomeAdminState();
  final Map<String, dynamic> userData;
  const HomeAdmin({Key? key, required this.userData}) : super(key: key);
  @override
  _HomeAdminState createState() => _HomeAdminState();
}

class _HomeAdminState extends State<HomeAdmin> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    ListUserPage(),
    ReportKehadiranPage(),
    SettingPage(),
  ];

  final List<String> _pageTitles = [
    'List User',
    'Report',
    'Setting',
  ];

  @override
  void initState() {
    super.initState();
    createAttendanceDataForAllStaff();
  }
  Future<void> createAttendanceDataForAllStaff() async {
    try {
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

      print("Attendance data created for all eligible staff members");

    } catch (e) {
      print("Error creating attendance data: $e");
    }
  }

  void _onItemTapped(int index) {
    if (index == 3) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => LoginPage()),
            (route) => false,
      );
    } else {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      // Tampilan untuk Web
      return Scaffold(
        // appBar: AppBar(title: Text(_pageTitles[_selectedIndex])),
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onItemTapped,
              labelType: NavigationRailLabelType.all,
              destinations: [
                NavigationRailDestination(icon: Icon(Icons.list), label: Text('Users')),
                NavigationRailDestination(icon: Icon(Icons.report), label: Text('Reports')),
                NavigationRailDestination(icon: Icon(Icons.settings), label: Text('Settings')),
                NavigationRailDestination(icon: Icon(Icons.logout), label: Text('Logout')),
              ],
            ),
            Expanded(child: _pages[_selectedIndex]),
          ],
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      // Tampilan untuk Windows & MacOS
      return Scaffold(
        appBar: AppBar(title: Text(_pageTitles[_selectedIndex])),
        body: _pages[_selectedIndex],
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          items: [
            BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Users'),
            BottomNavigationBarItem(icon: Icon(Icons.report), label: 'Reports'),
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
            BottomNavigationBarItem(icon: Icon(Icons.logout), label: 'Logout'),
          ],
        ),
      );
    } else {
      // Tampilan untuk Android & iOS
      return Scaffold(
        body: IndexedStack(
          index: _selectedIndex,
          children: _pages,
        ),
        bottomNavigationBar: CurvedNavigationBar(
          backgroundColor: Colors.white,
          color: Colors.purple,
          buttonBackgroundColor: Colors.deepPurple,
          height: 60,
          index: _selectedIndex,
          items: <Widget>[
            Icon(Icons.list, size: 30, color: Colors.white),
            Icon(Icons.report, size: 30, color: Colors.white),
            Icon(Icons.settings, size: 30, color: Colors.white),
            Icon(Icons.logout, size: 30, color: Colors.white),
          ],
          onTap: _onItemTapped,
        ),
      );
    }
  }
}
