import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ta/pages/admin/regisface.dart';

class DaftarUserRegisFacePage extends StatefulWidget {
  @override
  _DaftarUserRegisFacePageState createState() => _DaftarUserRegisFacePageState();
}

class _DaftarUserRegisFacePageState extends State<DaftarUserRegisFacePage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Registrasi Wajah'),
        backgroundColor: Colors.deepPurple,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Cari nama atau nomor...',
                prefixIcon: Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (value) {
                setState(() {
                  searchQuery = value.toLowerCase();
                });
              },
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('users')
                  .where('role', whereIn: ['Guru', 'Staff'])
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting)
                  return Center(child: CircularProgressIndicator());

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
                  return Center(child: Text('Tidak ada pengguna ditemukan.'));

                final users = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data['name'] ?? '').toString().toLowerCase();
                  final nomor = (data['nomor'] ?? '').toString().toLowerCase();
                  return name.contains(searchQuery) || nomor.contains(searchQuery);
                }).toList();

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 800;
                    final crossAxisCount = isWide ? 2 : 1;

                    return GridView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: users.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: isWide ? 3.5 : 2.8,
                      ),
                      itemBuilder: (context, index) {
                        final doc = users[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final name = data['name'] ?? '-';
                        final role = data['role'] ?? '-';
                        final nomor = data['nomor'] ?? '-';
                        final embedding = data['embedding'] ?? '';
                        final canRegister = embedding == '';

                        return Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                CircleAvatar(
                                  radius: 30,
                                  backgroundColor: Colors.grey.shade200,
                                  backgroundImage: data['profile'] != null
                                      ? MemoryImage(base64Decode(data['profile']))
                                      : null,
                                  child: data['profile'] == null
                                      ? Icon(Icons.person, color: Colors.grey)
                                      : null,
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        name,
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        '$role - $nomor',
                                        style: TextStyle(color: Colors.grey[600]),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        embedding == ''
                                            ? 'Belum terdaftar'
                                            : 'Wajah sudah terdaftar',
                                        style: TextStyle(
                                          fontStyle: FontStyle.italic,
                                          color: embedding == ''
                                              ? Colors.red
                                              : Colors.green,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: 8),
                                ElevatedButton.icon(
                                  onPressed: canRegister
                                      ? () {
                                    // Navigator.push(
                                    //   context,
                                    //   MaterialPageRoute(
                                    //     builder: (context) => FaceAbsensiPage(userId: doc.id),
                                    //   ),
                                    // );
                                  }
                                      : null,
                                  icon: Icon(Icons.face),
                                  label: Text('Registrasi'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.deepPurple,
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor: Colors.grey.shade300,
                                    disabledForegroundColor: Colors.grey,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
