import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';


// Halaman Absensi Fingerprint
class FingerprintPage extends StatefulWidget {
  @override
  _FingerprintPageState createState() => _FingerprintPageState();
}

class _FingerprintPageState extends State<FingerprintPage> {
  String _message = "Scan your fingerprint";
  String _user = "";

  Future<void> _startFingerprintScan() async {
    try {
      final response = await http.post(
        Uri.parse('http://127.0.0.1:5000/scan_fingerprint'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _message = data["message"];
          _user = data["user_id"];
        });
      } else {
        setState(() {
          _message = "Fingerprint not recognized.";
        });
      }
    } catch (e) {
      setState(() {
        _message = "Error: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Absensi Fingerprint')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_message),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _startFingerprintScan,
              child: Text("Start Scan"),
            ),
            if (_user.isNotEmpty) Text("User: $_user"),
            ElevatedButton(
              onPressed: () {
                // Navigator.push(
                //   context,
                //   MaterialPageRoute(builder: (context) => AddFingerprintPage()),
                // );
              },
              child: Text("Add Fingerprint"),
            ),
          ],
        ),
      ),
    );
  }
}
