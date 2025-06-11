import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ta/pages/admin/homeadmin.dart';
import 'package:ta/pages/guru/homeguru.dart';
import 'package:ta/pages/kepsek/homepeksek.dart';
import 'package:ta/pages/staff/homestaff.dart';
import 'package:ta/services/auth_services.dart';
import 'package:lottie/lottie.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;

  Future<void> _login() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final String username = _usernameController.text.trim();
    final String password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _showErrorDialog('Username/Nomor dan kata sandi tidak boleh kosong!');
      setState(() => _isLoading = false);
      return;
    }else if (username.isEmpty ) {
      _showErrorDialog('Username/Nomor tidak boleh kosong!');
      setState(() => _isLoading = false);
      return;
    }else if ( password.isEmpty) {
      _showErrorDialog('Kata sandi tidak boleh kosong!');
      setState(() => _isLoading = false);
      return;
    }

    try {
      QuerySnapshot userQuery = await _firestore
          .collection('users')
          .where('username', isEqualTo: username)
          .get();

      if (userQuery.docs.isEmpty) {
        userQuery = await _firestore
            .collection('users')
            .where('nomor', isEqualTo: username)
            .get();
      }

      if (userQuery.docs.isEmpty) {
        _showErrorDialog('User tidak ditemukan!');
        setState(() => _isLoading = false);
        return;
      }

      String email = userQuery.docs.first.get('email');
      String userId = userQuery.docs.first.id;

      try {
        await _auth.signInWithEmailAndPassword(email: email, password: password);
        context.read<DataLogin>().setuserlogin(userId);

        DocumentSnapshot userDoc =
        await _firestore.collection('users').doc(userId).get();

        if (userDoc.exists) {
          Map<String, dynamic> userData =
          userDoc.data() as Map<String, dynamic>;

          if (userData['role'] == 'Guru' || userData['role'] == 'Staff') {
            Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) => HomeGuru(userData: userData)));
          } else if (userData['role'] == 'Kepala Sekolah') {
            Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) => HomeKepsek(userData: userData)));
          } else if (userData['role'] == 'Admin') {
            Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) => HomeAdmin(userData: userData)));
          } else {
            _showErrorDialog('Role tidak valid!');
          }
        } else {
          _showErrorDialog('Akun tidak ditemukan!');
        }
      } on FirebaseAuthException catch (e) {
        if (e.code == 'wrong-password') {
          _showErrorDialog('Password salah!');
        } else {
          _showErrorDialog(e.message ?? 'Login gagal! Silakan coba lagi.');
        }
      }
    } catch (e) {
      _showErrorDialog('Terjadi kesalahan: ${e.toString()}');
    }

    setState(() => _isLoading = false);
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  /// **Menentukan animasi Lottie berdasarkan platform**
  String _getLottieIcon() {
    if (kIsWeb) {
      return 'lib/assets/animations/KYC.json';
    } else if (Platform.isAndroid) {
      return 'lib/assets/animations/face-scan.json';
    } else if (Platform.isWindows) {
      return 'lib/assets/animations/facial-recog.json';
    } else {
      return 'lib/assets/animations/KYC.json';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          /// **Latar Belakang Kabut (Fog Background)**
          Positioned.fill(
            child: Lottie.asset(
              'lib/assets/animations/fog.json',
              fit: BoxFit.cover,
            ),
          ),

          /// **Dekorasi Kiri Atas**
          Positioned(
            top: 50,
            left: 20,
            child: Lottie.asset(
              'lib/assets/animations/Tech.json',
              width: 150,
              height: 150,
            ),
          ),

          /// **Dekorasi Kanan Bawah**
          Positioned(
            bottom: 20,
            right: 20,
            child: Lottie.asset(
              'lib/assets/animations/back-to-school.json',
              width: 150,
              height: 150,
            ),
          ),

          /// **Form Login**
          Center(
            child: Container(
              padding: EdgeInsets.all(25),
              margin: EdgeInsets.symmetric(horizontal: 30),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.4),
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 100,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  /// **Animasi Lottie Icon Login**
                  Lottie.asset(_getLottieIcon(), width: 150, height: 150),

                  /// **Judul Login**
                  Text(
                    'Login',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF7B1FA2),
                    ),
                  ),
                  SizedBox(height: 20),

                  /// **Input Username**
                  TextField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      labelText: 'Username / No. Telepon',
                      prefixIcon: Icon(Icons.person, color: Color(0xFF7B1FA2)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  SizedBox(height: 15),

                  /// **Input Password**
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock, color: Color(0xFF7B1FA2)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  SizedBox(height: 20),

                  /// **Tombol Login**
                  ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      backgroundColor: Color(0xFF7B1FA2),
                      elevation: 5,
                    ),
                    child: _isLoading
                        ? Lottie.asset('lib/assets/animations/waiting-register.json',
                        width: 50, height: 50)
                        : Text('Login',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
