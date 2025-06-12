import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

class ListKehadiranPage extends StatefulWidget {
  @override
  _ListKehadiranPageState createState() => _ListKehadiranPageState();
}

class _ListKehadiranPageState extends State<ListKehadiranPage> {
  List<Map<String, dynamic>> _combinedData = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('id_ID', null).then((_) {
      _fetchAttendanceData();
    });
  }

  Future<void> _fetchAttendanceData() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });

      String today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      QuerySnapshot usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', whereIn: ['Guru', 'Staff'])
          .get();

      Map<String, Map<String, dynamic>> userData = {};
      for (var doc in usersSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        userData[doc.id] = {
          'id': doc.id,
          'name': data['name'] ?? 'Unknown',
          'role': data['role'] ?? 'Unknown',
          'status': 'Belum Hadir',
          'checkInTime': null,
          'checkOutTime': null,
          'alasan': null,
        };
      }

      QuerySnapshot izinSnapshot = await FirebaseFirestore.instance
          .collection('izin')
          .where('tanggal', isEqualTo: today)
          .where('jenis_izin', isEqualTo: 'Izin Tidak Masuk')
          .where('status', isEqualTo: 'Diterima')
          .get();

      for (var doc in izinSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        String userId = data['user_id'];

        if (userData.containsKey(userId)) {
          userData[userId]!['status'] = 'Izin Tidak Masuk';
          userData[userId]!['alasan'] = data['alasan'] ?? '';
        }
      }

      QuerySnapshot absenSnapshot = await FirebaseFirestore.instance
          .collection('absen')
          .where('tanggal', isEqualTo: today)
          .get();

      for (var doc in absenSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        String userId = data['user_id'];

        if (userData.containsKey(userId)) {
          if (data['waktu_masuk'] != null && data['waktu_masuk'].toString().isNotEmpty) {
            userData[userId]!['status'] = 'Hadir';
            userData[userId]!['checkInTime'] = data['waktu_masuk'];
            userData[userId]!['checkOutTime'] = data['waktu_pulang'] ?? null;
          }
        }
      }

      List<Map<String, dynamic>> combined = userData.values.toList();

      combined.sort((a, b) {
        Map<String, int> priority = {
          'Hadir': 0,
          'Izin Tidak Masuk': 1,
          'Belum Hadir': 2,
        };
        int statusComparison = priority[a['status']]!.compareTo(priority[b['status']]!);
        if (statusComparison != 0) return statusComparison;
        return a['name'].compareTo(b['name']);
      });

      setState(() {
        _combinedData = combined;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  void _setupRealTimeListener() {
    FirebaseFirestore.instance
        .collection('absen')
        .where('tanggal', isEqualTo: DateFormat('yyyy-MM-dd').format(DateTime.now()))
        .snapshots()
        .listen((snapshot) {
      _fetchAttendanceData();
    });

    FirebaseFirestore.instance
        .collection('izin')
        .where('tanggal', isEqualTo: DateFormat('yyyy-MM-dd').format(DateTime.now()))
        .snapshots()
        .listen((snapshot) {
      _fetchAttendanceData();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _setupRealTimeListener();
  }

  String _formatTime(dynamic timeValue) {
    if (timeValue == null) return '-';

    if (timeValue is Timestamp) {
      return DateFormat('HH:mm').format(timeValue.toDate());
    } else if (timeValue is String && timeValue.isNotEmpty) {
      return timeValue;
    }

    return '-';
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Hadir':
        return Colors.green;
      case 'Izin Tidak Masuk':
        return Colors.orange;
      case 'Belum Hadir':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Kehadiran Hari Ini', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _fetchAttendanceData,
            tooltip: 'Refresh Data',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(DateTime.now()),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text('Data Kehadiran Guru & Staff', style: TextStyle(color: Colors.grey.shade700)),
                  ],
                ),
                Row(
                  children: [
                    Icon(Icons.sync, size: 16, color: Colors.blue),
                    SizedBox(width: 4),
                    Text(
                      'Pembaruan Otomatis',
                      style: TextStyle(color: Colors.blue, fontStyle: FontStyle.italic, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!_isLoading && !_hasError)
            Padding(
              padding:const EdgeInsets.symmetric(horizontal: 6.0),
              child: Row(
                children: [
                  _buildSummaryCard('Hadir', _combinedData.where((item) => item['status'] == 'Hadir').length, Colors.green, Icons.check_circle),
                  SizedBox(width: 3),
                  _buildSummaryCard('Izin', _combinedData.where((item) => item['status'] == 'Izin Tidak Masuk').length, Colors.orange, Icons.event_note),
                  SizedBox(width: 3),
                  _buildSummaryCard('Belum Hadir', _combinedData.where((item) => item['status'] == 'Belum Hadir').length, Colors.red, Icons.warning),
                ],
              ),
            ),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _hasError
                ? Center(child: Text('Terjadi kesalahan: $_errorMessage'))
                : _combinedData.isEmpty
                ? Center(child: Text('Belum ada data guru atau staf.'))
                : _buildAttendanceTable(),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, int count, Color color, IconData icon) {
    return Expanded(
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w500, color: Colors.grey.shade700)),
                  Icon(icon, color: color, size: 18),
                ],
              ),
              SizedBox(height: 8),
              Text(
                count.toString(),
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttendanceTable() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: MaterialStateProperty.all(Colors.blue.shade50),
            dataRowMaxHeight: 64,
            columnSpacing: 20,
            columns: [
              DataColumn(label: Text('No', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Nama', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Jabatan', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Jam Masuk', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Jam Pulang', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Keterangan', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
            rows: List.generate(_combinedData.length, (index) {
              final item = _combinedData[index];
              return DataRow(
                color: index % 2 == 0
                    ? WidgetStateProperty.all(Colors.grey.shade50)
                    : null,
                cells: [
                  DataCell(Text('${index + 1}')),
                  DataCell(Text(item['name'] ?? 'Unknown')),
                  DataCell(Text(item['role'] ?? 'Unknown')),
                  DataCell(
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getStatusColor(item['status']).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _getStatusColor(item['status']), width: 1),
                      ),
                      child: Text(
                        item['status'] ?? 'Unknown',
                        style: TextStyle(
                          color: _getStatusColor(item['status']),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  DataCell(Text(_formatTime(item['checkInTime']))),
                  DataCell(Text(_formatTime(item['checkOutTime']))),
                  DataCell(
                        () {
                      if (item['status'] == 'Hadir') {
                        return Text('Sudah Masuk');
                      } else if (item['status'] == 'Izin Tidak Masuk') {
                        return Tooltip(
                          message: item['alasan'] ?? 'Tidak ada keterangan',
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.info_outline, color: Colors.orange, size: 16),
                              SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'Izin',
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false,
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      } else {
                        return Text('Belum Hadir');
                      }
                    }(),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}
