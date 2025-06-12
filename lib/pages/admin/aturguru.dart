import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AturJadwalGuruPage extends StatefulWidget {
  @override
  _AturJadwalGuruPageState createState() => _AturJadwalGuruPageState();
}

class _AturJadwalGuruPageState extends State<AturJadwalGuruPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? selectedGuruId;
  String? selectedGuruName;
  List<String> hariLibur = [];
  final List<String> hariList = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu'];

  void _tampilkanFormFloating(BuildContext context, String guruId, String guruName, List<String> hariLiburSebelumnya) {
    setState(() {
      selectedGuruId = guruId;
      selectedGuruName = guruName;
      hariLibur = List.from(hariLiburSebelumnya);
    });

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              elevation: 5,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Atur Jadwal - $guruName",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                    ),
                    SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: hariList.map((hari) {
                        bool isSelected = hariLibur.contains(hari);
                        return GestureDetector(
                          onTap: () {
                            setStateDialog(() {
                              if (hariLibur.contains(hari)) {
                                hariLibur.remove(hari);
                              } else {
                                hariLibur.add(hari);
                              }
                            });
                          },
                          child: AnimatedContainer(
                            duration: Duration(milliseconds: 200),
                            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 14),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.red : Colors.black,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withOpacity(0.3),
                                  blurRadius: 4,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Text(
                              hari,
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: Text("Tutup", style: TextStyle(fontSize: 16)),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueGrey,
                            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          ),
                          onPressed: () async {
                            if (selectedGuruId != null) {
                              await _firestore.collection('users').doc(selectedGuruId).update({'hari_libur': hariLibur});
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Jadwal berhasil disimpan!')),
                              );
                            }
                          },
                          child: Text("Simpan", style: TextStyle(fontSize: 16)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Atur Jadwal Guru')),
      body: StreamBuilder(
        stream: _firestore
            .collection('users')
            .where('role', isEqualTo: 'Guru')
            .where('status', isEqualTo: 'Honorer')
            .snapshots(),
        builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (!snapshot.hasData) return Center(child: CircularProgressIndicator());

          return ListView(
            padding: EdgeInsets.all(12),
            children: snapshot.data!.docs.map((doc) {
              return Card(
                margin: EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 3,
                child: ListTile(
                  contentPadding: EdgeInsets.all(12),
                  leading: CircleAvatar(
                    backgroundColor: Colors.blueGrey,
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                  title: Text(
                    doc['name'],
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text("Klik untuk atur jadwal"),
                  trailing: Icon(Icons.edit, color: Colors.blueGrey),
                  onTap: () {
                    List<String> hariLiburSebelumnya = [];
                    if (doc.data() != null && (doc.data() as Map<String, dynamic>).containsKey('hari_libur')) {
                      hariLiburSebelumnya = List<String>.from(doc['hari_libur']);
                    }
                    _tampilkanFormFloating(context, doc.id, doc['name'], hariLiburSebelumnya);
                  },
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
