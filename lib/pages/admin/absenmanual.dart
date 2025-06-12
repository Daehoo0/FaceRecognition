import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class Absenmanual extends StatefulWidget {
  @override
  _AbsenmanualState createState() => _AbsenmanualState();
}

class _AbsenmanualState extends State<Absenmanual> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
  String searchQuery = '';

  Future<void> _updateAttendance(String userId, String type) async {
    try {
      DocumentReference attendanceRef =
      _firestore.collection('absen').doc('${userId}_$today');

      DocumentSnapshot doc = await attendanceRef.get();

      // Get current time in HH:MM format
      final nowTime = DateTime.now();
      final formattedTime = "${nowTime.hour.toString().padLeft(2, '0')}:${nowTime.minute.toString().padLeft(2, '0')}";

      if (!doc.exists) {
        DocumentSnapshot userDoc =
        await _firestore.collection('users').doc(userId).get();

        if (!userDoc.exists) throw Exception('User tidak ditemukan');

        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;

        await attendanceRef.set({
          'user_id': userId,
          'user_name': userData['name'] ?? 'Unknown',
          'tanggal': today,
          'waktu_masuk_raw': type == 'masuk' ? FieldValue.serverTimestamp() : null,
          'waktu_pulang_raw': type == 'pulang' ? FieldValue.serverTimestamp() : null,
          'waktu_masuk': type == 'masuk' ? formattedTime : null,
          'waktu_pulang': type == 'pulang' ? formattedTime : null,
          'keterangan': type == 'masuk' ? 'Sudah Masuk' : 'Sudah Pulang',
          'hari': DateFormat('EEEE', 'id_ID').format(DateTime.now()),
          'bulan': DateFormat('MMMM', 'id_ID').format(DateTime.now()),
        });
      } else {
        await attendanceRef.update({
          type == 'masuk' ? 'waktu_masuk_raw' : 'waktu_pulang_raw': FieldValue.serverTimestamp(),
          type == 'masuk' ? 'waktu_masuk' : 'waktu_pulang': formattedTime,
          'keterangan': type == 'masuk' ? 'Sudah Masuk' : 'Sudah Pulang',
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  String formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '--:--';

    // If it's already in HH:MM format, just return it
    if (timestamp is String && RegExp(r'^\d{2}:\d{2}$').hasMatch(timestamp)) {
      return timestamp;
    }

    // Handle different timestamp formats
    if (timestamp is Timestamp) {
      final time = timestamp.toDate();
      return DateFormat('HH:mm').format(time);
    } else if (timestamp is String) {
      // Try to parse the string timestamp
      try {
        // If it's a simple time string already, just return it
        if (timestamp == '--:--') {
          return timestamp;
        }

        // Attempt to parse as DateTime
        DateTime dateTime = DateTime.parse(timestamp);
        return DateFormat('HH:mm').format(dateTime);
      } catch (e) {
        return '--:--';
      }
    } else {
      return '--:--';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Absen Manual'),
        centerTitle: true,
        backgroundColor: Colors.deepPurple,
      ),
      backgroundColor: Colors.grey[100],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Cari nama guru/staf...',
                prefixIcon: Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
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
                  .where('role', whereIn: ['Guru', 'Staff', 'Kepala Sekolah'])
                  .snapshots(),
              builder: (context, userSnapshot) {
                if (userSnapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                if (!userSnapshot.hasData || userSnapshot.data!.docs.isEmpty) {
                  return Center(child: Text('Tidak ada data pengguna'));
                }

                final filteredUsers = userSnapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name = data['name']?.toLowerCase() ?? '';
                  return name.contains(searchQuery);
                }).toList();

                return ListView.builder(
                  padding: EdgeInsets.all(12),
                  itemCount: filteredUsers.length,
                  itemBuilder: (context, index) {
                    final userDoc = filteredUsers[index];
                    String userId = userDoc.id;
                    Map<String, dynamic> userData =
                    userDoc.data() as Map<String, dynamic>;
                    String userName = userData['name'] ?? 'Unknown';
                    String userRole = userData['role'] ?? 'Unknown';
                    String userNumber = userData['nomor'] ?? 'Unknown';

                    return StreamBuilder<DocumentSnapshot>(
                      stream: _firestore
                          .collection('absen')
                          .doc('${userId}_$today')
                          .snapshots(),
                      builder: (context, attendanceSnapshot) {
                        String checkInTime = '--:--';
                        String checkOutTime = '--:--';
                        bool canCheckIn = true;
                        bool canCheckOut = true;

                        if (attendanceSnapshot.hasData &&
                            attendanceSnapshot.data!.exists) {
                          var attendanceData =
                          attendanceSnapshot.data!.data() as Map<String, dynamic>;

                          // Use the formatted string time directly
                          checkInTime = attendanceData['waktu_masuk'] ?? '--:--';
                          checkOutTime = attendanceData['waktu_pulang'] ?? '--:--';

                          canCheckIn = attendanceData['waktu_masuk'] == null;
                          canCheckOut = attendanceData['waktu_pulang'] == null;
                        }

                        return Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 4,
                          margin: EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    userName,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text('$userRole - $userNumber'),
                                  trailing: Icon(Icons.person, color: Colors.grey),
                                ),
                                Divider(height: 24),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    _buildAbsenColumn(
                                      label: 'Masuk',
                                      time: checkInTime,
                                      color: Colors.green,
                                      onPressed: canCheckIn
                                          ? () => _updateAttendance(userId, 'masuk')
                                          : null,
                                    ),
                                    _buildAbsenColumn(
                                      label: 'Pulang',
                                      time: checkOutTime,
                                      color: Colors.blue,
                                      onPressed: canCheckOut
                                          ? () => _updateAttendance(userId, 'pulang')
                                          : null,
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
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAbsenColumn({
    required String label,
    required String time,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return Column(
      children: [
        Text(
          'Absen $label',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 4),
        Text(
          time,
          style: TextStyle(fontSize: 16),
        ),
        SizedBox(height: 8),
        ElevatedButton(
          onPressed: onPressed,
          child: Text('Absen $label'),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }
}