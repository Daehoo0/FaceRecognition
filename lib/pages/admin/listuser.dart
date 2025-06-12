import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ta/pages/admin/adduser.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:ta/pages/admin/edituser.dart';

class ListUserPage extends StatefulWidget {
  const ListUserPage({super.key});

  @override
  State<ListUserPage> createState() => _ListUserPageState();
}

class _ListUserPageState extends State<ListUserPage> {
  final TextEditingController searchController = TextEditingController();
  String searchQuery = '';

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Daftar Pengguna'),
        backgroundColor: Colors.deepPurple,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: 'Cari nama, nomor, atau profesi...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (value) {
                setState(() {
                  searchQuery = value.toLowerCase().trim();
                });
              },
            ),
          ),
          Expanded(
            child: StreamBuilder(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('role', whereIn: ['Guru', 'Staff', 'Kepala Sekolah'])
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting)
                  return Center(child: CircularProgressIndicator());

                final userDocs = snapshot.data?.docs ?? [];
                final users = userDocs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return {
                    'imagePath': data['profile'],
                    'name': data['name'] ?? '',
                    'nomor': data['nomor'] ?? '',
                    'profession': data['role'] ?? '',
                    'id': doc.id,
                  };
                }).where((user) {
                  final name = user['name'].toLowerCase();
                  final nomor = user['nomor'].toLowerCase();
                  final role = user['profession'].toLowerCase();
                  return name.contains(searchQuery) ||
                      nomor.contains(searchQuery) ||
                      role.contains(searchQuery);
                }).toList();

                if (kIsWeb) return _buildWebView(users);
                if (defaultTargetPlatform == TargetPlatform.windows ||
                    defaultTargetPlatform == TargetPlatform.macOS) {
                  return _buildDesktopView(users);
                }
                return _buildMobileView(users);
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => AddUserPage()),
          );
        },
        icon: Icon(Icons.person_add),
        label: Text('Tambah'),
      ),
    );
  }

  Widget displayImage(String? imageData, {double size = 50}) {
    if (imageData == null || imageData.isEmpty) {
      return Icon(Icons.account_circle, size: size, color: Colors.grey.shade400);
    }

    try {
      final bytes = base64Decode(imageData);
      return ClipOval(
        child: Image.memory(bytes, width: size, height: size, fit: BoxFit.cover),
      );
    } catch (_) {
      return Icon(Icons.account_circle, size: size, color: Colors.grey.shade400);
    }
  }

  Widget _buildWebView(List<Map<String, dynamic>> users) {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      padding: EdgeInsets.all(16),
      child: DataTable(
        columnSpacing: 24,
        headingRowColor: MaterialStateProperty.all(Colors.deepPurple.shade50),
        columns: const [
          DataColumn(label: Text('Foto')),
          DataColumn(label: Text('Nama')),
          DataColumn(label: Text('Nomor')),
          DataColumn(label: Text('Profesi')),
          DataColumn(label: Text('Aksi')),
        ],
        rows: users.map((user) {
          return DataRow(cells: [
            DataCell(displayImage(user['imagePath'], size: 40)),
            DataCell(Text(user['name'])),
            DataCell(Text(user['nomor'])),
            DataCell(Text(user['profession'])),
            DataCell(Row(
              children: [
                IconButton(
                  icon: Icon(Icons.edit, color: Colors.blue),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EditUserPage(userId: user['id']),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: Icon(Icons.delete, color: Colors.red),
                  onPressed: () async {
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(user['id'])
                        .delete();
                  },
                ),
              ],
            )),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _buildDesktopView(List<Map<String, dynamic>> users) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView.builder(
        itemCount: users.length,
        itemBuilder: (context, index) {
          final user = users[index];
          return Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: EdgeInsets.symmetric(vertical: 8),
            child: ListTile(
              leading: displayImage(user['imagePath'], size: 50),
              title: Text(user['name'], style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${user['nomor']} - ${user['profession']}'),
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    icon: Icon(Icons.edit, color: Colors.blue),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EditUserPage(userId: user['id']),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.delete, color: Colors.red),
                    onPressed: () async {
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(user['id'])
                          .delete();
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMobileView(List<Map<String, dynamic>> users) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: GridView.builder(
        itemCount: users.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.72,
        ),
        itemBuilder: (context, index) {
          final user = users[index];
          return Card(
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  displayImage(user['imagePath'], size: 70),
                  SizedBox(height: 10),
                  Text(
                    user['name'],
                    style: TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    softWrap: true,
                  ),
                  Text(
                    user['nomor'],
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    user['profession'],
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: Icon(Icons.edit, color: Colors.blue),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => EditUserPage(userId: user['id']),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(user['id'])
                              .delete();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
