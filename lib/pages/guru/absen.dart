import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class FaceAbsensiPage extends StatefulWidget {
  const FaceAbsensiPage({Key? key}) : super(key: key);

  @override
  State<FaceAbsensiPage> createState() => _FacePageState();
}

class _FacePageState extends State<FaceAbsensiPage> {
  // Platform detection
  bool _isWindows = false;
  bool _isAndroid = false;
  bool _isIOS = false;

  // Camera controller
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isBusy = false;

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  // Face detection
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableClassification: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.accurate,
      minFaceSize: 0.15,
    ),
  );

  // TFLite model
  Interpreter? _interpreter;
  bool _isModelReady = false;
  int _inputSize = 160; // FaceNet typically uses 160x160 input

  // User information
  User? _user;
  bool _hasEmbedding = false;
  bool _isVerifying = false;
  bool _isFaceDetected = false;
  bool _isProcessingImage = false;

  // Result status
  String _statusText = 'Initializing...';
  List<double>? _registeredEmbedding;

  // Face detection results
  Face? _detectedFace;

  // Timer for frame capture
  DateTime? _lastCaptureTime;

  // Network info
  final NetworkInfo _networkInfo = NetworkInfo();

  @override
  void initState() {
    super.initState();
    _detectPlatform();
  }

  Future<void> _initializeNotifications() async {
    if (_isWindows) return;

    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
    DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> _detectPlatform() async {
    // Check platform
    if (Platform.isWindows) {
      setState(() {
        _isWindows = true;
        _statusText = 'Aplikasi ini tidak mendukung Windows. Silakan gunakan perangkat Android atau iOS.';
      });

      // Show message box for Windows users
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showWindowsMessageBox();
      });
    } else if (Platform.isAndroid) {
      setState(() {
        _isAndroid = true;
      });
      _initializeServices();
    } else if (Platform.isIOS) {
      setState(() {
        _isIOS = true;
      });
      _initializeServices();
    } else {
      setState(() {
        _statusText = 'Platform tidak didukung. Silakan gunakan perangkat Android atau iOS.';
      });
    }
  }

  void _showWindowsMessageBox() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Platform Tidak Didukung'),
        content: const Text(
          'Aplikasi ini tidak dapat dijalankan di Windows. Fitur absensi wajah membutuhkan kamera dan sensor dari perangkat mobile.\n\n'
              'Silakan gunakan handphone Android atau iOS untuk melakukan absensi wajah.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // Exit from this screen
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _initializeServices() async {
    // Skip initialization if on Windows
    if (_isWindows) return;

    await requestPermissions();
    await _initializeNotifications();

    try {
      // Get current user
      _user = FirebaseAuth.instance.currentUser;

      if (_user == null) {
        setState(() {
          _statusText = 'No user logged in';
        });
        return;
      }

      // Initialize ML components in parallel for faster startup
      await Future.wait([
        _loadModel().then((_) {
          setState(() {
            _isModelReady = true;
          });
        }),
        _checkUserEmbedding(),
        _initializeCamera(),
      ]);

      setState(() {
        _statusText = 'Mencari wajah untuk verifikasi...';
      });
    } catch (e) {
      print('Initialization error: $e');
    }
  }

  Future<void> _checkUserEmbedding() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .get();

      final hasEmbedding = doc.exists && doc.data()?['embedding'] != null;

      if (!mounted) return;

      setState(() {
        _hasEmbedding = hasEmbedding;
        _statusText = 'Siap untuk verifikasi';

        if (hasEmbedding && doc.data() != null) {
          try {
            List<dynamic> rawEmbedding = doc.data()?['embedding'];
            if (rawEmbedding != null) {
              _registeredEmbedding = rawEmbedding.map((value) => value as double).toList();
            } else {
              _hasEmbedding = false;
              _statusText = 'Data wajah tidak ditemukan';
            }
          } catch (e) {
            _hasEmbedding = false;
            _statusText = 'Error reading face data';
          }
        }
      });
    } catch (e) {
      setState(() {
        _hasEmbedding = false;
      });
    }
  }

  Future<void> _initializeCamera() async {
    // Skip camera initialization if on Windows
    if (_isWindows) return;

    try {
      _cameras = await availableCameras();

      if (_cameras == null || _cameras!.isEmpty) {
        if (mounted) {
          setState(() {
            _statusText = 'No cameras available';
          });
        }
        return;
      }

      // Use front camera for face recognition
      final frontCamera = _cameras!.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();

      // Set exposure mode to auto for better face detection
      if (_cameraController!.value.exposureMode != ExposureMode.auto) {
        await _cameraController!.setExposureMode(ExposureMode.auto);
      }

      // Set focus mode to auto for better face detection
      if (_cameraController!.value.focusMode != FocusMode.auto) {
        await _cameraController!.setFocusMode(FocusMode.auto);
      }

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });

        // Start face detection
        _startFaceDetection();
      }
    } catch (e) {
      print('Camera error: $e');
    }
  }

  Future<void> _loadModel() async {
    // Skip model loading if on Windows
    if (_isWindows) return;

    try {
      // Close any existing interpreter
      if (_interpreter != null) {
        _interpreter!.close();
        _interpreter = null;
      }

      // Create interpreter options
      final options = InterpreterOptions()
        ..threads = 2
        ..useNnApiForAndroid = false;

      // Load model
      _interpreter = await Interpreter.fromAsset(
          'lib/assets/models/facenet.tflite',
          options: options
      );

      // Validate model input/output shapes
      final inputShape = _interpreter!.getInputTensor(0).shape;
      if (inputShape.length >= 3) {
        _inputSize = inputShape[1];
      }

    } catch (e) {
      print('Failed to load model: $e');
      throw e;
    }
  }

  void _startFaceDetection() {
    if (_isWindows) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    _processFrame();
  }

  Future<void> _processFrame() async {
    if (_isWindows) return;
    if (_isBusy || !mounted || _cameraController == null || !_cameraController!.value.isInitialized) {
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 500), _processFrame);
      }
      return;
    }

    _isBusy = true;

    try {
      // Limit capture frequency
      final now = DateTime.now();
      if (_lastCaptureTime != null &&
          now.difference(_lastCaptureTime!).inMilliseconds < 500) {
        _isBusy = false;
        if (mounted) {
          Future.delayed(const Duration(milliseconds: 500), _processFrame);
        }
        return;
      }

      _lastCaptureTime = now;

      // Take picture
      final image = await _cameraController!.takePicture();

      // Detect faces using ML Kit
      final inputImage = InputImage.fromFilePath(image.path);
      final faces = await _faceDetector.processImage(inputImage);

      if (!mounted) return;

      if (faces.isNotEmpty) {
        // Use the largest face if multiple are detected
        Face largestFace = faces.first;
        double maxArea = largestFace.boundingBox.width * largestFace.boundingBox.height;

        for (var face in faces) {
          double area = face.boundingBox.width * face.boundingBox.height;
          if (area > maxArea) {
            maxArea = area;
            largestFace = face;
          }
        }

        setState(() {
          _detectedFace = largestFace;
          _isFaceDetected = true;
          _statusText = 'Wajah terdeteksi! Tekan "Verifikasi Wajah" untuk absensi';
        });
      } else {
        setState(() {
          _isFaceDetected = false;
          _detectedFace = null;
          _statusText = 'Mencari wajah untuk verifikasi...';
        });
      }

      // Clean up the temporary image file
      try {
        await File(image.path).delete();
      } catch (e) {
        // Ignore file deletion errors
      }
    } catch (e) {
      print('Frame processing error: $e');
    } finally {
      _isBusy = false;

      // Continue processing frames if still mounted
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 500), _processFrame);
      }
    }
  }

  Future<List<double>> _generateEmbedding(File imageFile) async {
    if (_interpreter == null || !_isModelReady) {
      throw Exception('Model not ready');
    }

    try {
      final bytes = await imageFile.readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) throw Exception('Failed to decode image');

      final inputHeight = _inputSize;
      final inputWidth = _inputSize;

      img.Image resizedImage = img.copyResize(
        image,
        width: inputWidth,
        height: inputHeight,
        interpolation: img.Interpolation.linear,
      );

      // Buat input buffer dengan format [1, H, W, 3]
      final inputBuffer = List.generate(
        1,
            (_) => List.generate(
          inputHeight,
              (y) => List.generate(
            inputWidth,
                (x) {
              final pixel = resizedImage.getPixel(x, y);
              return [
                (pixel.r / 127.5) - 1.0,
                (pixel.g / 127.5) - 1.0,
                (pixel.b / 127.5) - 1.0,
              ];
            },
          ),
        ),
      );

      // Buat output buffer dengan format [1, 512]
      final outputShape = _interpreter!.getOutputTensor(0).shape;
      final outputSize = outputShape[1];
      final outputBuffer = List.generate(1, (_) => List.filled(outputSize, 0.0));

      _interpreter!.run(inputBuffer, outputBuffer);

      final embedding = outputBuffer[0];

      // L2 Normalization
      double sumSquared = embedding.fold(0.0, (sum, e) => sum + e * e);
      double norm = math.sqrt(math.max(sumSquared, 1e-10));
      return embedding.map((e) => e / norm).toList();
    } catch (e) {
      print('Error in _generateEmbedding: $e');
      throw Exception('Embedding generation failed');
    }
  }

  double _calculateSimilarity(List<double> embedding1, List<double> embedding2) {
    if (embedding1.length != embedding2.length) {
      throw Exception('Embedding dimensions do not match');
    }

    // Calculate cosine similarity
    double dotProduct = 0;
    for (int i = 0; i < embedding1.length; i++) {
      dotProduct += embedding1[i] * embedding2[i];
    }

    return math.max(0.0, math.min(1.0, dotProduct));
  }

  Future<void> _verifyFace(File imageFile) async {
    if (_registeredEmbedding == null) {
      setState(() {
        _statusText = 'No registered face data found';
      });
      return;
    }

    setState(() {
      _isVerifying = true;
      _statusText = 'Memverifikasi wajah...';
    });

    try {
      final currentEmbedding = await _generateEmbedding(imageFile);
      final similarity = _calculateSimilarity(currentEmbedding, _registeredEmbedding!);
      final similarityPercent = (similarity * 100).toStringAsFixed(2);

      // Check for liveness
      final isLive = await _checkLiveness(imageFile);
      if (!isLive) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Peringatan'),
            content: const Text('Terdeteksi menggunakan foto. Mohon gunakan wajah asli.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Coba Lagi'),
              ),
            ],
          ),
        );
        setState(() {
          _statusText = 'Terdeteksi menggunakan foto';
        });
        return;
      }

      if (similarity >= 0.75) {
        setState(() {
          _statusText = 'Wajah dikenali! ($similarityPercent%)';
        });
        await handleFaceMatch(similarity);
      } else {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Wajah Tidak Cocok'),
            content: Text('Similarity: $similarityPercent%'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Coba Lagi'),
              ),
            ],
          ),
        );
        setState(() {
          _statusText = 'Wajah tidak cocok ($similarityPercent%)';
        });
      }
    } catch (e) {
      print('Verification failed: $e');
    } finally {
      setState(() {
        _isVerifying = false;
      });
    }
  }

  Future<bool> _checkLiveness(File imageFile) async {
    try {
      // Read image and detect faces
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        return false;
      }

      final face = faces.first;
      double livenessScore = 0.0;

      // 1. Check for eye blink detection
      if (face.leftEyeOpenProbability != null && face.rightEyeOpenProbability != null) {
        final leftEyeOpen = face.leftEyeOpenProbability! > 0.5;
        final rightEyeOpen = face.rightEyeOpenProbability! > 0.5;
        if (!leftEyeOpen || !rightEyeOpen) {
          livenessScore += 0.3;
        }
      }

      // 2. Check face angle
      if (face.headEulerAngleY != null && face.headEulerAngleZ != null) {
        final yaw = face.headEulerAngleY!.abs();
        final roll = face.headEulerAngleZ!.abs();
        if (yaw > 5 || roll > 5) {
          livenessScore += 0.2;
        }
      }

      // 3. Check for face quality and natural features
      if (face.landmarks.isNotEmpty) {
        final requiredLandmarks = [
          FaceLandmarkType.leftEye,
          FaceLandmarkType.rightEye,
          FaceLandmarkType.noseBase,
          FaceLandmarkType.bottomMouth,
        ];

        bool allLandmarksPresent = true;
        for (var landmark in requiredLandmarks) {
          if (!face.landmarks.containsKey(landmark)) {
            allLandmarksPresent = false;
            break;
          }
        }

        if (allLandmarksPresent) {
          livenessScore += 0.3;
        }
      }

      // 4. Check for natural face contours
      if (face.contours.isNotEmpty) {
        final requiredContours = [
          FaceContourType.face,
          FaceContourType.leftEye,
          FaceContourType.rightEye,
          FaceContourType.noseBridge,
          FaceContourType.upperLipTop,
          FaceContourType.lowerLipBottom,
        ];

        bool allContoursPresent = true;
        for (var contour in requiredContours) {
          if (!face.contours.containsKey(contour) ||
              face.contours[contour]!.points.isEmpty) {
            allContoursPresent = false;
            break;
          }
        }

        if (allContoursPresent) {
          livenessScore += 0.2;
        }
      }

      // Calculate final liveness score
      return livenessScore >= 0.5;
    } catch (e) {
      print('Liveness check failed: $e');
      return false;
    }
  }

  Future<void> _captureAndVerify() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      final image = await _cameraController!.takePicture();
      await _verifyFace(File(image.path));
    } catch (e) {
      print('Capture failed: $e');
    }
  }

  // New function to check network connection against approved school networks
  Future<Map<String, dynamic>> _checkNetworkConnection() async {
    try {
      // For Windows, we would skip this check, but since we're already
      // preventing Windows from using this feature, this is just a safeguard
      if (_isWindows) {
        return {
          'status': 'wrong_platform',
          'message': 'Platform tidak didukung'
        };
      }

      // 1. Get the current network information
      String? wifiName = await _networkInfo.getWifiName();
      String? wifiBSSID = await _networkInfo.getWifiBSSID(); // This is the MAC address

      // Clean up the WiFi name (on some devices it includes quotes)
      if (wifiName != null) {
        wifiName = wifiName.replaceAll('"', '');
      }

      // 2. Query for approved networks with 'on' set to true
      final QuerySnapshot networkQuery = await FirebaseFirestore.instance
          .collection('jaringan')
          .where('on', isEqualTo: true)
          .get();

      // 3. Check if there are any approved networks
      if (networkQuery.docs.isEmpty) {
        return {
          'status': 'no_networks',
          'message': 'Jaringan sekolah sedang bermasalah. Segera pergi ke admin.'
        };
      }

      // 4. Check if current network matches any approved network
      bool isConnectedToApprovedNetwork = false;
      for (var doc in networkQuery.docs) {
        final networkData = doc.data() as Map<String, dynamic>;

        final String networkName = networkData['nama'] ?? '';
        final String networkMAC = networkData['ip'] ?? '';

        if ((wifiName != null && wifiName.contains(networkName)) &&
            (wifiBSSID != null && wifiBSSID == networkMAC)) {
          isConnectedToApprovedNetwork = true;
          break;
        }
      }

      if (isConnectedToApprovedNetwork) {
        return {
          'status': 'connected',
          'message': 'Anda berhasil absen'
        };
      } else {
        return {
          'status': 'wrong_network',
          'message': 'Anda tidak sedang berada di jaringan sekolah'
        };
      }
    } catch (e) {
      print('Network check error: $e');
      return {
        'status': 'error',
        'message': 'Gagal memeriksa jaringan: $e'
      };
    }
  }

  Future<void> requestPermissions() async {
    // Skip permission requests on Windows
    if (_isWindows) return;

    // Minta izin lokasi
    if (await Permission.location.isDenied) {
      await Permission.location.request();
    }

    // Cek apakah diizinkan
    if (await Permission.location.isPermanentlyDenied) {
      openAppSettings(); // arahkan ke pengaturan jika ditolak permanen
    }
  }

  Future<void> sendNotification(String title, String body) async {
    // Skip notifications on Windows
    if (_isWindows) return;

    try {
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
        'absensi_channel',
        'Absensi Notifications',
        channelDescription: 'Notifications for attendance system',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
      );

      const DarwinNotificationDetails iOSPlatformChannelSpecifics =
      DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
      );

      await _flutterLocalNotificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        body,
        platformChannelSpecifics,
      );

      print('Local notification sent successfully');
    } catch (e) {
      print('Error sending local notification: $e');
    }
  }

  Future<void> handleFaceMatch(double similarity) async {
    if (similarity < 0.75 || _user == null) return;

    // 🔒 Step 1: Get current device ID
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    String? currentDeviceId;

    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      currentDeviceId = androidInfo.id;
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      currentDeviceId = iosInfo.identifierForVendor;
    } else {
      // Windows case is already handled earlier, but as a safeguard:
      if (_isWindows) {
        _showInfoDialog('Platform tidak didukung');
        return;
      }
    }

    // 🔐 Step 2: Get device field from Firestore
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_user!.uid)
        .get();

    final registeredDeviceId = userDoc.data()?['device'];

    // 🔍 Step 3: Bandingkan device ID
    if (registeredDeviceId != currentDeviceId) {
      _showInfoDialog('Anda tidak dapat absen pada device yang bukan milik Anda.');
      return;
    }

    // ✅ Step 4: Jika device cocok, lanjut cek jaringan
    final networkStatus = await _checkNetworkConnection();

    if (networkStatus['status'] != 'connected') {
      _showInfoDialog(networkStatus['message']);
      return;
    }

    // 🕒 Step 5: Proses absen
    final uid = _user!.uid;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayString = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

    final QuerySnapshot absenQuery = await FirebaseFirestore.instance
        .collection('absen')
        .where('tanggal', isEqualTo: todayString)
        .where('user_id', isEqualTo: uid)
        .limit(1)
        .get();

    final nowTime = TimeOfDay.fromDateTime(DateTime.now());
    final formattedTime = "${nowTime.hour.toString().padLeft(2, '0')}:${nowTime.minute.toString().padLeft(2, '0')}";

    if (absenQuery.docs.isEmpty) {
      _showInfoDialog('Data absensi tidak ditemukan untuk hari ini. Silakan hubungi admin.');
      return;
    }

    final absenDoc = absenQuery.docs.first;
    final absenData = absenDoc.data() as Map<String, dynamic>;
    final absenRef = FirebaseFirestore.instance.collection('absen').doc(absenDoc.id);

    if (absenData['waktu_masuk'] == null || absenData['waktu_masuk'].isEmpty) {
      _showConfirmationDialog(
        title: 'Verifikasi Wajah Berhasil',
        message: 'Apakah Anda ingin melakukan absen masuk sekarang?',
        onConfirm: () async {
          try {
            await absenRef.update({
              'waktu_masuk': formattedTime,
              'keterangan': 'Sudah Masuk',
              'absen_masuk': '1'
            });
            await sendNotification(
              'Absen Masuk Berhasil',
              'Anda telah absen masuk pada pukul $formattedTime',
            );
            _showSuccessDialog(
              title: 'Absen Masuk Berhasil',
              message: 'Anda berhasil melakukan absen masuk pada pukul $formattedTime',
            );
          } catch (e) {
            _showInfoDialog('Gagal menyimpan absen masuk: $e');
          }
        },
      );
    } else if (absenData['waktu_pulang'] == null || absenData['waktu_pulang'].isEmpty) {
      _showConfirmationDialog(
        title: 'Verifikasi Wajah Berhasil',
        message: 'Apakah Anda ingin melakukan absen pulang sekarang?',
        onConfirm: () async {
          try {
            await absenRef.update({
              'waktu_pulang': formattedTime,
              'absen_pulang': '1'
            });
            await sendNotification(
              'Absen Pulang Berhasil',
              'Anda telah absen pulang pada pukul $formattedTime',
            );
            _showSuccessDialog(
              title: 'Absen Pulang Berhasil',
              message: 'Anda berhasil melakukan absen pulang pada pukul $formattedTime',
            );
          } catch (e) {
            _showInfoDialog('Gagal menyimpan absen pulang: $e');
          }
        },
      );
    } else {
      _showInfoDialog('Anda sudah melakukan absen masuk dan pulang hari ini.');
    }
  }

  void _showSuccessDialog({required String title, required String message}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showConfirmationDialog({
    required String title,
    required String message,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onConfirm();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Info'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _isBusy = true; // Prevent further processing
    _cameraController?.dispose();
    _faceDetector.close();
    if (_interpreter != null) {
      _interpreter!.close();
      _interpreter = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verifikasi Wajah'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Camera preview
                _isCameraInitialized
                    ? CameraPreview(_cameraController!)
                    : const Center(child: CircularProgressIndicator()),

                // Status text overlay
                Positioned(
                  bottom: 20,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.black54,
                    child: Text(
                      _statusText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Action buttons
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                ElevatedButton(
                  onPressed: _isFaceDetected && !_isVerifying
                      ? _captureAndVerify
                      : null,
                  child: const Text('Verifikasi Wajah'),
                ),

                const SizedBox(height: 20),

                Text(
                  'User ID: ${_user?.uid ?? 'Not logged in'}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}