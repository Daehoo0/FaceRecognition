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
import 'package:path_provider/path_provider.dart';
import 'package:ta/pages/admin/registrasi.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;

class FaceAbsensiPage extends StatefulWidget {
  final String userId;
  const FaceAbsensiPage({Key? key, required this.userId}) : super(key: key);

  @override
  State<FaceAbsensiPage> createState() => _FacePageState();
}

class _FacePageState extends State<FaceAbsensiPage> {
  // Camera controller
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isBusy = false;
  // Tambahkan setelah deklarasi variabel lainnya
  bool get isMobilePlatform {
    if (kIsWeb) return false;
    if (Platform.isWindows) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  // Face detection
  late FaceDetector _faceDetector;
  bool _isFaceDetectorReady = false;

  // TFLite model
  Interpreter? _interpreter;
  bool _isModelReady = false;
  int _inputSize = 160; // FaceNet typically uses 160x160 input

  // User information
  User? _user;
  bool _isProcessingImage = false;
  bool _isFaceDetected = false;

  // Result status
  String _statusText = 'Initializing...';

  // Face detection results
  Face? _detectedFace;

  // Timer for frame capture
  DateTime? _lastCaptureTime;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      // Initialize face detector
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableContours: true,
          enableClassification: true,
          enableTracking: true,
          performanceMode: FaceDetectorMode.accurate,
          minFaceSize: 0.15,
        ),
      );
      _isFaceDetectorReady = true;

      // Get current user
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();

      if (userDoc.exists) {
        final email = userDoc['email'];
        _user = FirebaseAuth.instance.currentUser;
      }

      if (_user == null) {
        setState(() {
          _statusText = 'No user logged in';
        });
        return;
      }

      // Initialize ML components - tambahkan pengecekan platform
      if (isMobilePlatform) {
        await _loadModel();
      } else {
        setState(() {
          _isModelReady = false;
          _statusText = 'Platform ini tidak mendukung TensorFlow';
        });
      }
      await _initializeCamera();

      setState(() {
        _statusText = isMobilePlatform
            ? 'Mencari wajah untuk pendaftaran...'
            : 'Platform tidak mendukung fitur AI';
      });
    } catch (e) {
      print('Initialization failed: $e');
      setState(() {
        _statusText = 'Initialization failed: ${e.toString()}';
      });
    }
  }

  Future<void> _initializeCamera() async {
    try {
      // Check if platform supports camera
      if (!Platform.isAndroid && !Platform.isIOS && !Platform.isWindows) {
        setState(() {
          _statusText = 'Camera not supported on this platform';
        });
        return;
      }

      _cameras = await availableCameras();

      if (_cameras == null || _cameras!.isEmpty) {
        setState(() {
          _statusText = 'No cameras available';
        });
        return;
      }

      // Use front camera for face recognition
      CameraDescription? frontCamera;
      try {
        frontCamera = _cameras!.firstWhere(
              (camera) => camera.lensDirection == CameraLensDirection.front,
        );
      } catch (e) {
        frontCamera = _cameras!.first;
      }

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();

      // Set exposure and focus modes
      if (_cameraController!.value.exposureMode != ExposureMode.auto) {
        await _cameraController!.setExposureMode(ExposureMode.auto);
      }

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
      print('Camera initialization failed: $e');
      setState(() {
        _statusText = 'Camera initialization failed: ${e.toString()}';
      });
    }
  }

  Future<void> _loadModel() async {
    // Tambahkan pengecekan platform di awal
    if (!isMobilePlatform) {
      print("TensorFlow dinonaktifkan untuk platform ini");
      setState(() {
        _isModelReady = false;
      });
      return;
    }
    try {
      // Close any existing interpreter
      if (_interpreter != null) {
        _interpreter!.close();
        _interpreter = null;
      }

      final options = InterpreterOptions()
        ..threads = 2
        ..useNnApiForAndroid = Platform.isAndroid;

      _interpreter = await Interpreter.fromAsset(
        'lib/assets/models/facenet.tflite',
        options: options,
      );

      // Update input size based on model's requirements
      final inputShape = _interpreter!.getInputTensor(0).shape;
      if (inputShape.length >= 3) {
        _inputSize = inputShape[1];
      }

      setState(() {
        _isModelReady = true;
      });
    } catch (e) {
      print('Failed to load model: $e');
      setState(() {
        _isModelReady = false;
        _statusText = 'Failed to load model: ${e.toString()}';
      });
    }
  }

  void _startFaceDetection() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    _processFrame();
  }

  Future<void> _processFrame() async {
    if (_isBusy || !mounted ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized ||
        !_isFaceDetectorReady) {
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 500), _processFrame);
      }
      return;
    }

    _isBusy = true;

    try {
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

      final image = await _cameraController!.takePicture();
      final inputImage = InputImage.fromFilePath(image.path);
      final faces = await _faceDetector.processImage(inputImage);

      if (!mounted) return;

      if (faces.isNotEmpty) {
        // Use the largest face
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
          _statusText = 'Wajah terdeteksi! Tekan "Daftarkan Wajah" untuk melanjutkan';
        });
      } else {
        setState(() {
          _isFaceDetected = false;
          _detectedFace = null;
          _statusText = 'Mencari wajah untuk pendaftaran...';
        });
      }

      try {
        await File(image.path).delete();
      } catch (e) {
        print('Error deleting temp image: $e');
      }
    } catch (e) {
      print('Frame processing error: $e');
    } finally {
      _isBusy = false;

      if (mounted) {
        Future.delayed(const Duration(milliseconds: 500), _processFrame);
      }
    }
  }

  Future<List<double>> _generateEmbedding(File imageFile) async {
    // Tambahkan pengecekan ini di awal
    if (!isMobilePlatform || _interpreter == null) {
      throw Exception('TensorFlow tidak tersedia di platform ini');
    }
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
      throw Exception('Embedding generation failed: ${e.toString()}');
    }
  }

  Future<bool> _isFaceAlreadyRegistered(List<double> newEmbedding) async {
    try {
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('embedding', isNotEqualTo: null)
          .get();

      for (var doc in usersSnapshot.docs) {
        if (doc.id == widget.userId) continue; // Skip current user

        final existingEmbedding = List<double>.from(doc['embedding'] as List);
        if (existingEmbedding.isEmpty) continue;

        // Calculate cosine similarity
        double similarity = 0.0;
        for (int i = 0; i < newEmbedding.length; i++) {
          similarity += newEmbedding[i] * existingEmbedding[i];
        }

        // Threshold for face matching (adjust as needed)
        if (similarity > 0.5) {
          return true;
        }
      }
      return false;
    } catch (e) {
      print('Error checking existing embeddings: $e');
      return false;
    }
  }

  Future<bool> _registerFace(File imageFile) async {
    // Tambahkan pengecekan di awal
    if (!isMobilePlatform) {
      setState(() {
        _statusText = 'Fitur registrasi wajah tidak tersedia di platform ini';
      });
      return false;
    }

    setState(() {
      _statusText = 'Mendaftarkan wajah...';
      _isProcessingImage = true;
    });

    try {
      final embedding = await _generateEmbedding(imageFile);

      // Check if face is already registered
      bool isAlreadyRegistered = await _isFaceAlreadyRegistered(embedding);
      if (isAlreadyRegistered) {
        setState(() {
          _statusText = 'Wajah sudah terdaftar oleh pengguna lain';
        });

        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Registrasi Gagal'),
            content: const Text('Wajah sudah terpakai. Tidak dapat melakukan registrasi dengan wajah ini.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return false;
      }

      // Save embedding to Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .set({
        'embedding': embedding,
        'hasFaceRegistered': true,
      }, SetOptions(merge: true));

      setState(() {
        _statusText = 'Wajah berhasil didaftarkan!';
      });

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Registrasi Berhasil'),
          content: const Text('Data wajah Anda berhasil didaftarkan.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DaftarUserRegisFacePage(),
                  ),
                );
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );

      return true;
    } catch (e) {
      print('Registration failed: $e');
      setState(() {
        _statusText = 'Gagal mendaftarkan wajah. Silakan coba lagi.';
      });
      return false;
    } finally {
      setState(() {
        _isProcessingImage = false;
      });
    }
  }

  Future<void> _captureAndRegister() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        !_isFaceDetected) {
      return;
    }

    try {
      final image = await _cameraController!.takePicture();
      await _registerFace(File(image.path));
    } catch (e) {
      print('Capture failed: $e');
      setState(() {
        _statusText = 'Gagal mengambil gambar. Silakan coba lagi.';
      });
    }
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
        title: const Text('Registrasi Wajah'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Camera preview or placeholder
                if (_isCameraInitialized)
                  CameraPreview(_cameraController!)
                else
                  Container(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.camera_alt, size: 64, color: Colors.white),
                          const SizedBox(height: 16),
                          Text(
                            _statusText,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),

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
                  onPressed: _isFaceDetected && !_isProcessingImage
                      ? _captureAndRegister
                      : null,
                  child: _isProcessingImage
                      ? const CircularProgressIndicator()
                      : const Text('Daftarkan Wajah'),
                ),

                const SizedBox(height: 20),

                Text(
                  'User ID: ${_user?.uid ?? widget.userId}',
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