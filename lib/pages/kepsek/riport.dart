import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:file_saver/file_saver.dart';
import 'package:open_filex/open_filex.dart';
// import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';

class ReportKehadiranPage extends StatefulWidget {
  @override
  _ReportKehadiranPageState createState() => _ReportKehadiranPageState();
}

// Helper functions untuk PDF - pindahkan ke luar class
pw.Widget buildHeaderCell(String text) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(5),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      textAlign: pw.TextAlign.center,
    ),
  );
}

pw.Widget buildSubHeaderCell(String text) {
  return pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(2),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(),
      ),
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 8),
        textAlign: pw.TextAlign.center,
      ),
    ),
  );
}

pw.Widget buildCell(String text) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(5),
    child: pw.Text(
      text,
      style: const pw.TextStyle(fontSize: 10),
      textAlign: pw.TextAlign.center,
    ),
  );
}

pw.Widget buildDataCell(String text) {
  return pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(2),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(),
      ),
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 8),
        textAlign: pw.TextAlign.center,
      ),
    ),
  );
}

class _ReportKehadiranPageState extends State<ReportKehadiranPage> {
  String? selectedMonth;
  bool isLoading = false;
  List<Map<String, dynamic>> reportData = [];
  String? downloadPath; // Untuk menyimpan path file yang diunduh
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // List bulan untuk dropdown
  final List<Map<String, String>> months = [
    {"value": "01", "label": "Januari"},
    {"value": "02", "label": "Februari"},
    {"value": "03", "label": "Maret"},
    {"value": "04", "label": "April"},
    {"value": "05", "label": "Mei"},
    {"value": "06", "label": "Juni"},
    {"value": "07", "label": "Juli"},
    {"value": "08", "label": "Agustus"},
    {"value": "09", "label": "September"},
    {"value": "10", "label": "Oktober"},
    {"value": "11", "label": "November"},
    {"value": "12", "label": "Desember"},
  ];

  // Helper functions untuk PDF
  pw.Widget _buildHeaderCell(String text) {
    return pw.Container(
      padding: pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  pw.Widget _buildSubHeaderCell(String text) {
    return pw.Expanded(
      child: pw.Container(
        padding: pw.EdgeInsets.all(2),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(),
        ),
        child: pw.Text(
          text,
          style: pw.TextStyle(fontSize: 8),
          textAlign: pw.TextAlign.center,
        ),
      ),
    );
  }

  pw.Widget _buildCell(String text) {
    return pw.Container(
      padding: pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 10),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  pw.Widget _buildDataCell(String text) {
    return pw.Expanded(
      child: pw.Container(
        padding: pw.EdgeInsets.all(2),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(),
        ),
        child: pw.Text(
          text,
          style: pw.TextStyle(fontSize: 8),
          textAlign: pw.TextAlign.center,
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _generateReport(String month) async {
    List<Map<String, dynamic>> reportData = [];
    String year = DateTime.now().year.toString();

    try {
      // 1. Ambil data red_days (tanggal merah) pada bulan yang dipilih
      List<String> redDays = [];
      QuerySnapshot redDaysSnapshot = await _firestore
          .collection('red_days')
          .where('date', isGreaterThanOrEqualTo: '$year-$month-01')
          .where('date', isLessThan: '$year-${(int.parse(month) + 1).toString().padLeft(2, '0')}-01')
          .where('isRed', isEqualTo: true)
          .get();

      for (var doc in redDaysSnapshot.docs) {
        String tanggal = doc['date'] as String;
        redDays.add(tanggal);
      }

      // 2. Ambil jumlah hari dalam bulan yang dipilih
      int daysInMonth = DateTime(int.parse(year), int.parse(month) + 1, 0).day;

      // 3. Hitung hari Minggu dalam bulan tersebut
      List<int> sundays = [];
      for (int day = 1; day <= daysInMonth; day++) {
        DateTime date = DateTime(int.parse(year), int.parse(month), day);
        if (date.weekday == DateTime.sunday) {
          sundays.add(day);
        }
      }

      // 4. Ambil data pengguna dengan role Guru/Staff
      QuerySnapshot usersSnapshot = await _firestore
          .collection('users')
          .where('role', whereIn: ['Guru', 'Staff'])
          .get();

      for (var userDoc in usersSnapshot.docs) {
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
        String userId = userDoc.id;

        // Tentukan status guru (Tetap/Honorer)
        String status = userData['status'] ?? 'Tetap';

        // Ambil jam masuk & pulang, default jika tidak tersedia
        String jamMasukStr = userData['jam_masuk'] ?? '07:00';
        String jamPulangStr = userData['jam_pulang'] ?? '16:00';

        DateTime jamMasukDefault;
        DateTime jamPulangDefault;
        DateTime batasTepatWaktu;

        try {
          jamMasukDefault = DateFormat('HH:mm').parse(jamMasukStr);
          jamPulangDefault = DateFormat('HH:mm').parse(jamPulangStr);
          batasTepatWaktu = jamMasukDefault.add(Duration(minutes: 4));
        } catch (e) {
          // Fallback kalau parsing gagal
          jamMasukDefault = DateFormat('HH:mm').parse('07:00');
          jamPulangDefault = DateFormat('HH:mm').parse('16:00');
          batasTepatWaktu = jamMasukDefault.add(Duration(minutes: 4));
        }


        // Hitung jumlah hari kerja berdasarkan status
        int hariKerja = daysInMonth - sundays.length - redDays.length;

        // Untuk guru honorer, kurangi juga dengan hari libur mereka
        if (status == 'Honorer' && userData.containsKey('hari_libur')) {
          List<dynamic> hariLibur = userData['hari_libur'] ?? [];

          // Hitung jumlah hari libur dalam bulan
          int jumlahHariLibur = 0;
          for (int day = 1; day <= daysInMonth; day++) {
            DateTime date = DateTime(int.parse(year), int.parse(month), day);

            // Format nama hari sesuai dengan yang disimpan di database (contoh: 'Senin', 'Selasa', dsb)
            String namaHari = DateFormat('EEEE', 'id_ID').format(date);

            // Jika hari ini adalah hari libur guru & bukan hari Minggu & bukan tanggal merah
            if (hariLibur.contains(namaHari) &&
                date.weekday != DateTime.sunday &&
                !redDays.contains('$year-$month-${day.toString().padLeft(2, '0')}')) {
              jumlahHariLibur++;
            }
          }

          hariKerja -= jumlahHariLibur;
        }

        // Initialize counters dengan nilai awal 0 untuk semua
        Map<String, int> counters = {
          'tepat_waktu': 0,
          'terlambat_5_30': 0,
          'terlambat_31_60': 0,
          'terlambat_61_90': 0,
          'terlambat_90plus': 0,
          'mendahului_1_30': 0,
          'mendahului_31_60': 0,
          'mendahului_61_90': 0,
          'mendahului_90plus': 0,
          'cuti': 0,
          'izin': 0,
          'tidak_presensi': 0,
        };

        // 5. Ambil data izin bulan ini terlebih dahulu
        Map<String, bool> izinApproved = {};
        QuerySnapshot izinSnapshot = await _firestore
            .collection('izin')
            .where('user_id', isEqualTo: userId)
            .where('tanggal', isGreaterThanOrEqualTo: '$year-$month-01')
            .where('tanggal', isLessThan: '$year-${(int.parse(month) + 1).toString().padLeft(2, '0')}-01')
            .where('status', isEqualTo: 'Diterima')
            .get();

        // Buatkan mapping tanggal izin untuk memudahkan pengecekan
        for (var izin in izinSnapshot.docs) {
          String tanggalIzin = izin['tanggal'];
          izinApproved[tanggalIzin] = true;
        }

        // Hitung jumlah izin yang disetujui
        counters['izin'] = izinSnapshot.docs.length;

        // 6. Get attendance data
        QuerySnapshot absenSnapshot = await _firestore
            .collection('absen')
            .where('user_id', isEqualTo: userId)
            .where('tanggal', isGreaterThanOrEqualTo: '$year-$month-01')
            .where('tanggal', isLessThan: '$year-${(int.parse(month) + 1).toString().padLeft(2, '0')}-01')
            .get();

        // 7. Buat mapping tanggal yang ada data absen
        Map<String, Map<String, dynamic>> tanggalAbsen = {};
        for (var absen in absenSnapshot.docs) {
          Map<String, dynamic> data = absen.data() as Map<String, dynamic>;
          String tanggal = data['tanggal'] ?? '';
          tanggalAbsen[tanggal] = data;
        }

        // 8. Proses data absensi per hari kerja
        // Cek setiap hari dalam bulan
        for (int day = 1; day <= daysInMonth; day++) {
          String dayStr = day.toString().padLeft(2, '0');
          String tanggal = '$year-$month-$dayStr';
          DateTime date = DateTime(int.parse(year), int.parse(month), day);

          // Skip hari Minggu dan tanggal merah
          if (date.weekday == DateTime.sunday || redDays.contains(tanggal)) {
            continue;
          }

          // Skip jika guru honorer dan ini adalah hari libur mereka
          if (status == 'Honorer' && userData.containsKey('hari_libur')) {
            List<dynamic> hariLibur = userData['hari_libur'] ?? [];
            String namaHari = DateFormat('EEEE', 'id_ID').format(date);
            if (hariLibur.contains(namaHari)) {
              continue;
            }
          }

          // Cek jika tanggal ini ada izin yang disetujui
          if (izinApproved.containsKey(tanggal)) {
            // Sudah dihitung pada langkah sebelumnya
            continue;
          }

          // Cek data absen untuk tanggal ini
          if (tanggalAbsen.containsKey(tanggal)) {
            Map<String, dynamic> data = tanggalAbsen[tanggal]!;
            String waktuMasuk = data['waktu_masuk'] ?? '';
            String waktuPulang = data['waktu_pulang'] ?? '';
            String keterangan = data['keterangan'] ?? '';

            // Cek keterangan "Tidak Masuk"
            if (waktuMasuk.isEmpty && waktuPulang.isEmpty && keterangan.toLowerCase() == 'tidak masuk') {
              counters['tidak_presensi'] = counters['tidak_presensi']! + 1;
              continue;
            }

            // Proses data kehadiran normal
            if (waktuMasuk.isNotEmpty) {
              // Validasi format waktu masuk
              DateTime jamMasuk;
              try {
                jamMasuk = DateFormat('HH:mm').parse(waktuMasuk);
              } catch (e) {
                print('Error parsing waktu_masuk: $waktuMasuk for date $tanggal');
                continue;
              }

              // Batas waktu untuk tepat waktu (07:04)
              DateTime batasTepatWaktu = DateFormat('HH:mm').parse('07:04');

              // Kategori keterlambatan
              int selisihMenitMasuk = jamMasuk.difference(jamMasukDefault).inMinutes;

              // Cek waktu pulang
              if (waktuPulang.isNotEmpty) {
                // Ada waktu pulang, cek kategori
                DateTime jamPulang;
                try {
                  jamPulang = DateFormat('HH:mm').parse(waktuPulang);
                } catch (e) {
                  print('Error parsing waktu_pulang: $waktuPulang for date $tanggal');
                  // Tetap proses waktu masuk
                  if (jamMasuk.compareTo(batasTepatWaktu) <= 0) {
                    counters['tepat_waktu'] = counters['tepat_waktu']! + 1;
                  } else {
                    // Terlambat (masuk > 07:04)
                    if (selisihMenitMasuk <= 30) counters['terlambat_5_30'] = counters['terlambat_5_30']! + 1;
                    else if (selisihMenitMasuk <= 60) counters['terlambat_31_60'] = counters['terlambat_31_60']! + 1;
                    else if (selisihMenitMasuk <= 90) counters['terlambat_61_90'] = counters['terlambat_61_90']! + 1;
                    else counters['terlambat_90plus'] = counters['terlambat_90plus']! + 1;
                  }
                  continue;
                }

                DateTime batasPulang = jamPulangDefault;

                // Tepat waktu jika masuk tepat waktu saja (≤ 07:04)
                if (jamMasuk.compareTo(batasTepatWaktu) <= 0) {
                  counters['tepat_waktu'] = counters['tepat_waktu']! + 1;
                } else {
                  // Terlambat (masuk > 07:04)
                  if (selisihMenitMasuk <= 30) counters['terlambat_5_30'] = counters['terlambat_5_30']! + 1;
                  else if (selisihMenitMasuk <= 60) counters['terlambat_31_60'] = counters['terlambat_31_60']! + 1;
                  else if (selisihMenitMasuk <= 90) counters['terlambat_61_90'] = counters['terlambat_61_90']! + 1;
                  else counters['terlambat_90plus'] = counters['terlambat_90plus']! + 1;
                }

                // Check mendahului terpisah
                if (jamPulang.compareTo(batasPulang) < 0) {
                  // Mendahului (pulang < 16:00)
                  int selisihMenitPulang = batasPulang.difference(jamPulang).inMinutes;

                  if (selisihMenitPulang <= 30) counters['mendahului_1_30'] = counters['mendahului_1_30']! + 1;
                  else if (selisihMenitPulang <= 60) counters['mendahului_31_60'] = counters['mendahului_31_60']! + 1;
                  else if (selisihMenitPulang <= 90) counters['mendahului_61_90'] = counters['mendahului_61_90']! + 1;
                  else counters['mendahului_90plus'] = counters['mendahului_90plus']! + 1;
                }
              } else {
                // Lupa absen pulang (waktu_pulang null)
                counters['tidak_presensi'] = counters['tidak_presensi']! + 1;
              }
            } else {
              // waktu_masuk null, hitung sebagai tidak presensi
              counters['tidak_presensi'] = counters['tidak_presensi']! + 1;
            }
          } else {
            // Tidak ada data absen sama sekali untuk hari ini
            counters['tidak_presensi'] = counters['tidak_presensi']! + 1;
          }
        }

        // Hitung persentase TMK
        double tmkPercent = hariKerja > 0 ?
        (counters['tidak_presensi']! / hariKerja) * 100 : 0;

        reportData.add({
          'nama': userData['name'] ?? 'Unknown',
          'nip': userData['nip'] ?? userData['nomor'] ?? '-',
          'status': status,
          'hari_kerja': hariKerja,
          ...counters,
          'tmk_percent': tmkPercent.round(),
        });
      }

      return reportData;
    } catch (e) {
      print('Error generating report: $e');
      throw e;
    }
  }


  Future<void> _generateAndDownloadPDF(List<Map<String, dynamic>> reportData, String month) async {
    final pdf = pw.Document();

    // Ambil nama bulan dan tahun ajaran
    String monthName = months.firstWhere((m) => m['value'] == month)['label']!;
    int currentYear = DateTime.now().year;
    int selectedMonthInt = int.parse(month);
    String academicYear = selectedMonthInt <= 6
        ? '${currentYear - 1}/$currentYear'
        : '$currentYear/${currentYear + 1}';

    String fileName = 'rekap_kehadiran_${monthName.toLowerCase()}_${currentYear}.pdf';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        header: (context) => pw.Column(
          children: [
            pw.Text(
              'REKAPITULASI KEHADIRAN PEGAWAI - $monthName $academicYear',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(),
              columnWidths: {
                0: pw.FlexColumnWidth(1),
                1: pw.FlexColumnWidth(3),
                2: pw.FlexColumnWidth(2),
                3: pw.FlexColumnWidth(2),
                4: pw.FlexColumnWidth(1),
                5: pw.FlexColumnWidth(1),
                6: pw.FlexColumnWidth(3),
                7: pw.FlexColumnWidth(3),
                8: pw.FlexColumnWidth(2.5),
                9: pw.FlexColumnWidth(1),
              },
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: PdfColors.lightBlue50),
                  children: [
                    buildHeaderCell('Bulan'),
                    buildHeaderCell('OPD'),
                    buildHeaderCell('Nama'),
                    buildHeaderCell('NIP / NIK'),
                    buildHeaderCell('Hari\nKerja'),
                    buildHeaderCell('Tepat\nWaktu'),
                    buildHeaderCell('Menit Keterlambatan'),
                    buildHeaderCell('Menit Mendahului'),
                    buildHeaderCell('Tanpa Keterangan'),
                    buildHeaderCell('% TMK'),
                  ],
                ),
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: PdfColors.lightBlue50),
                  children: [
                    buildCell(''),
                    buildCell(''),
                    buildCell(''),
                    buildCell(''),
                    buildCell(''),
                    buildCell(''),
                    pw.Row(
                      children: [
                        buildSubHeaderCell('5-30'),
                        buildSubHeaderCell('31-60'),
                        buildSubHeaderCell('61-90'),
                        buildSubHeaderCell('90+'),
                      ],
                    ),
                    pw.Row(
                      children: [
                        buildSubHeaderCell('1-30'),
                        buildSubHeaderCell('31-60'),
                        buildSubHeaderCell('61-90'),
                        buildSubHeaderCell('90+'),
                      ],
                    ),
                    pw.Row(
                      children: [
                        buildSubHeaderCell('Cuti'),
                        buildSubHeaderCell('Izin'),
                        buildSubHeaderCell('Tidak\nPresensi'),
                      ],
                    ),
                    buildCell(''),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
          ],
        ),
        build: (context) {
          return [
            pw.Table(
              border: pw.TableBorder.all(),
              columnWidths: {
                0: pw.FlexColumnWidth(1),
                1: pw.FlexColumnWidth(3),
                2: pw.FlexColumnWidth(2),
                3: pw.FlexColumnWidth(2),
                4: pw.FlexColumnWidth(1),
                5: pw.FlexColumnWidth(1),
                6: pw.FlexColumnWidth(3),
                7: pw.FlexColumnWidth(3),
                8: pw.FlexColumnWidth(2.5),
                9: pw.FlexColumnWidth(1),
              },
              children: reportData.map((data) {
                return pw.TableRow(
                  children: [
                    buildCell(monthName),
                    buildCell('UPTD SATUAN PENDIDIKAN SMP NEGERI 3 WARU'),
                    buildCell(data['nama']),
                    buildCell(data['nip'] ?? '-'),
                    buildCell(data['hari_kerja']?.toString() ?? '25'),
                    buildCell(data['tepat_waktu']?.toString() ?? '0'),
                    pw.Row(
                      children: [
                        buildDataCell(data['terlambat_5_30']?.toString() ?? '0'),
                        buildDataCell(data['terlambat_31_60']?.toString() ?? '0'),
                        buildDataCell(data['terlambat_61_90']?.toString() ?? '0'),
                        buildDataCell(data['terlambat_90plus']?.toString() ?? '0'),
                      ],
                    ),
                    pw.Row(
                      children: [
                        buildDataCell(data['mendahului_1_30']?.toString() ?? '0'),
                        buildDataCell(data['mendahului_31_60']?.toString() ?? '0'),
                        buildDataCell(data['mendahului_61_90']?.toString() ?? '0'),
                        buildDataCell(data['mendahului_90plus']?.toString() ?? '0'),
                      ],
                    ),
                    pw.Row(
                      children: [
                        buildDataCell(data['cuti']?.toString() ?? '0'),
                        buildDataCell(data['izin']?.toString() ?? '0'),
                        buildDataCell(data['tidak_presensi']?.toString() ?? '0'),
                      ],
                    ),
                    buildCell('${calculateTMKPercent(data)}'),
                  ],
                );
              }).toList(),
            ),
            pw.SizedBox(height: 20),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text('Waru, ${DateFormat('d MMMM yyyy').format(DateTime.now())}'),
                    pw.Text('Kepala UPTD Satuan Pendidikan'),
                    pw.Text('SMP Negeri 3 Waru'),
                    pw.SizedBox(height: 50),
                    pw.Text('MAS HUSEIN, S.Pd., M.M.Pd.'),
                    pw.Text('NIP. 196906042006041017'),
                  ],
                ),
              ],
            ),
          ];
        },
      ),
    );

    // Simpan dan buka file
    try {
      final bytes = await pdf.save();

      String? filePath = await FileSaver.instance.saveFile(
        name: fileName,
        bytes: bytes,
        ext: 'pdf',
        mimeType: MimeType.pdf,
      );

      if (filePath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF berhasil diunduh ke: $filePath')),
        );
        await OpenFilex.open(filePath);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF berhasil diunduh')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengunduh PDF: $e')),
      );
    }
  }

// Fungsi perhitungan % TMK
  int calculateTMKPercent(Map<String, dynamic> data) {
    int tidak_presensi = data['tidak_presensi'] ?? 0;
    int hari_kerja = data['hari_kerja'] ?? 0;

    // Cek pembagian dengan nol
    if (hari_kerja == 0) return 0;

    // Perhitungan persentase
    double percent = (tidak_presensi / hari_kerja) * 100;

    return percent.round();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Laporan Kehadiran'),
        backgroundColor: Colors.blue,
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 4,
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Download Laporan Kehadiran',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            decoration: InputDecoration(
                              labelText: 'Pilih Bulan',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            ),
                            value: selectedMonth,
                            items: months.map((month) {
                              return DropdownMenuItem<String>(
                                value: month['value']!,
                                child: Text(month['label']!),
                              );
                            }).toList(),
                            onChanged: (value) async {
                              setState(() {
                                selectedMonth = value;
                                isLoading = true;
                              });

                              try {
                                // Segera ambil data ketika bulan dipilih
                                final data = await _generateReport(value!);
                                setState(() {
                                  reportData = data;
                                  isLoading = false;
                                });
                              } catch (e) {
                                setState(() {
                                  isLoading = false;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error: $e')),
                                );
                              }
                            },
                          ),
                        ),
                        SizedBox(width: 16),
                        ElevatedButton.icon(
                          icon: Icon(Icons.download),
                          label: Text('Download PDF'),
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            backgroundColor: Colors.blue,
                          ),
                          onPressed: selectedMonth == null || isLoading || reportData.isEmpty
                              ? null
                              : () async {
                            setState(() {
                              isLoading = true;
                            });
                            try {
                              // Gunakan data yang sudah diambil
                              await _generateAndDownloadPDF(reportData, selectedMonth!);
                            } finally {
                              setState(() {
                                isLoading = false;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (isLoading)
              Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Memproses data...'),
                    ],
                  ),
                ),
              ),

            // Tambahkan bagian untuk menampilkan tabel data
            if (!isLoading && reportData.isNotEmpty)
              Expanded(
                child: Card(
                  elevation: 4,
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Data Kehadiran ${selectedMonth != null ? months.firstWhere((m) => m["value"] == selectedMonth)["label"] : ""}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 16),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                headingTextStyle: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade800,
                                ),
                                columns: [
                                  DataColumn(label: Text('Nama')),
                                  DataColumn(label: Text('NIP/NIK')),
                                  DataColumn(label: Text('Hari Kerja')),
                                  DataColumn(label: Text('Tepat Waktu')),
                                  DataColumn(label: Text('Terlambat 5-30')),
                                  DataColumn(label: Text('Terlambat 31-60')),
                                  DataColumn(label: Text('Terlambat 61-90')),
                                  DataColumn(label: Text('Terlambat >90')),
                                  DataColumn(label: Text('Mendahului 1-30')),
                                  DataColumn(label: Text('Mendahului 31-60')),
                                  DataColumn(label: Text('Mendahului 61-90')),
                                  DataColumn(label: Text('Mendahului >90')),
                                  DataColumn(label: Text('Cuti')),
                                  DataColumn(label: Text('Izin')),
                                  DataColumn(label: Text('Tidak Presensi')),
                                  DataColumn(label: Text('% TMK')),
                                ],
                                rows: reportData.map((data) {
                                  return DataRow(
                                    cells: [
                                      DataCell(Text(data['nama'] ?? '-')),
                                      DataCell(Text(data['nip'] ?? '-')),
                                      DataCell(Text(data['hari_kerja']?.toString() ?? '0')),
                                      DataCell(Text(data['tepat_waktu']?.toString() ?? '0')),
                                      DataCell(Text(data['terlambat_5_30']?.toString() ?? '0')),
                                      DataCell(Text(data['terlambat_31_60']?.toString() ?? '0')),
                                      DataCell(Text(data['terlambat_61_90']?.toString() ?? '0')),
                                      DataCell(Text(data['terlambat_90plus']?.toString() ?? '0')),
                                      DataCell(Text(data['mendahului_1_30']?.toString() ?? '0')),
                                      DataCell(Text(data['mendahului_31_60']?.toString() ?? '0')),
                                      DataCell(Text(data['mendahului_61_90']?.toString() ?? '0')),
                                      DataCell(Text(data['mendahului_90plus']?.toString() ?? '0')),
                                      DataCell(Text(data['cuti']?.toString() ?? '0')),
                                      DataCell(Text(data['izin']?.toString() ?? '0')),
                                      DataCell(Text(data['tidak_presensi']?.toString() ?? '0')),
                                      DataCell(Text('${calculateTMKPercent(data)}%')),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}