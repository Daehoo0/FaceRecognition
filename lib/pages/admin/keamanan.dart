import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EditProfilePage extends StatefulWidget {
  @override
  _EditProfilePageState createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  User? currentUser = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _loadCurrentUsername();
  }

  // 🔹 Load Username dari Firestore
  void _loadCurrentUsername() async {
    if (currentUser != null) {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser!.uid).get();
      setState(() {
        _usernameController.text = userDoc['name'] ?? '';
      });
    }
  }

  // 🔹 Update Username
  void _updateUsername() async {
    if (_usernameController.text.isNotEmpty) {
      await FirebaseFirestore.instance.collection('users').doc(currentUser!.uid).update({
        'name': _usernameController.text,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Username berhasil diperbarui!")),
      );
    }
  }

  // 🔹 Update Password dengan Re-authentication
  void _updatePassword() async {
    if (_formKey.currentState!.validate()) {
      try {
        // Re-authenticate user
        AuthCredential credential = EmailAuthProvider.credential(
          email: currentUser!.email!,
          password: _oldPasswordController.text,
        );
        await currentUser!.reauthenticateWithCredential(credential);

        // Update password
        await currentUser!.updatePassword(_newPasswordController.text);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Password berhasil diperbarui!")),
        );

        // Kosongkan input setelah berhasil update
        _oldPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gagal memperbarui password: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Edit Profil")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🔹 Input Username
                Text("Username", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                TextFormField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    hintText: "Masukkan username baru",
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 10),

                ElevatedButton(
                  onPressed: _updateUsername,
                  child: Text("Simpan Username"),
                ),

                Divider(),

                // 🔹 Input Password Lama
                Text("Password Lama", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                TextFormField(
                  controller: _oldPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: "Masukkan password lama",
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value!.isEmpty ? "Password lama wajib diisi" : null,
                ),
                SizedBox(height: 10),

                // 🔹 Input Password Baru
                Text("Password Baru", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                TextFormField(
                  controller: _newPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: "Masukkan password baru",
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value!.length < 6 ? "Password minimal 6 karakter" : null,
                ),
                SizedBox(height: 10),

                // 🔹 Konfirmasi Password Baru
                Text("Konfirmasi Password Baru", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: "Masukkan kembali password baru",
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                  value != _newPasswordController.text ? "Password tidak cocok" : null,
                ),
                SizedBox(height: 20),

                ElevatedButton(
                  onPressed: _updatePassword,
                  child: Text("Simpan Password"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
