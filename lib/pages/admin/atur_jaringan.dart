import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AturJaringanPage extends StatefulWidget {
  @override
  _AturJaringanPageState createState() => _AturJaringanPageState();
}

class _AturJaringanPageState extends State<AturJaringanPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  void _tampilkanForm({DocumentSnapshot? jaringan}) {
    TextEditingController namaController =
    TextEditingController(text: jaringan?.get('nama') ?? '');
    TextEditingController ipController =
    TextEditingController(text: jaringan?.get('ip') ?? '');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(jaringan == null ? 'Tambah Jaringan' : 'Edit Jaringan'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: namaController,
                decoration: InputDecoration(labelText: 'Nama Jaringan'),
              ),
              TextField(
                controller: ipController,
                decoration: InputDecoration(labelText: 'MAC Address'),
              ),
            ],
          ),
          actions: [
            if (jaringan != null)
              TextButton(
                onPressed: () async {
                  await _firestore.collection('jaringan').doc(jaringan.id).delete();
                  Navigator.pop(context);
                },
                child: Text('Hapus', style: TextStyle(color: Colors.red)),
              ),
            TextButton(
              onPressed: () async {
                if (namaController.text.isNotEmpty && ipController.text.isNotEmpty) {
                  if (jaringan == null) {
                    await _firestore.collection('jaringan').add({
                      'nama': namaController.text.trim(),
                      'ip': ipController.text.trim(),
                      'on': false, // default: mati
                    });
                  } else {
                    await _firestore.collection('jaringan').doc(jaringan.id).update({
                      'nama': namaController.text.trim(),
                      'ip': ipController.text.trim(),
                    });
                  }
                  Navigator.pop(context);
                }
              },
              child: Text(jaringan == null ? 'Tambah' : 'Update'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _toggleJaringan(String id, bool status) async {
    await _firestore.collection('jaringan').doc(id).update({'on': status});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Atur Jaringan')),
      body: StreamBuilder(
        stream: _firestore.collection('jaringan').snapshots(),
        builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Belum ada jaringan yang ditambahkan'),
                  SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () => _tampilkanForm(),
                    child: Text('Tambah Jaringan'),
                  ),
                ],
              ),
            );
          }

          return ListView(
            children: snapshot.data!.docs.map((doc) {
              bool isOn = doc['on'] ?? false;

              return ListTile(
                title: Text(doc['nama']),
                subtitle: Text(doc['ip']),
                trailing: Switch(
                  value: isOn,
                  onChanged: (val) {
                    _toggleJaringan(doc.id, val);
                  },
                  activeColor: Colors.green,
                ),
                onTap: () => _tampilkanForm(jaringan: doc),
              );
            }).toList(),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _tampilkanForm(),
        child: Icon(Icons.add),
      ),
    );
  }
}
