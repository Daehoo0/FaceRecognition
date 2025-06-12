import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:uuid/uuid.dart';

class SchedulePage extends StatefulWidget {
  @override
  _SchedulePageState createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Set<String> _redDays = {}; // Menyimpan daftar tanggal merah
  final _uuid = Uuid();

  @override
  void initState() {
    super.initState();
    _loadRedDays(); // Ambil data dari Firestore saat pertama kali halaman dibuka
  }

  /// 🔹 Mengambil daftar tanggal merah dari Firestore
  Future<void> _loadRedDays() async {
    final snapshot = await FirebaseFirestore.instance.collection('red_days').get();

    setState(() {
      _redDays = snapshot.docs.map((doc) => doc['date'] as String).toSet();
    });
  }

  /// 🔹 Menambah atau menghapus tanggal merah di Firestore
  Future<void> _toggleRedDay(DateTime date) async {
    String formattedDate = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

    final snapshot = await FirebaseFirestore.instance
        .collection('red_days')
        .where('date', isEqualTo: formattedDate)
        .get();

    if (snapshot.docs.isNotEmpty) {
      // Jika tanggal sudah ada, hapus dari Firestore
      await FirebaseFirestore.instance.collection('red_days').doc(snapshot.docs.first.id).delete();
      setState(() {
        _redDays.remove(formattedDate);
      });
    } else {
      // Jika tanggal belum ada, tambahkan dengan UUID sebagai document ID
      String uuid = _uuid.v4();
      await FirebaseFirestore.instance.collection('red_days').add({
        'date': formattedDate,
        'isRed': true,
      });

      setState(() {
        _redDays.add(formattedDate);
      });
    }

    // Perbarui UI setelah menyimpan atau menghapus data
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Jadwal Sekolah')),
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2000, 1, 1),
            lastDay: DateTime.utc(2100, 12, 31),
            focusedDay: _focusedDay,
            calendarFormat: _calendarFormat,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
              });
              _showOptionsDialog(selectedDay);
            },
            onFormatChanged: (format) {
              setState(() {
                _calendarFormat = format;
              });
            },
            onPageChanged: (focusedDay) {
              _focusedDay = focusedDay;
            },
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, date, events) {
                bool isSunday = date.weekday == DateTime.sunday;
                String formattedDate = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
                bool isRed = _redDays.contains(formattedDate) || isSunday;

                return Center(
                  child: Text(
                    date.day.toString(),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isRed ? Colors.red : Colors.black,
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(height: 10),
          Text('Klik tanggal untuk mengatur jadwal.', style: TextStyle(fontSize: 16)),
        ],
      ),
    );
  }

  /// 🔹 Menampilkan dialog konfirmasi saat memilih tanggal
  void _showOptionsDialog(DateTime date) {
    showDialog(
      context: context,
      builder: (context) {
        String formattedDate = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
        bool isMarked = _redDays.contains(formattedDate);

        return AlertDialog(
          title: Text("Atur Jadwal"),
          content: Text(isMarked ? "Hapus tanda merah pada tanggal ini?" : "Tandai tanggal ini sebagai merah?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Batal"),
            ),
            TextButton(
              onPressed: () async {
                await _toggleRedDay(date);
                Navigator.pop(context);
              },
              child: Text(isMarked ? "Hapus" : "Tandai"),
            ),
          ],
        );
      },
    );
  }
}
