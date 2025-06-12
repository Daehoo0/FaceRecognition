import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AddUserPage extends StatefulWidget {
  @override
  _AddUserPageState createState() => _AddUserPageState();
}

class _AddUserPageState extends State<AddUserPage> {
  String selectedRole = 'Guru';
  String selectedStatus = 'Tetap';
  bool principalExists = false;
  bool isLoading = true;

  final TextEditingController idController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController professionController = TextEditingController();

  TimeOfDay? jamMasuk;
  TimeOfDay? jamPulang;
  Uint8List? photoBytes;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    checkIfPrincipalExists();
  }

  Future<void> checkIfPrincipalExists() async {
    try {
      final QuerySnapshot result = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'Kepala Sekolah')
          .limit(1)
          .get();

      setState(() {
        principalExists = result.docs.isNotEmpty;
        isLoading = false;
      });
    } catch (e) {
      print('Error checking principal existence: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  void pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      Uint8List bytes = await pickedFile.readAsBytes();
      setState(() {
        photoBytes = bytes;
      });
    }
  }

  Future<void> selectTime(bool isMasuk) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        if (isMasuk) {
          jamMasuk = picked;
        } else {
          jamPulang = picked;
        }
      });
    }
  }

  Future<void> addUser() async {
    String id = idController.text.trim();
    String name = nameController.text.trim();
    String email = emailController.text.trim();
    String password = passwordController.text.trim();
    String profession = professionController.text.trim();

    if (id.isEmpty || name.isEmpty || email.isEmpty || password.isEmpty) {
      _showMessage('Semua field harus diisi!');
      return;
    }

    if (selectedRole == 'Guru') {
      if (profession.isEmpty) {
        _showMessage('Profesi harus diisi untuk Guru!');
        return;
      }
      if (selectedStatus == 'Honorer' && (jamMasuk == null || jamPulang == null)) {
        _showMessage('Jam masuk dan pulang harus dipilih untuk Honorer!');
        return;
      }
    }

    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      String? photoBase64 = photoBytes != null ? base64Encode(photoBytes!) : null;

      Map<String, dynamic> userData = {
        'nomor': id,
        'name': name,
        'email': email,
        'role': selectedRole,
        'profile': photoBase64,
        'embedding': '',
        'finger': '',
        'device': '',
        'fcm_token': '',
      };

      // Add role-specific fields
      if (selectedRole == 'Guru') {
        userData['profession'] = profession;
        userData['status'] = selectedStatus;

        if (selectedStatus == 'Honorer') {
          userData['jam_masuk'] = jamMasuk!.format(context);
          userData['jam_pulang'] = jamPulang!.format(context);
        }
      } else if (selectedRole == 'Kepala Sekolah') {
        // Kepala Sekolah doesn't need profession and status fields
        userData['profession'] = '';
        userData['status'] = '';
      } else if (selectedRole == 'Staff') {
        userData['profession'] = '';
        userData['status'] = '';
      }

      await _firestore.collection('users').doc(userCredential.user?.uid).set(userData);

      // If we just added a principal, update the state
      if (selectedRole == 'Kepala Sekolah') {
        setState(() {
          principalExists = true;
        });
      }

      _showMessage('$selectedRole berhasil ditambahkan!');

      // Clear form after successful addition
      clearForm();
    } catch (e) {
      _showMessage('Error: $e');
    }
  }

  void clearForm() {
    idController.clear();
    nameController.clear();
    emailController.clear();
    passwordController.clear();
    professionController.clear();
    setState(() {
      photoBytes = null;
      jamMasuk = null;
      jamPulang = null;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Tambah Pengguna'),
        backgroundColor: Colors.deepPurple,
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: EdgeInsets.all(16.0),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 600),
              child: Center(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      children: [
                        ChoiceChip(
                          label: Text('Guru'),
                          selected: selectedRole == 'Guru',
                          onSelected: (val) => setState(() => selectedRole = 'Guru'),
                        ),
                        ChoiceChip(
                          label: Text('Staff'),
                          selected: selectedRole == 'Staff',
                          onSelected: (val) => setState(() => selectedRole = 'Staff'),
                        ),
                        ChoiceChip(
                          label: Text('Kepala Sekolah'),
                          selected: selectedRole == 'Kepala Sekolah',
                          onSelected: principalExists
                              ? null // Disable if principal exists
                              : (val) => setState(() => selectedRole = 'Kepala Sekolah'),
                          backgroundColor: principalExists ? Colors.grey.shade300 : null,
                          disabledColor: Colors.grey.shade300,
                        ),
                      ],
                    ),
                    if (principalExists && selectedRole == 'Kepala Sekolah') ...[
                      SizedBox(height: 10),
                      Text(
                        'Kepala Sekolah sudah ada dalam sistem',
                        style: TextStyle(color: Colors.red, fontStyle: FontStyle.italic),
                      ),
                    ],
                    SizedBox(height: 16),
                    _buildTextField(
                        idController,
                        selectedRole == 'Guru'
                            ? 'Nomor Guru'
                            : selectedRole == 'Staff'
                            ? 'Nomor Staff'
                            : 'Nomor Kepala Sekolah'
                    ),
                    _buildTextField(nameController, 'Nama'),
                    _buildTextField(emailController, 'Email'),
                    _buildTextField(passwordController, 'Password', obscure: true),

                    // Show profession and status only for Guru
                    if (selectedRole == 'Guru') ...[
                      _buildTextField(professionController, 'Profesi Guru'),
                      SizedBox(height: 10),
                      Text('Status Guru:', style: TextStyle(fontWeight: FontWeight.w500)),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: selectedStatus == 'Tetap' ? Colors.deepPurple : Colors.grey.shade300,
                              ),
                              onPressed: () => setState(() => selectedStatus = 'Tetap'),
                              child: Text('Tetap', style: TextStyle(color: selectedStatus == 'Tetap' ? Colors.white : Colors.black)),
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: selectedStatus == 'Honorer' ? Colors.deepPurple : Colors.grey.shade300,
                              ),
                              onPressed: () => setState(() => selectedStatus = 'Honorer'),
                              child: Text('Honorer', style: TextStyle(color: selectedStatus == 'Honorer' ? Colors.white : Colors.black)),
                            ),
                          ),
                        ],
                      ),
                      if (selectedStatus == 'Honorer') ...[
                        SizedBox(height: 10),
                        _buildTimePicker(
                          label: 'Jam Masuk',
                          time: jamMasuk,
                          onTap: () => selectTime(true),
                        ),
                        _buildTimePicker(
                          label: 'Jam Pulang',
                          time: jamPulang,
                          onTap: () => selectTime(false),
                        ),
                      ],
                    ],

                    SizedBox(height: 20),
                    Center(
                      child: Column(
                        children: [
                          if (photoBytes != null)
                            ClipOval(
                              child: Image.memory(photoBytes!, height: 100, width: 100, fit: BoxFit.cover),
                            )
                          else
                            CircleAvatar(
                              radius: 50,
                              backgroundColor: Colors.grey.shade300,
                              child: Icon(Icons.person, size: 40, color: Colors.grey.shade700),
                            ),
                          TextButton.icon(
                            onPressed: pickImage,
                            icon: Icon(Icons.image),
                            label: Text('Pilih Foto'),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: (selectedRole == 'Kepala Sekolah' && principalExists)
                            ? null // Disable button if trying to add principal when one exists
                            : addUser,
                        icon: Icon(Icons.save),
                        label: Text('Tambah $selectedRole'),
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          disabledBackgroundColor: Colors.grey.shade400, // For disabled state
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, {bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildTimePicker({required String label, required TimeOfDay? time, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: GestureDetector(
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(time != null ? time.format(context) : 'Pilih waktu'),
        ),
      ),
    );
  }
}