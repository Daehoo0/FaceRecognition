import 'package:flutter/material.dart';
import 'package:ta/pages/kepsek/izin.dart';
import 'package:ta/pages/kepsek/riport.dart';
import 'package:ta/pages/kepsek/kehadiran.dart';
import 'package:ta/pages/login.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class HomeKepsek extends StatefulWidget {
  final Map<String, dynamic> userData;

  const HomeKepsek({Key? key, required this.userData}) : super(key: key);
  @override
  _HomeKepsekState createState() => _HomeKepsekState();
}

class _HomeKepsekState extends State<HomeKepsek> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    ListKehadiranPage(),
    KonfirmasiIzinPage(),
    ReportKehadiranPage(),
  ];

  final List<String> _pageTitles = [
    'List User',
    'Report',
    'Setting',
  ];

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
        items: <Widget>[
          Icon(Icons.today, size: 30, color: Colors.white),
          Icon(Icons.check, size: 30, color: Colors.white),
          Icon(Icons.bar_chart, size: 30, color: Colors.white),
          Icon(Icons.logout, size: 30, color: Colors.white),
        ],
        onTap: (index) {
          if (index == 3) {
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
        },
      ),
    );
  }
}