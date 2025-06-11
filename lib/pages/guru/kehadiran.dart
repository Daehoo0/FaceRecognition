import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/date_symbol_data_local.dart';

class KehadiranPage extends StatefulWidget {
  @override
  _KehadiranPageState createState() => _KehadiranPageState();
}

class _KehadiranPageState extends State<KehadiranPage> {
  String statusIzin = 'Pending';
  int jumlahMasuk = 20;
  int jumlahIzin = 3;
  int jumlahTidakMasuk = 2;
  bool showIzinCard = false;

  // Tab selection
  bool showChart = true;

  // Bulan selection
  String selectedMonth = '';
  List<String> availableMonths = [];

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('id_ID', null).then((_) {
      _initializeMonths();
    });
  }

  void _initializeMonths() {
    final now = DateTime.now();
    final currentMonth = DateFormat('MMMM yyyy', 'id_ID').format(now);

    // Set bulan saat ini sebagai default
    setState(() {
      selectedMonth = currentMonth;

      // Tambahkan bulan-bulan tersedia (6 bulan terakhir)
      availableMonths = [];
      for (int i = 0; i < 6; i++) {
        final month = DateTime(now.year, now.month - i, 1);
        availableMonths.add(DateFormat('MMMM yyyy', 'id_ID').format(month));
      }
    });
  }

  // Mendapatkan data bulan dalam format yyyy-MM
  String _getMonthYearFormat(String monthName) {
    final parts = monthName.split(' ');
    if (parts.length != 2) return '';

    final months = {
      'Januari': '01', 'Februari': '02', 'Maret': '03', 'April': '04',
      'Mei': '05', 'Juni': '06', 'Juli': '07', 'Agustus': '08',
      'September': '09', 'Oktober': '10', 'November': '11', 'Desember': '12'
    };

    final monthNumber = months[parts[0]];
    final year = parts[1];

    return '$year-$monthNumber';
  }

  @override
  Widget build(BuildContext context) {
    final String tanggal = DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: Text('Kehadiran'),
        centerTitle: true,
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _buildWaktuDanTanggal(tanggal),
              SizedBox(height: 16),
              _buildAbsenCard(),
              SizedBox(height: 16),
              _buildIzinCard(),
              SizedBox(height: 16),
              _buildTabSelector(),
              SizedBox(height: 8),
              _buildMonthSelector(),
              SizedBox(height: 8),
              Expanded(
                child: showChart ? _buildChart() : _buildAbsenTable(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabSelector() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                showChart = true;
              });
            },
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: showChart ? Colors.deepPurple : Colors.grey.shade300,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
              ),
              child: Text(
                'Chart',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: showChart ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                showChart = false;
              });
            },
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: !showChart ? Colors.deepPurple : Colors.grey.shade300,
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
              ),
              child: Text(
                'Tabel',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: !showChart ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMonthSelector() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey.shade200,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: selectedMonth,
          icon: Icon(Icons.arrow_drop_down),
          style: TextStyle(color: Colors.black87, fontSize: 16),
          onChanged: (String? newValue) {
            if (newValue != null) {
              setState(() {
                selectedMonth = newValue;
              });
            }
          },
          items: availableMonths.map<DropdownMenuItem<String>>((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildWaktuDanTanggal(String tanggal) {
    return Column(
      children: [
        StreamBuilder(
          stream: Stream.periodic(Duration(seconds: 1)),
          builder: (context, snapshot) {
            final waktu = DateFormat('HH:mm').format(DateTime.now());
            return Text(
              waktu,
              style: TextStyle(fontSize: 42, fontWeight: FontWeight.bold),
            );
          },
        ),
        Text(
          tanggal,
          style: TextStyle(fontSize: 14, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildAbsenCard() {
    String uid = FirebaseAuth.instance.currentUser!.uid;
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('absen')
            .where('user_id', isEqualTo: uid)
            .where('tanggal', isEqualTo: today)
            .snapshots(),
        builder: (context, snapshot) {
          String absenMasuk = '--:--';
          String absenPulang = '--:--';

          if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
            final data = snapshot.data!.docs.first.data() as Map<String, dynamic>;
            absenMasuk = data['waktu_masuk'] ?? '--:--';
            absenPulang = data['waktu_pulang'] ?? '--:--';
          }
          return Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Flexible(
                    child: Column(
                      children: [
                        Text('Absen Masuk',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(height: 8),
                        Text(absenMasuk, style: TextStyle(fontSize: 20)),
                      ],
                    ),
                  ),
                  Flexible(
                    child: Column(
                      children: [
                        Text('Absen Pulang',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(height: 8),
                        Text(absenPulang, style: TextStyle(fontSize: 20)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
    );
  }

  Future<void> _markAsRead(String docId) async {
    try {
      await FirebaseFirestore.instance
          .collection('izin')
          .doc(docId)
          .update({'visible': "false"});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Izin telah ditandai sebagai sudah dibaca'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal menandai izin: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildIzinCard() {
    String uid = FirebaseAuth.instance.currentUser!.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('izin')
          .where('user_id', isEqualTo: uid)
          .where('visible', isEqualTo: "true")
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          return Container(
            height: 140, // Tinggi diperbesar lebih banyak
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                final izin = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                String status = izin['status'] ?? 'Pending';
                String tanggal = izin['tanggal'] ?? '';
                String keterangan = izin['keterangan'] ?? '';
                String jenisIzin = izin['jenis_izin'] ?? izin['jenis'] ?? 'Izin'; // Field untuk jenis izin
                String docId = snapshot.data!.docs[index].id;

                // Format tanggal
                String tanggalFormatted = '';
                try {
                  if (tanggal.isNotEmpty) {
                    final dt = DateTime.parse(tanggal);
                    tanggalFormatted = DateFormat('dd MMM yyyy', 'id_ID').format(dt);
                  }
                } catch (e) {
                  tanggalFormatted = tanggal;
                }

                Color statusColor;
                if (status == 'Pending') {
                  statusColor = Colors.orange;
                } else if (status == 'Diterima') {
                  statusColor = Colors.green;
                } else {
                  statusColor = Colors.red;
                }

                return Container(
                  width: 260, // Lebar diperbesar untuk menampung lebih banyak teks
                  margin: EdgeInsets.only(right: 12),
                  child: Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)
                    ),
                    elevation: 3,
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header dengan icon dan status
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Icon(Icons.assignment, color: statusColor, size: 20),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  status,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 6),

                          // Expanded untuk konten yang bisa fleksibel
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Jenis Izin
                                Text(
                                  jenisIzin,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                SizedBox(height: 2),

                                // Tanggal - ditampilkan untuk semua status
                                if (tanggalFormatted.isNotEmpty)
                                  Text(
                                    tanggalFormatted,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[700],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                SizedBox(height: 2),

                                // Keterangan - ditampilkan untuk semua status
                                if (keterangan.isNotEmpty)
                                  Expanded(
                                    child: Text(
                                      keterangan,
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.grey[600],
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          // Tombol "Sudah Dibaca" hanya untuk status selain Pending
                          if (status != 'Pending')
                            Align(
                              alignment: Alignment.centerRight,
                              child: ElevatedButton(
                                onPressed: () => _markAsRead(docId),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.deepPurple,
                                  minimumSize: Size(60, 22),
                                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                ),
                                child: Text(
                                  'Sudah Dibaca',
                                  style: TextStyle(
                                    fontSize: 8,
                                    color: Colors.white,
                                  ),
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
        } else {
          return SizedBox();
        }
      },
    );
  }

  Widget _buildChart() {
    String uid = FirebaseAuth.instance.currentUser!.uid;
    String monthYear = _getMonthYearFormat(selectedMonth);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('absen')
          .where('user_id', isEqualTo: uid)
          .where('tanggal', isGreaterThanOrEqualTo: '$monthYear-01')
          .where('tanggal', isLessThan: _getNextMonth(monthYear))
          .snapshots(),
      builder: (context, absenSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('izin')
              .where('user_id', isEqualTo: uid)
              .where('tanggal', isGreaterThanOrEqualTo: '$monthYear-01')
              .where('tanggal', isLessThan: _getNextMonth(monthYear))
              .where('status', isEqualTo: 'Diterima')
              .snapshots(),
          builder: (context, izinSnapshot) {
            int masuk = 0;
            int izin = 0;
            int tidakMasuk = 0;
            String today = DateFormat('yyyy-MM-dd').format(DateTime.now());

            if (absenSnapshot.hasData) {
              // Get approved permit dates
              Map<String, bool> izinDates = {};
              if (izinSnapshot.hasData) {
                for (var doc in izinSnapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;

                  String tanggal = '';
                  if (data['tanggal'] is Timestamp) {
                    DateTime dateTime = (data['tanggal'] as Timestamp).toDate();
                    tanggal = DateFormat('yyyy-MM-dd').format(dateTime);
                  } else if (data['tanggal'] is String) {
                    tanggal = data['tanggal'] as String;
                  }

                  if (tanggal.isNotEmpty) {
                    izinDates[tanggal] = true;
                  }
                }
              }

              // Process attendance data
              for (var doc in absenSnapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;

                String tanggal = '';
                if (data['tanggal'] is Timestamp) {
                  DateTime dateTime = (data['tanggal'] as Timestamp).toDate();
                  tanggal = DateFormat('yyyy-MM-dd').format(dateTime);
                } else if (data['tanggal'] is String) {
                  tanggal = data['tanggal'] as String;
                }

                if (tanggal.isEmpty) continue;

                String waktuMasuk = data['waktu_masuk']?.toString() ?? '';

                // Determine status based on priority:
                if (izinDates.containsKey(tanggal)) {
                  izin++;
                } else if (waktuMasuk.isNotEmpty && waktuMasuk != '--:--') {
                  masuk++;
                } else if (tanggal == today) {
                  continue;
                } else {
                  tidakMasuk++;
                }
              }
            }

            // Check if there's any data to display
            int totalData = masuk + izin + tidakMasuk;
            if (totalData == 0) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Rekap Kehadiran $selectedMonth',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    SizedBox(height: 20),
                    Center(
                      child: Text(
                        'Tidak ada data untuk bulan ini',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              );
            }

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Rekap Kehadiran $selectedMonth',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  SizedBox(height: 12),
                  // Legend
                  Wrap(
                    alignment: WrapAlignment.spaceEvenly,
                    children: [
                      _buildLegendItem('Masuk', Colors.green, masuk),
                      _buildLegendItem('Izin', Colors.orange, izin),
                      _buildLegendItem('Tidak Masuk', Colors.red, tidakMasuk),
                    ],
                  ),
                  SizedBox(height: 16),
                  Container(
                    height: 250,
                    child: PieChart(
                      PieChartData(
                        sections: [
                          if (masuk > 0) PieChartSectionData(
                            value: masuk.toDouble(),
                            color: Colors.green,
                            title: 'Masuk\n$masuk',
                            radius: 80,
                            titleStyle: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          if (izin > 0) PieChartSectionData(
                            value: izin.toDouble(),
                            color: Colors.orange,
                            title: 'Izin\n$izin',
                            radius: 80,
                            titleStyle: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          if (tidakMasuk > 0) PieChartSectionData(
                            value: tidakMasuk.toDouble(),
                            color: Colors.red,
                            title: 'Tidak\nMasuk\n$tidakMasuk',
                            radius: 80,
                            titleStyle: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                        sectionsSpace: 4,
                        centerSpaceRadius: 30,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLegendItem(String label, Color color, int count) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          SizedBox(width: 4),
          Text(
            '$label ($count)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAbsenTable() {
    String uid = FirebaseAuth.instance.currentUser!.uid;
    String monthYear = _getMonthYearFormat(selectedMonth);
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('absen')
          .where('user_id', isEqualTo: uid)
          .where('tanggal', isGreaterThanOrEqualTo: '$monthYear-01')
          .where('tanggal', isLessThan: _getNextMonth(monthYear))
          .snapshots(),
      builder: (context, absenSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('izin')
              .where('user_id', isEqualTo: uid)
              .where('tanggal', isGreaterThanOrEqualTo: '$monthYear-01')
              .where('tanggal', isLessThan: _getNextMonth(monthYear))
              .where('status', isEqualTo: 'Diterima')
              .snapshots(),
          builder: (context, izinSnapshot) {
            List<Map<String, dynamic>> allData = [];

            if (absenSnapshot.hasData) {
              Map<String, Map<String, dynamic>> absenData = {};

              for (var doc in absenSnapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;

                String tanggal = '';
                if (data['tanggal'] is Timestamp) {
                  DateTime dateTime = (data['tanggal'] as Timestamp).toDate();
                  tanggal = DateFormat('yyyy-MM-dd').format(dateTime);
                } else if (data['tanggal'] is String) {
                  tanggal = data['tanggal'] as String;
                } else {
                  continue;
                }

                Map<String, dynamic> standardizedData = {...data};
                standardizedData['tanggal'] = tanggal;
                absenData[tanggal] = standardizedData;
              }

              Map<String, bool> izinDates = {};
              if (izinSnapshot.hasData) {
                for (var doc in izinSnapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;

                  String tanggal = '';
                  if (data['tanggal'] is Timestamp) {
                    DateTime dateTime = (data['tanggal'] as Timestamp).toDate();
                    tanggal = DateFormat('yyyy-MM-dd').format(dateTime);
                  } else if (data['tanggal'] is String) {
                    tanggal = data['tanggal'] as String;
                  } else {
                    continue;
                  }

                  izinDates[tanggal] = true;
                }
              }

              absenData.forEach((tanggal, data) {
                String waktuMasuk = data['waktu_masuk']?.toString() ?? '';
                String keterangan;

                if (izinDates.containsKey(tanggal)) {
                  keterangan = 'Izin';
                } else if (waktuMasuk.isNotEmpty && waktuMasuk != '--:--') {
                  keterangan = 'Masuk';
                } else if (tanggal == today) {
                  keterangan = 'Belum Masuk';
                } else {
                  keterangan = 'Tidak Masuk';
                }

                String hariIndonesia = _getIndonesianDayName(data['hari']?.toString() ?? '');

                allData.add({
                  'tanggal': tanggal,
                  'hari': hariIndonesia,
                  'bulan': data['bulan']?.toString() ?? '',
                  'waktu_masuk': waktuMasuk,
                  'waktu_pulang': data['waktu_pulang']?.toString() ?? '--:--',
                  'keterangan': keterangan,
                });
              });

              allData.sort((a, b) => (a['tanggal'] as String).compareTo(b['tanggal'] as String));
            }

            if (allData.isEmpty) {
              return Center(
                child: Text('Tidak ada data untuk bulan ini'),
              );
            }

            return SingleChildScrollView(
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Rekap Kehadiran $selectedMonth',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingTextStyle: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple,
                          ),
                          dataTextStyle: TextStyle(fontSize: 12),
                          columns: [
                            DataColumn(label: Text('Tanggal')),
                            DataColumn(label: Text('Hari')),
                            DataColumn(label: Text('Jam Masuk')),
                            DataColumn(label: Text('Jam Pulang')),
                            DataColumn(label: Text('Keterangan')),
                          ],
                          rows: allData.map((data) {
                            String tanggalFormatted = '';
                            try {
                              final dt = DateTime.parse(data['tanggal']);
                              tanggalFormatted = DateFormat('dd-MM-yyyy').format(dt);
                            } catch (e) {
                              tanggalFormatted = data['tanggal'];
                            }

                            return DataRow(
                              cells: [
                                DataCell(Text(tanggalFormatted)),
                                DataCell(Text(data['hari'])),
                                DataCell(Text(data['waktu_masuk'] ?? '--:--')),
                                DataCell(Text(data['waktu_pulang'] ?? '--:--')),
                                DataCell(_buildKeteranganCell(data['keterangan'])),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _getIndonesianDayName(String englishDayName) {
    Map<String, String> dayTranslations = {
      'Monday': 'Senin',
      'Tuesday': 'Selasa',
      'Wednesday': 'Rabu',
      'Thursday': 'Kamis',
      'Friday': 'Jumat',
      'Saturday': 'Sabtu',
      'Sunday': 'Minggu',
    };

    return dayTranslations[englishDayName] ?? englishDayName;
  }

  Widget _buildKeteranganCell(String keterangan) {
    Color color;

    switch (keterangan) {
      case 'Masuk':
        color = Colors.green;
        break;
      case 'Izin':
        color = Colors.orange;
        break;
      case 'Belum Masuk':
        color = Colors.blue;
        break;
      case 'Tidak Masuk':
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        keterangan,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }

  String _getNextMonth(String monthYear) {
    final parts = monthYear.split('-');
    if (parts.length != 2) return '';

    int year = int.parse(parts[0]);
    int month = int.parse(parts[1]);

    if (month == 12) {
      year++;
      month = 1;
    } else {
      month++;
    }

    return '$year-${month.toString().padLeft(2, '0')}';
  }
}