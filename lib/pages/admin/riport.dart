import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class ReportKehadiranPage extends StatefulWidget {
  @override
  _ReportKehadiranPageState createState() => _ReportKehadiranPageState();
}

class _ReportKehadiranPageState extends State<ReportKehadiranPage> {
  String _filter = 'Hari Ini';
  // Map<String, int> _chartData = {};
  // Future<List<DocumentSnapshot>>? _futureData;

  @override
  void initState() {
    super.initState();
    // _futureData = _fetchData();
  }

  DateTime getStartDate() {
    DateTime now = DateTime.now();
    if (_filter == 'Hari Ini') {
      return DateTime(now.year, now.month, now.day);
    } else if (_filter == 'Minggu Ini') {
      return now.subtract(Duration(days: now.weekday - 1));
    } else if (_filter == 'Bulan Ini') {
      return DateTime(now.year, now.month, 1);
    } else {
      return DateTime(now.year, 1, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Laporan Kehadiran')),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            DropdownButton<String>(
              value: _filter,
              items: ['Hari Ini', 'Minggu Ini', 'Bulan Ini', 'Tahun Ini']
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _filter = value!;
                  // _futureData = _fetchData();
                });
              },
            ),

            SizedBox(height: 20),

            Expanded(
              flex: 2,
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('absen')
                    .where('tanggal', isGreaterThanOrEqualTo: DateFormat('yyyy-MM-dd').format(getStartDate()))
                    .snapshots(),
                builder: (context, absenSnapshot) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('izin')
                        .where('status', isEqualTo: 'Diterima')
                        .where('tanggal', isGreaterThanOrEqualTo: DateFormat('yyyy-MM-dd').format(getStartDate()))
                        .snapshots(),
                    builder: (context, izinSnapshot) {
                      if (absenSnapshot.connectionState == ConnectionState.waiting ||
                          izinSnapshot.connectionState == ConnectionState.waiting) {
                        return Center(child: CircularProgressIndicator());
                      }
                      if ((!absenSnapshot.hasData || absenSnapshot.data!.docs.isEmpty) &&
                          (!izinSnapshot.hasData || izinSnapshot.data!.docs.isEmpty)) {
                        return Center(child: Text("Tidak ada data kehadiran"));
                      }

                      // Data absen
                      var absenData = absenSnapshot.data?.docs ?? [];
                      // Data izin
                      var izinData = izinSnapshot.data?.docs ?? [];

                      // Gabungkan data absen dan izin
                      List<Map<String, dynamic>> allData = [];

                      // Tambahkan data absen
                      for (var doc in absenData) {
                        allData.add({
                          'type': 'absen',
                          'doc': doc,
                        });
                      }

                      // Tambahkan data izin, pastikan user yang sama tidak double (misal sudah ada absen, tidak tampil izin)
                      Set<String> absenUserTanggal = absenData
                          .map((e) => "${e['user_name']}_${e['tanggal']}")
                          .toSet();

                      for (var izin in izinData) {
                        String key = "${izin['nama']}_${izin['tanggal']}";
                        if (!absenUserTanggal.contains(key)) {
                          allData.add({
                            'type': 'izin',
                            'doc': izin,
                          });
                        }
                      }

                      // Urutkan berdasarkan tanggal (descending)
                      allData.sort((a, b) {
                        String tglA = a['type'] == 'absen'
                            ? a['doc']['tanggal'] ?? ''
                            : a['doc']['tanggal'] ?? '';
                        String tglB = b['type'] == 'absen'
                            ? b['doc']['tanggal'] ?? ''
                            : b['doc']['tanggal'] ?? '';
                        return tglB.compareTo(tglA);
                      });

                      return ListView.builder(
                        itemCount: allData.length,
                        itemBuilder: (context, index) {
                          var item = allData[index];
                          if (item['type'] == 'absen') {
                            var doc = item['doc'];
                            String userName = doc['user_name'] ?? '-';
                            String tanggal = doc['tanggal'] ?? '-';
                            String waktuMasuk = doc['waktu_masuk']?.toString() ?? '--:--';
                            String waktuPulang = doc['waktu_pulang']?.toString() ?? '--:--';

                            String keterangan = (doc['waktu_masuk'] != null && doc['waktu_masuk'].toString().isNotEmpty)
                                ? "Sudah Masuk"
                                : "Belum Masuk";
                            Color statusColor = keterangan == "Sudah Masuk" ? Colors.green : Colors.red;

                            // --- Waktu Terlambat ---
                            String waktuTerlambat = "--:--";
                            if (doc['waktu_masuk'] != null && doc['waktu_masuk'].toString().isNotEmpty) {
                              try {
                                final masukParts = doc['waktu_masuk'].toString().split(":");
                                final masukJam = int.parse(masukParts[0]);
                                final masukMenit = int.parse(masukParts[1]);
                                final masuk = DateTime(2000, 1, 1, masukJam, masukMenit);
                                final batas = DateTime(2000, 1, 1, 7, 0);

                                if (masuk.isAfter(batas)) {
                                  final diff = masuk.difference(batas);
                                  waktuTerlambat = diff.inMinutes < 60
                                      ? "0${diff.inMinutes ~/ 60}:${(diff.inMinutes % 60).toString().padLeft(2, '0')}"
                                      : "${diff.inHours}:${(diff.inMinutes % 60).toString().padLeft(2, '0')}";
                                } else {
                                  waktuTerlambat = "Tepat Waktu";
                                }
                              } catch (e) {
                                waktuTerlambat = "--:--";
                              }
                            }

                            // --- Waktu Pulang Terlalu Cepat ---
                            String waktuPulangCepat = "--:--";
                            if (doc['waktu_pulang'] != null && doc['waktu_pulang'].toString().isNotEmpty) {
                              try {
                                final pulangParts = doc['waktu_pulang'].toString().split(":");
                                final pulangJam = int.parse(pulangParts[0]);
                                final pulangMenit = int.parse(pulangParts[1]);
                                final pulang = DateTime(2000, 1, 1, pulangJam, pulangMenit);
                                final batasPulang = DateTime(2000, 1, 1, 16, 0);

                                if (pulang.isBefore(batasPulang)) {
                                  final diff = batasPulang.difference(pulang);
                                  waktuPulangCepat = diff.inMinutes < 60
                                      ? "0${diff.inMinutes ~/ 60}:${(diff.inMinutes % 60).toString().padLeft(2, '0')}"
                                      : "${diff.inHours}:${(diff.inMinutes % 60).toString().padLeft(2, '0')}";
                                } else {
                                  waktuPulangCepat = "Tepat Waktu";
                                }
                              } catch (e) {
                                waktuPulangCepat = "--:--";
                              }
                            }

                            return Card(
                              elevation: 3,
                              margin: EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                              child: ListTile(
                                title: Text(userName, style: TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("Tanggal: $tanggal"),
                                    Text("Waktu Masuk: $waktuMasuk"),
                                    Text("Waktu Pulang: $waktuPulang"),
                                    Text("Keterangan: $keterangan"),
                                    Text("Waktu Terlambat: $waktuTerlambat"),
                                    Text("Waktu Pulang Terlalu Cepat: $waktuPulangCepat"),
                                  ],
                                ),
                                trailing: Text(
                                  keterangan,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            );
                          } else {
                            // type == 'izin'
                            var izin = item['doc'];
                            String nama = izin['nama'] ?? '-';
                            String tanggal = izin['tanggal'] ?? '-';
                            String alasan = izin['alasan'] ?? izin['jenis'] ?? '-';
                            String keterangan = "Izin";
                            Color statusColor = Colors.orange;

                            return Card(
                              elevation: 3,
                              margin: EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                              child: ListTile(
                                title: Text(nama, style: TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("Tanggal: $tanggal"),
                                    Text("Keterangan: $keterangan"),
                                    Text("Alasan: $alasan"),
                                  ],
                                ),
                                trailing: Text(
                                  keterangan,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            );
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
