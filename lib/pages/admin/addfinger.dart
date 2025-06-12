import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// Halaman Tambah Data Fingerprint
class AddFingerprintPage extends StatefulWidget {
  @override
  _AddFingerprintPageState createState() => _AddFingerprintPageState();
}

class _AddFingerprintPageState extends State<AddFingerprintPage> {
  List<dynamic> _users = [];

  Future<void> _getUsers() async {
    final response = await http.get(Uri.parse('http://127.0.0.1:5000/get_users'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        _users = data['users'];
      });
    }
  }

  Future<void> _addFingerprint(String userId) async {
    final response = await http.post(
      Uri.parse('http://127.0.0.1:5000/add_fingerprint'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'user_id': userId}),
    );

    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fingerprint added for $userId')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error adding fingerprint')));
    }
  }

  @override
  void initState() {
    super.initState();
    _getUsers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Add Fingerprint')),
      body: ListView.builder(
        itemCount: _users.length,
        itemBuilder: (context, index) {
          final user = _users[index];
          return ListTile(
            title: Text(user['name']),
            subtitle: Text(user['role']),
            onTap: () => _addFingerprint(user['user_id']),
          );
        },
      ),
    );
  }
}
