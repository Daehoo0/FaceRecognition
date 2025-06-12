import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:typed_data';
import 'dart:convert';

class KonfirmasiIzinPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Get available screen size
    final Size screenSize = MediaQuery.of(context).size;
    final double screenWidth = screenSize.width;

    // Determine grid columns based on available width
    int crossAxisCount = (screenWidth ~/ 180).clamp(1, 4);

    return Scaffold(
      appBar: AppBar(title: Text('Konfirmasi Izin')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: StreamBuilder(
            stream: FirebaseFirestore.instance
                .collection('izin')
                .where('status', isEqualTo: 'Pending')
                .snapshots(),
            builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(child: Text('Tidak ada izin pending.'));
              }

              var izinList = snapshot.data!.docs;
              return GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.75, // Adjusted for better layout
                ),
                itemCount: izinList.length,
                itemBuilder: (context, index) {
                  var izin = izinList[index];
                  final Map<String, dynamic> data = izin.data() as Map<String, dynamic>;

                  // Safely extract data using null-aware operators
                  final String profile = data['foto_user'] ?? '';
                  final String nama = data['nama'] ?? 'Nama tidak tersedia';
                  final String alasan = data['alasan'] ?? 'Alasan tidak tersedia';
                  final String jenisIzin = data['jenis_izin'] ?? 'Jenis izin tidak tersedia';
                  final String foto_izin = data['foto_izin'] ?? '';

                  // Decode base64 images
                  Uint8List? profileImageBytes;
                  if (profile.isNotEmpty && !profile.startsWith('http')) {
                    try {
                      profileImageBytes = base64Decode(profile);
                    } catch (e) {
                      profileImageBytes = null;
                    }
                  }

                  return Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 35,
                              backgroundImage: profileImageBytes != null
                                  ? MemoryImage(profileImageBytes)
                                  : (profile.startsWith('http') ? NetworkImage(profile) as ImageProvider : null),
                              child: (profileImageBytes == null && profile.isEmpty)
                                  ? Icon(Icons.person, size: 35)
                                  : null,
                            ),
                            SizedBox(height: 8),
                            Flexible(
                              child: Text(
                                nama,
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            Flexible(
                              child: Text(
                                jenisIzin,
                                style: TextStyle(color: Colors.grey, fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            SizedBox(height: 8),
                            Flexible(
                              child: Text(
                                'Alasan: $alasan',
                                style: TextStyle(color: Colors.grey[600], fontSize: 14),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                            ),
                            Flexible(
                              child: Text(
                                'Status: ${izin['status']}',
                                style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SizedBox(height: 8),
                            ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: 150),
                              child: ElevatedButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => DetailIzinPage(izin: izin),
                                    ),
                                  );
                                },
                                child: Text('Lihat Detail'),
                                style: ElevatedButton.styleFrom(
                                  minimumSize: Size(double.infinity, 36),
                                ),
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  onPressed: () {
                                    FirebaseFirestore.instance
                                        .collection('izin')
                                        .doc(izin.id)
                                        .update({'status': 'Diterima'});
                                  },
                                  icon: Icon(Icons.check_circle, color: Colors.green),
                                  constraints: BoxConstraints(),
                                  padding: EdgeInsets.all(8),
                                ),
                                IconButton(
                                  onPressed: () {
                                    FirebaseFirestore.instance
                                        .collection('izin')
                                        .doc(izin.id)
                                        .update({'status': 'Ditolak'});
                                  },
                                  icon: Icon(Icons.cancel, color: Colors.red),
                                  constraints: BoxConstraints(),
                                  padding: EdgeInsets.all(8),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class DetailIzinPage extends StatelessWidget {
  final QueryDocumentSnapshot izin;
  DetailIzinPage({required this.izin});

  @override
  Widget build(BuildContext context) {
    // Get available screen size for responsive layout
    final Size screenSize = MediaQuery.of(context).size;
    final bool isSmallScreen = screenSize.width < 400;

    return Scaffold(
      appBar: AppBar(title: Text('Detail Izin')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: ClipOval(
                        child: SizedBox(
                          width: 100,
                          height: 100,
                          child: izin['foto_user'] != null && izin['foto_user'].toString().isNotEmpty
                              ? displayImage(izin['foto_user'])
                              : Icon(Icons.account_circle, size: 100, color: Colors.grey),
                        ),
                      ),
                    ),
                    SizedBox(height: 16),
                    buildInfoSection(context, 'Nama', izin['nama'] ?? 'Tidak tersedia'),
                    buildInfoSection(context, 'Jenis Izin', izin['jenis_izin'] ?? 'Tidak tersedia'),
                    buildInfoSection(context, 'Alasan', izin['alasan'] ?? 'Tidak tersedia'),
                    SizedBox(height: 16),
                    Center(
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: isSmallScreen ? screenSize.width - 32 : 400,
                          maxHeight: 300,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey),
                        ),
                        child: izin['foto_izin'] != null && izin['foto_izin'].toString().isNotEmpty
                            ? ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: displayImage(izin['foto_izin'], fit: BoxFit.contain),
                        )
                            : Icon(Icons.image_not_supported, size: 100, color: Colors.grey),
                      ),
                    ),
                    SizedBox(height: 16),
                    buildInfoSection(context, 'Tanggal', izin['tanggal'] ?? 'Tidak tersedia'),
                    buildInfoSection(
                      context,
                      'Status',
                      izin['status'] ?? 'Tidak tersedia',
                      textStyle: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue
                      ),
                    ),
                    SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: ElevatedButton(
                              onPressed: () {
                                FirebaseFirestore.instance
                                    .collection('izin')
                                    .doc(izin.id)
                                    .update({'status': 'Diterima'});
                                Navigator.pop(context);
                              },
                              child: Text('Terima'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                padding: EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: ElevatedButton(
                              onPressed: () {
                                FirebaseFirestore.instance
                                    .collection('izin')
                                    .doc(izin.id)
                                    .update({'status': 'Ditolak'});
                                Navigator.pop(context);
                              },
                              child: Text('Tolak'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                padding: EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildInfoSection(BuildContext context, String label, String value, {TextStyle? textStyle}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text: value,
              style: textStyle ?? TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget displayImage(String imageData, {BoxFit fit = BoxFit.cover}) {
    try {
      if (imageData.startsWith('data:image')) {
        String base64String = imageData.split(',')[1];
        Uint8List bytes = base64Decode(base64String);
        return Image.memory(bytes, fit: fit);
      } else if (imageData.startsWith('http')) {
        return Image.network(
          imageData,
          fit: fit,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(child: CircularProgressIndicator());
          },
          errorBuilder: (context, error, stackTrace) {
            return Icon(Icons.broken_image, size: 100, color: Colors.grey);
          },
        );
      } else {
        try {
          Uint8List bytes = base64Decode(imageData);
          return Image.memory(bytes, fit: fit);
        } catch (e) {
          return Icon(Icons.broken_image, size: 100, color: Colors.grey);
        }
      }
    } catch (e) {
      return Icon(Icons.broken_image, size: 100, color: Colors.grey);
    }
  }
}