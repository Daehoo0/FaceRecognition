import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:intl/intl.dart';

class IzinPage extends StatefulWidget {
  @override
  _IzinPageState createState() => _IzinPageState();
}

class _IzinPageState extends State<IzinPage> {
  final TextEditingController _alasanController = TextEditingController();
  DateTime? _selectedDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  Uint8List? photoBytes;
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;
  String _currentIzinType = '';

  // Define work hour boundaries
  final TimeOfDay _workStartTime = TimeOfDay(hour: 7, minute: 0);  // 07:00
  final TimeOfDay _workEndTime = TimeOfDay(hour: 16, minute: 0);   // 16:00

  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (pickedFile != null) {
      Uint8List bytes = await pickedFile.readAsBytes();
      setState(() {
        photoBytes = bytes;
      });
    }
  }

  Future<void> _pickDate(String izinType) async {
    // Set first selectable date based on izin type
    DateTime firstDate;
    DateTime initialDate;

    if (izinType == "Izin Tidak Masuk") {
      // For "Izin Tidak Masuk" - only future dates (tomorrow onwards)
      firstDate = DateTime.now().add(Duration(days: 1));
      initialDate = firstDate;
    } else {
      // For "Izin Sementara" - today and future dates
      firstDate = DateTime.now();
      initialDate = DateTime.now();
    }

    DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: DateTime.now().add(Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.blue,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: Colors.blue,
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      setState(() {
        _selectedDate = pickedDate;
        // Reset time values when date changes
        _startTime = null;
        _endTime = null;
      });
    }
  }

  Future<void> _pickTime(bool isStart) async {
    // Initialize with appropriate defaults
    TimeOfDay initialTime;

    if (isStart) {
      initialTime = _workStartTime;
    } else {
      initialTime = _startTime != null ?
      TimeOfDay(hour: (_startTime!.hour + 1).clamp(7, 16), minute: _startTime!.minute) :
      _workStartTime;
    }

    TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.blue,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: Colors.blue,
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedTime != null) {
      // Validate if time is within working hours
      if (!_isTimeWithinWorkHours(pickedTime)) {
        _showErrorMessage('Waktu harus antara jam 07:00 - 16:00');
        return;
      }

      setState(() {
        if (isStart) {
          _startTime = pickedTime;
          // If end time is before or equal to start time, reset end time
          if (_endTime != null) {
            if (_compareTimeOfDay(_startTime!, _endTime!) >= 0) {
              _endTime = null;
            }
          }
        } else {
          // Ensure end time is after start time
          if (_startTime != null && _compareTimeOfDay(pickedTime, _startTime!) > 0) {
            _endTime = pickedTime;
          } else if (_startTime != null) {
            // Show error message if end time is not after start time
            _showErrorMessage('Jam selesai harus setelah jam mulai');
          } else {
            _endTime = pickedTime;
          }
        }
      });
    }
  }

  // Utility function to check if time is within work hours
  bool _isTimeWithinWorkHours(TimeOfDay time) {
    // Convert TimeOfDay to minutes for easier comparison
    int timeInMinutes = time.hour * 60 + time.minute;
    int startInMinutes = _workStartTime.hour * 60 + _workStartTime.minute;
    int endInMinutes = _workEndTime.hour * 60 + _workEndTime.minute;

    return timeInMinutes >= startInMinutes && timeInMinutes <= endInMinutes;
  }

  // Utility function to compare two TimeOfDay objects
  int _compareTimeOfDay(TimeOfDay time1, TimeOfDay time2) {
    int time1Minutes = time1.hour * 60 + time1.minute;
    int time2Minutes = time2.hour * 60 + time2.minute;

    if (time1Minutes < time2Minutes) return -1;
    if (time1Minutes > time2Minutes) return 1;
    return 0;
  }

  // Format TimeOfDay to display with leading zeros
  String _formatTimeOfDay(TimeOfDay time) {
    return "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";
  }

  Future<void> _submitIzin(String izinType) async {
    // Validate required fields
    if (_alasanController.text.isEmpty) {
      _showErrorMessage('Alasan izin tidak boleh kosong');
      return;
    }

    if (_selectedDate == null) {
      _showErrorMessage('Tanggal izin harus dipilih');
      return;
    }

    if (izinType == "Izin Sementara" && (_startTime == null || _endTime == null)) {
      _showErrorMessage('Jam mulai dan jam selesai harus dipilih');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showErrorMessage('User tidak ditemukan, silakan login kembali');
        return;
      }

      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (!userDoc.exists) {
        _showErrorMessage('Data user tidak ditemukan');
        return;
      }

      Map<String, dynamic>? userData = userDoc.data() as Map<String, dynamic>?;
      if (userData == null) return;

      String userId = user.uid;
      String userName = userData['name'] ?? "Anonymous";
      String userFoto = userData['profile'] ?? "";
      String alasan = _alasanController.text;
      String status = "Pending";
      String tanggal = DateFormat('yyyy-MM-dd').format(_selectedDate!);

      // Convert photo to base64 string if available
      String? photoBase64 = photoBytes != null ? base64Encode(photoBytes!) : null;

      Map<String, dynamic> izinData = {
        'user_id': userId,
        'nama': userName,
        'jenis_izin': izinType,
        'alasan': alasan,
        'status': status,
        'tanggal': tanggal,
        'keterangan': null,
        'foto_user': userFoto,
        'foto_izin': photoBase64,
        'timestamp': FieldValue.serverTimestamp(),
        'visible': 'true',
      };

      if (izinType == "Izin Sementara" && _startTime != null && _endTime != null) {
        izinData['jam_mulai'] = _formatTimeOfDay(_startTime!);
        izinData['jam_selesai'] = _formatTimeOfDay(_endTime!);
      }

      await FirebaseFirestore.instance.collection('izin').add(izinData);

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Permintaan izin berhasil dikirim'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      _showErrorMessage('Terjadi kesalahan: ${e.toString()}');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _resetForm() {
    _alasanController.clear();
    setState(() {
      _selectedDate = null;
      _startTime = null;
      _endTime = null;
      photoBytes = null;
    });
  }

  void _showIzinForm(String izinType) {
    _resetForm();
    setState(() {
      _currentIzinType = izinType;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, -5),
                ),
              ],
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Form $izinType',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[800],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: Colors.grey),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  Divider(thickness: 1),
                  SizedBox(height: 10),

                  // Alasan field
                  Text(
                    'Alasan Izin',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 8),
                  TextField(
                    controller: _alasanController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Masukkan alasan izin...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.blue, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      contentPadding: EdgeInsets.all(16),
                    ),
                  ),
                  SizedBox(height: 16),

                  // Date picker
                  Text(
                    'Tanggal Izin',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 8),
                  InkWell(
                    onTap: () => _pickDate(izinType).then((_) {
                      setModalState(() {});
                    }),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10),
                        color: Colors.grey.shade50,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, color: Colors.blue),
                          SizedBox(width: 10),
                          Text(
                            _selectedDate == null
                                ? "Pilih Tanggal"
                                : DateFormat('dd MMMM yyyy').format(_selectedDate!),
                            style: TextStyle(
                              fontSize: 16,
                              color: _selectedDate == null ? Colors.grey : Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 16),

                  // Time picker for "Izin Sementara"
                  if (izinType == "Izin Sementara") ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Jam Mulai',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                              SizedBox(height: 8),
                              InkWell(
                                onTap: () => _pickTime(true).then((_) {
                                  setModalState(() {});
                                }),
                                child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(10),
                                    color: Colors.grey.shade50,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.access_time, color: Colors.blue),
                                      SizedBox(width: 10),
                                      Text(
                                        _startTime == null
                                            ? "Pilih Jam"
                                            : _formatTimeOfDay(_startTime!),
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: _startTime == null ? Colors.grey : Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Jam Selesai',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                              SizedBox(height: 8),
                              InkWell(
                                onTap: () => _pickTime(false).then((_) {
                                  setModalState(() {});
                                }),
                                child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(10),
                                    color: Colors.grey.shade50,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.access_time, color: Colors.blue),
                                      SizedBox(width: 10),
                                      Text(
                                        _endTime == null
                                            ? "Pilih Jam"
                                            : _formatTimeOfDay(_endTime!),
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: _endTime == null ? Colors.grey : Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Center(
                      child: Text(
                        'Waktu izin hanya tersedia antara jam 07:00 - 16:00',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    SizedBox(height: 16),
                  ],

                  // Photo picker
                  Text(
                    'Dokumentasi',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 8),
                  InkWell(
                    onTap: () => _pickImage().then((_) {
                      setModalState(() {});
                    }),
                    child: Container(
                      width: double.infinity,
                      height: 120,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10),
                        color: Colors.grey.shade50,
                      ),
                      child: photoBytes != null
                          ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(
                          photoBytes!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                      )
                          : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.photo_camera, size: 40, color: Colors.blue),
                          SizedBox(height: 8),
                          Text(
                            'Tambahkan Foto',
                            style: TextStyle(color: Colors.blue),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 24),

                  // Submit button
                  Container(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : () => _submitIzin(izinType),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 2,
                      ),
                      child: _isLoading
                          ? CircularProgressIndicator(color: Colors.white)
                          : Text(
                        'Kirim Permintaan',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Pengajuan Izin',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade50, Colors.white],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Jenis Izin',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade800,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Text(
                  'Silakan pilih jenis izin yang akan diajukan',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade700,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 40),

                // Izin Tidak Masuk Card
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: InkWell(
                    onTap: () => _showIzinForm('Izin Tidak Masuk'),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Container(
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.red.shade100,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.calendar_month_outlined,
                              size: 40,
                              color: Colors.red.shade700,
                            ),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Izin Tidak Masuk',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade700,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Untuk pengajuan izin sehari penuh',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 20),

                // Izin Sementara Card
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: InkWell(
                    onTap: () => _showIzinForm('Izin Sementara'),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Container(
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade100,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.timer_outlined,
                              size: 40,
                              color: Colors.blue.shade700,
                            ),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Izin Sementara',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Untuk izin beberapa jam (07:00-16:00)',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}