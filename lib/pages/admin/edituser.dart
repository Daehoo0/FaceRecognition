import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class EditUserPage extends StatefulWidget {
  final String userId;

  const EditUserPage({super.key, required this.userId});

  @override
  State<EditUserPage> createState() => _EditUserPageState();
}

class _EditUserPageState extends State<EditUserPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController nomorController = TextEditingController();
  String selectedRole = 'Guru';
  String? imageData;

  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
    if (doc.exists) {
      final data = doc.data()!;
      nameController.text = data['name'] ?? '';
      nomorController.text = data['nomor'] ?? '';
      selectedRole = data['role'] ?? 'Guru';
      imageData = data['profile'];
    }
    setState(() {
      isLoading = false;
    });
  }

  Widget _displayImage(String? base64Image) {
    if (base64Image == null || base64Image.isEmpty) {
      return const Icon(Icons.account_circle, size: 100, color: Colors.grey);
    }
    try {
      Uint8List bytes = base64Decode(base64Image);
      return ClipOval(child: Image.memory(bytes, width: 100, height: 100, fit: BoxFit.cover));
    } catch (_) {
      return const Icon(Icons.account_circle, size: 100, color: Colors.grey);
    }
  }

  Future<void> _resetEmbedding() async {
    await FirebaseFirestore.instance.collection('users').doc(widget.userId).update({
      'embedding': FieldValue.delete(),
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Data wajah direset.")));
  }

  Future<void> _resetDevice() async {
    await FirebaseFirestore.instance.collection('users').doc(widget.userId).update({
      'device': FieldValue.delete(),
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Data device direset.")));
  }

  Future<void> _saveChanges() async {
    if (_formKey.currentState!.validate()) {
      await FirebaseFirestore.instance.collection('users').doc(widget.userId).update({
        'name': nameController.text.trim(),
        'nomor': nomorController.text.trim(),
        'role': selectedRole,
      });
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Pengguna'),
        backgroundColor: Colors.deepPurple,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _displayImage(imageData),
              const SizedBox(height: 20),
              TextFormField(
                controller: nameController,
                decoration: _inputDecoration('Nama Lengkap'),
                validator: (value) => value == null || value.isEmpty ? 'Masukkan nama' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: nomorController,
                keyboardType: TextInputType.number,
                decoration: _inputDecoration('Nomor'),
                validator: (value) => value == null || value.isEmpty ? 'Masukkan nomor' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedRole,
                decoration: _inputDecoration('Profesi'),
                items: ['Guru', 'Staff', 'Kepala Sekolah']
                    .map((role) => DropdownMenuItem(
                  value: role,
                  child: Text(role),
                ))
                    .toList(),
                onChanged: (value) => setState(() => selectedRole = value!),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _resetEmbedding,
                    icon: Icon(Icons.face_retouching_off),
                    label: Text('Reset Wajah'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                  ),
                  ElevatedButton.icon(
                    onPressed: _resetDevice,
                    icon: Icon(Icons.devices_other),
                    label: Text('Reset Device'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _saveChanges,
                icon: Icon(Icons.save),
                label: Text('Simpan Perubahan'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}
