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

class FacePage extends StatefulWidget {
  const FacePage({Key? key}) : super(key: key);

  @override
  State<FacePage> createState() => _FacePageState();
}

class _FacePageState extends State<FacePage> {
  // Camera controller
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isBusy = false;

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
  bool _isJustRegistered = false;

  // Result status
  String _statusText = 'Initializing...';
  List<double>? _registeredEmbedding;

  // Face detection results
  Face? _detectedFace;

  // Timer for frame capture
  DateTime? _lastCaptureTime;

  @override
  void initState() {
    super.initState();
    print('DEBUG: initState started');
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      print('DEBUG: Starting _initializeServices');

      // Get current user
      _user = FirebaseAuth.instance.currentUser;
      print('DEBUG: Current user: ${_user?.uid ?? "no user"}');

      if (_user == null) {
        print('DEBUG: No user logged in');
        setState(() {
          _statusText = 'No user logged in';
        });
        return;
      }

      // Initialize ML components in parallel for faster startup
      await Future.wait([
        _loadModel().then((_) {
          print('DEBUG: Model loaded successfully');
          setState(() {
            _isModelReady = true;
          });
        }),
        _checkUserEmbedding(),
        _initializeCamera(),
      ]);

      setState(() {
        _statusText = _hasEmbedding
            ? 'Mencari wajah untuk verifikasi...'
            : 'Mencari wajah untuk pendaftaran...';
      });

      print('DEBUG: _initializeServices completed');
    } catch (e) {
      print('ERROR: Initialization failed: $e');
      // setState(() {
      //   _statusText = 'Initialization error: $e';
      // });
    }
  }

  Future<void> _checkUserEmbedding() async {
    try {
      print('DEBUG: Checking embedding data in Firestore');
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .get();

      final hasEmbedding = doc.exists && doc.data()?['embedding'] != null;
      print('DEBUG: Embedding check result: ${hasEmbedding ? "Exists" : "Doesn\'t exist"}');

      // If mounted check before setState to avoid errors
      if (!mounted) return;

      setState(() {
        _hasEmbedding = hasEmbedding;
        _statusText = hasEmbedding
            ? 'Siap untuk verifikasi'
            : 'Ready for registration';

        if (hasEmbedding && doc.data() != null) {
          try {
            print('DEBUG: Reading embedding data from Firestore');
            // Convert stored embedding to list of doubles for comparison
            List<dynamic> rawEmbedding = doc.data()?['embedding'];
            if (rawEmbedding != null) {
              // Fix: Safely convert List<dynamic> to List<double>
              _registeredEmbedding = rawEmbedding.map((value) => value as double).toList();
              print('DEBUG: Stored embedding length: ${_registeredEmbedding?.length}');
            } else {
              print('DEBUG: Embedding data is null');
              _hasEmbedding = false;
              _statusText = 'Ready for registration';
            }
          } catch (e) {
            print('ERROR: Failed to process embedding data: $e');
            _hasEmbedding = false;
            _statusText = 'Error reading face data. Please register again.';
          }
        }
      });
    } catch (e) {
      print('ERROR: Failed to check user data: $e');
      if (mounted) {
        setState(() {
          // _statusText = 'Error checking user data: $e';
          _hasEmbedding = false; // Fallback to registration mode on error
        });
      }
    }
  }

  Future<void> _initializeCamera() async {
    print('DEBUG: Starting camera initialization');

    try {
      _cameras = await availableCameras();
      print('DEBUG: Number of cameras detected: ${_cameras?.length ?? 0}');

      if (_cameras == null || _cameras!.isEmpty) {
        print('ERROR: No cameras available');
        if (mounted) {
          setState(() {
            _statusText = 'No cameras available';
          });
        }
        return;
      }

      // Use front camera for face recognition
      print('DEBUG: Selecting front camera');
      final frontCamera = _cameras!.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );
      print('DEBUG: Selected camera: ${frontCamera.name}');

      print('DEBUG: Initializing camera controller');
      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium, // Lower resolution for better performance
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );

      print('DEBUG: Initializing camera controller...');
      await _cameraController!.initialize();
      print('DEBUG: Camera controller successfully initialized');

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
        print('DEBUG: Starting face detection');
        _startFaceDetection();
      }
    } catch (e) {
      print('ERROR: Camera initialization failed: $e');
      if (mounted) {
        // setState(() {
        //   _statusText = 'Camera error: $e';
        // });
      }
    }
  }

  Future<void> _loadModel() async {
    try {
      print('DEBUG: Starting TFLite model loading');

      // Close any existing interpreter
      if (_interpreter != null) {
        _interpreter!.close();
        _interpreter = null;
      }

      // Create more fault-tolerant interpreter options
      final options = InterpreterOptions()
        ..threads = 2
        ..useNnApiForAndroid = false; // Disable NNAPI for reliability

      // Load model with error handling
      try {
        _interpreter = await Interpreter.fromAsset(
            'lib/assets/models/facenet.tflite',
            options: options
        );

        print('DEBUG: Model loaded successfully');

        // Validate model input/output shapes
        final inputShape = _interpreter!.getInputTensor(0).shape;
        final outputShape = _interpreter!.getOutputTensor(0).shape;
        print('DEBUG: Model input shape: $inputShape');
        print('DEBUG: Model output shape: $outputShape');

        // Update input size based on model's actual requirements
        if (inputShape.length >= 3) {
          _inputSize = inputShape[1]; // Height dimension
          print('DEBUG: Using input size: $_inputSize');
        }

        return;
      } catch (e) {
        print('ERROR: Failed to load model from asset: $e');
        throw Exception('Model loading failed: $e');
      }
    } catch (e) {
      print('ERROR: Failed to load model: $e');
      if (mounted) {
        setState(() {
          _isModelReady = false;
          // _statusText = 'Error loading model: $e';
        });
      }
      throw e; // Re-throw to handle in _initializeServices
    }
  }

  void _startFaceDetection() {
    print('DEBUG: Starting _startFaceDetection function');
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      print('ERROR: Camera not ready for face detection');
      return;
    }

    _processFrame();
  }

  Future<void> _processFrame() async {
    if (_isBusy || !mounted || _cameraController == null || !_cameraController!.value.isInitialized) {
      // Schedule next frame if still mounted
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 500), _processFrame);
      }
      return;
    }

    _isBusy = true;

    try {
      // Limit capture frequency to avoid overwhelming the device
      final now = DateTime.now();
      if (_lastCaptureTime != null &&
          now.difference(_lastCaptureTime!).inMilliseconds < 500) {
        // Skip this frame if too soon after last capture
        _isBusy = false;
        if (mounted) {
          Future.delayed(const Duration(milliseconds: 500), _processFrame);
        }
        return;
      }

      _lastCaptureTime = now;

      // Take picture with lower resolution for better performance
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

          // Update status text for registration mode
          if (!_hasEmbedding) {
            _statusText = 'Wajah terdeteksi! Tekan "Daftarkan Wajah" untuk melanjutkan';
          }
        });
      } else {
        setState(() {
          _isFaceDetected = false;
          _detectedFace = null;
          _statusText = _hasEmbedding
              ? 'Mencari wajah untuk verifikasi...'
              : 'Mencari wajah untuk pendaftaran...';
        });
      }

      // Clean up the temporary image file
      try {
        await File(image.path).delete();
      } catch (e) {
        // Ignore file deletion errors
      }
    } catch (e) {
      print('ERROR: Frame processing error: $e');
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
      print('ERROR: Model not ready');
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
      print('ERROR in _generateEmbedding: $e');
      try {
        print('DEBUG: Trying alternative embedding generation approach');
        return _generateEmbeddingAlternative(imageFile);
      } catch (e2) {
        print('ERROR: Alternative embedding generation also failed: $e2');
        throw Exception('All embedding generation methods failed');
      }
    }
  }

  // Alternative approach for embedding generation
  Future<List<double>> _generateEmbeddingAlternative(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) throw Exception('Failed to decode image');

    final resized = img.copyResize(image, width: _inputSize, height: _inputSize);

    final inputTensor = List.generate(
      1,
          (_) => List.generate(
        _inputSize,
            (y) => List.generate(
          _inputSize,
              (x) {
            final pixel = resized.getPixel(x, y);
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
    final outputTensor = List.generate(1, (_) => List.filled(outputSize, 0.0));

    _interpreter!.run(inputTensor, outputTensor);

    final embedding = outputTensor[0];
    double sumSquared = embedding.fold(0.0, (sum, e) => sum + e * e);
    double norm = math.sqrt(math.max(sumSquared, 1e-10));
    return embedding.map((e) => e / norm).toList();
  }

  double _calculateSimilarity(List<double> embedding1, List<double> embedding2) {
    print('DEBUG: Calculating similarity between two embeddings');
    if (embedding1.length != embedding2.length) {
      print('ERROR: Embedding dimensions do not match: ${embedding1.length} vs ${embedding2.length}');
      throw Exception('Embedding dimensions do not match');
    }

    // Calculate cosine similarity
    double dotProduct = 0;
    for (int i = 0; i < embedding1.length; i++) {
      dotProduct += embedding1[i] * embedding2[i];
    }

    // Cosine similarity will be between -1 and 1
    // We clamp to [0,1] for face verification purposes
    double similarity = math.max(0.0, math.min(1.0, dotProduct));
    print('DEBUG: Similarity result: $similarity');
    return similarity;
  }

  Future<void> _registerFace(File imageFile) async {
    print('DEBUG: Starting _registerFace with file ${imageFile.path}');
    setState(() {
      _statusText = 'Mendaftarkan wajah...';
      _isProcessingImage = true;
    });

    try {
      print('DEBUG: Will generate face embedding');
      final embedding = await _generateEmbedding(imageFile);
      print('DEBUG: Embedding successfully created, length: ${embedding.length}');

      // Save embedding to Firestore
      print('DEBUG: Saving embedding to Firestore');
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .set({
        'embedding': embedding,
      }, SetOptions(merge: true));
      print('DEBUG: Embedding successfully saved to Firestore');

      setState(() {
        _hasEmbedding = true;
        _registeredEmbedding = embedding;
        _statusText = 'Wajah berhasil didaftarkan!';
      });

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Registrasi Berhasil'),
          content: const Text(
              'Data wajah Anda berhasil didaftarkan. Untuk melakukan absensi, tekan tombol "Verifikasi Wajah".'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      // Allow a moment to read the success message
      print('DEBUG: Waiting 2 seconds before changing status');
      await Future.delayed(const Duration(seconds: 2));

      setState(() {
        _statusText = 'Siap untuk verifikasi';
      });
    } catch (e) {
      print('ERROR: Registration failed: $e');
      setState(() {
        // _statusText = 'Registration error: $e';
      });
    } finally {
      setState(() {
        _isProcessingImage = false;
      });
      print('DEBUG: _registerFace completed');
    }
  }

  Future<void> _verifyFace(File imageFile) async {
    if (_isJustRegistered) {
      _isJustRegistered = false; // Reset flag
      print('DEBUG: Skipping first verification after registration');
      setState(() {
        _isVerifying = false;
        _statusText = 'Silakan tekan tombol Verifikasi Wajah untuk absensi';
      });
      return;
    }
    print('DEBUG: Starting _verifyFace with file ${imageFile.path}');
    if (_registeredEmbedding == null) {
      print('ERROR: No stored embedding data found');
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
      print('DEBUG: Will create face embedding for verification');
      final currentEmbedding = await _generateEmbedding(imageFile);
      print('DEBUG: Embedding successfully created, length: ${currentEmbedding.length}');

      print('DEBUG: Calculating similarity');
      final similarity = _calculateSimilarity(currentEmbedding, _registeredEmbedding!);
      final similarityPercent = (similarity * 100).toStringAsFixed(2);
      print('DEBUG: Similarity: $similarity');

      // Check for liveness
      final isLive = await _checkLiveness(imageFile);
      if (!isLive) {
        print('DEBUG: Liveness check failed');
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
        print('DEBUG: Verification successful');
        setState(() {
          _statusText = 'Wajah dikenali! ($similarityPercent%)';
        });
        await handleFaceMatch(similarity);
      } else {
        print('DEBUG: Verification failed');
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
      print('ERROR: Verification failed: $e');
      setState(() {
        // _statusText = 'Verification error: $e';
      });
    } finally {
      setState(() {
        _isVerifying = false;
      });
      print('DEBUG: _verifyFace completed');
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
          livenessScore += 0.3; // Eyes are partially closed
        }
      }

      // 2. Check face angle (should not be perfectly straight)
      if (face.headEulerAngleY != null && face.headEulerAngleZ != null) {
        final yaw = face.headEulerAngleY!.abs();
        final roll = face.headEulerAngleZ!.abs();
        if (yaw > 5 || roll > 5) {
          livenessScore += 0.2; // Face is slightly tilted
        }
      }

      // 3. Check for face quality and natural features
      if (face.landmarks.isNotEmpty) {
        // Check if all important landmarks are present
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

      // 5. Check for natural face expression
      if (face.smilingProbability != null) {
        final smileProb = face.smilingProbability!;
        if (smileProb > 0.1 && smileProb < 0.9) {
          livenessScore += 0.1; // Natural expression
        }
      }

      // Calculate final liveness score
      final isLive = livenessScore >= 0.6; // Threshold for liveness
      print('DEBUG: Liveness score: $livenessScore, Is live: $isLive');
      return isLive;

    } catch (e) {
      print('ERROR: Liveness check failed: $e');
      return false;
    }
  }

  Future<void> _captureAndRegister() async {
    print('DEBUG: Starting _captureAndRegister');
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      print('ERROR: Camera not ready for capturing');
      return;
    }

    try {
      print('DEBUG: Taking picture for registration');
      final image = await _cameraController!.takePicture();
      print('DEBUG: Picture successfully taken: ${image.path}');

      print('DEBUG: Will register face');
      await _registerFace(File(image.path));
    } catch (e) {
      print('ERROR: Capture failed: $e');
      setState(() {
        // _statusText = 'Capture error: $e';
      });
    }
    print('DEBUG: _captureAndRegister completed');
  }

  Future<void> _captureAndVerify() async {
    print('DEBUG: Starting _captureAndVerify');
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      print('ERROR: Camera not ready for capturing');
      return;
    }

    try {
      print('DEBUG: Taking picture for verification');
      final image = await _cameraController!.takePicture();
      print('DEBUG: Picture successfully taken: ${image.path}');

      print('DEBUG: Will verify face');
      await _verifyFace(File(image.path));
    } catch (e) {
      print('ERROR: Capture failed: $e');
      setState(() {
        // _statusText = 'Capture error: $e';
      });
    }
    print('DEBUG: _captureAndVerify completed');
  }

  Future<void> handleFaceMatch(double similarity) async {
    if (similarity < 0.75 || _user == null) return;

    final uid = _user!.uid;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayString = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

    // Query untuk mencari dokumen absen hari ini untuk user ini
    final QuerySnapshot absenQuery = await FirebaseFirestore.instance
        .collection('absen')
        .where('tanggal', isEqualTo: todayString)
        .where('user_id', isEqualTo: uid)
        .limit(1)
        .get();

    final nowTime = TimeOfDay.fromDateTime(DateTime.now());
    final formattedTime = "${nowTime.hour.toString().padLeft(2, '0')}:${nowTime.minute.toString().padLeft(2, '0')}";

    if (absenQuery.docs.isEmpty) {
      // Tidak menemukan dokumen, mungkin ada kesalahan
      _showInfoDialog('Data absensi tidak ditemukan untuk hari ini. Silakan hubungi admin.');
      return;
    }

    // Ambil dokumen absen yang ditemukan
    final absenDoc = absenQuery.docs.first;
    final absenData = absenDoc.data() as Map<String, dynamic>;
    final absenRef = FirebaseFirestore.instance.collection('absen').doc(absenDoc.id);

    if (absenData['waktu_masuk'] == null || absenData['waktu_masuk'].isEmpty) {
      _showConfirmationDialog(
        title: 'Wajah cocok',
        message: 'Apakah Anda ingin absen masuk?',
        onConfirm: () {
          absenRef.update({
            'waktu_masuk': formattedTime,
            'keterangan': 'Sudah Masuk',
            'absen_masuk': '1'
          });
        },
      );
    } else if (absenData['waktu_pulang'] == null || absenData['waktu_pulang'].isEmpty) {
      _showConfirmationDialog(
        title: 'Wajah cocok',
        message: 'Apakah Anda ingin absen pulang?',
        onConfirm: () {
          absenRef.update({
            'waktu_pulang': formattedTime,
            'absen_pulang': '1'
          });
        },
      );
    } else {
      _showInfoDialog('Anda sudah absen masuk dan pulang hari ini.');
    }
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


  Future<void> _resetFaceData() async {
    print('DEBUG: Starting _resetFaceData');
    try {
      print('DEBUG: Deleting embedding data from Firestore');
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .update({
        'embedding': FieldValue.delete(),
      });
      print('DEBUG: Embedding data successfully deleted');

      setState(() {
        _hasEmbedding = false;
        _registeredEmbedding = null;
        _statusText = 'Data wajah direset. Siap untuk pendaftaran.';
      });
    } catch (e) {
      print('ERROR: Data reset failed: $e');
      setState(() {
        // _statusText = 'Error resetting face data: $e';
      });
    }
    print('DEBUG: _resetFaceData completed');
  }

  @override
  void dispose() {
    print('DEBUG: dispose called, cleaning up resources');
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
        title: Text(_hasEmbedding ? 'Verifikasi Wajah' : 'Registrasi Wajah'),
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

                // Face detection overlay
                // if (_isFaceDetected && _detectedFace != null)
                //   CustomPaint(
                //     painter: FaceOverlayPainter(_detectedFace!),
                //   ),

                // Status text overlay
                Positioned(
                  bottom: 20,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.black54,
                    // child: Text(
                    //   _statusText,
                    //   textAlign: TextAlign.center,
                    //   style: const TextStyle(
                    //     color: Colors.white,
                    //     fontSize: 16,
                    //   ),
                    // ),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    if (!_hasEmbedding)
                      ElevatedButton(
                        onPressed: _isFaceDetected && !_isProcessingImage
                            ? () {
                          print('DEBUG: Register Face button pressed');
                          _captureAndRegister();
                        }
                            : null,
                        child: const Text('Daftarkan Wajah'),
                      )
                    else
                      ElevatedButton(
                        onPressed: _isFaceDetected && !_isVerifying
                            ? () {
                          print('DEBUG: Verify Face button pressed');
                          _captureAndVerify();
                        }
                            : null,
                        child: const Text('Verifikasi Wajah'),
                      ),

                    // ElevatedButton(
                    //   onPressed: _hasEmbedding ? () {
                    //     print('DEBUG: Reset Face Data button pressed');
                    //     _resetFaceData();
                    //   } : null,
                    //   style: ElevatedButton.styleFrom(
                    //     backgroundColor: Colors.red,
                    //   ),
                    //   child: const Text('Reset Face Data'),
                    // ),
                  ],
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

// Painter for face overlay
class FaceOverlayPainter extends CustomPainter {
  final Face face;

  FaceOverlayPainter(this.face);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.green;

    // Draw face bounding box with improved coordinate conversion
    final rect = face.boundingBox;

    // Calculate scaling factors
    final double scaleX = size.width / rect.right;
    final double scaleY = size.height / rect.bottom;
    final double scale = math.min(scaleX, scaleY);

    // Calculate display offset to center the face in the view
    final double offsetX = (size.width - (rect.width * scale)) / 2;
    final double offsetY = (size.height - (rect.height * scale)) / 2;

    // Draw properly transformed bounding box
    final Rect displayRect = Rect.fromLTWH(
      rect.left * scale + offsetX,
      rect.top * scale + offsetY,
      rect.width * scale,
      rect.height * scale,
    );

    canvas.drawRect(displayRect, paint);
  }

  @override
  bool shouldRepaint(FaceOverlayPainter oldDelegate) {
    return oldDelegate.face != face;
  }
}

// Advanced face detection helper functions
class FaceDetectionUtils {
  // Calculate face quality score based on various factors
  static double calculateFaceQuality(Face face, Size imageSize) {
    double score = 1.0;

    // Check face size relative to image
    final faceArea = face.boundingBox.width * face.boundingBox.height;
    final imageArea = imageSize.width * imageSize.height;
    final faceRatio = faceArea / imageArea;

    // Penalize if face is too small or too large
    if (faceRatio < 0.05) {
      score *= 0.5; // Face too small
    } else if (faceRatio > 0.9) {
      score *= 0.7; // Face too large (likely too close)
    }

    // Check if face is centered
    final faceCenter = Offset(
      face.boundingBox.left + face.boundingBox.width / 2,
      face.boundingBox.top + face.boundingBox.height / 2,
    );
    final imageCenter = Offset(imageSize.width / 2, imageSize.height / 2);
    final distance = (faceCenter - imageCenter).distance;
    final maxDistance = math.sqrt(imageSize.width * imageSize.width + imageSize.height * imageSize.height) / 2;
    final distanceRatio = distance / maxDistance;

    // Penalize if face is not centered
    if (distanceRatio > 0.5) {
      score *= (1 - distanceRatio * 0.5);
    }

    // Check face rotation if landmarks are available
    if (face.landmarks.isNotEmpty) {
      // Calculate head pose factors
      if (face.headEulerAngleY != null) {
        final absYaw = face.headEulerAngleY!.abs();
        if (absYaw > 15) {
          score *= (1 - (absYaw - 15) / 45); // Penalize yaw > 15 degrees
        }
      }

      if (face.headEulerAngleZ != null) {
        final absRoll = face.headEulerAngleZ!.abs();
        if (absRoll > 15) {
          score *= (1 - (absRoll - 15) / 45); // Penalize roll > 15 degrees
        }
      }
    }

    // Additional checks based on face contours
    if (face.contours.isNotEmpty) {
      // Check if all contours are present (good quality detection)
      bool missingKeyContours = false;

      final keyContours = [
        FaceContourType.face,
        FaceContourType.leftEye,
        FaceContourType.rightEye,
        FaceContourType.leftEyebrowTop,
        FaceContourType.rightEyebrowTop,
        FaceContourType.noseBridge,
        FaceContourType.upperLipTop,
        FaceContourType.lowerLipBottom
      ];

      for (var contour in keyContours) {
        if (face.contours[contour] == null || face.contours[contour]!.points.isEmpty) {
          missingKeyContours = true;
          break;
        }
      }

      if (missingKeyContours) {
        score *= 0.7; // Penalize for missing facial features
      }
    }

    // Bonus for smiling (if classification available and confidence high)
    if (face.smilingProbability != null && face.smilingProbability! > 0.7) {
      score = math.min(1.0, score * 1.1); // Small bonus for smiling
    }

    return math.max(0.0, math.min(1.0, score)); // Ensure score is between 0 and 1
  }

  // Get cropped face image from the full image
  static Future<img.Image?> cropFaceFromImage(img.Image fullImage, Face face, {double padding = 0.2}) async {
    try {
      // Calculate bounding box with padding
      final width = face.boundingBox.width;
      final height = face.boundingBox.height;
      final paddingX = width * padding;
      final paddingY = height * padding;

      // Calculate crop rectangle with boundaries check
      int left = math.max(0, (face.boundingBox.left - paddingX).round());
      int top = math.max(0, (face.boundingBox.top - paddingY).round());
      int right = math.min(fullImage.width, (face.boundingBox.right + paddingX).round());
      int bottom = math.min(fullImage.height, (face.boundingBox.bottom + paddingY).round());

      // Ensure valid dimensions
      if (right <= left || bottom <= top) {
        throw Exception('Invalid crop dimensions');
      }

      // Crop image
      return img.copyCrop(
          fullImage,
          x: left,
          y: top,
          width: right - left,
          height: bottom - top
      );
    } catch (e) {
      print('ERROR: Failed to crop face from image: $e');
      return null;
    }
  }

  // Process face image for optimal recognition (align, normalize)
  static Future<img.Image?> processFaceImage(img.Image faceImage, Face face, int targetSize) async {
    try {
      // If we have eye landmarks, perform face alignment
      if (face.landmarks.containsKey(FaceLandmarkType.leftEye) &&
          face.landmarks.containsKey(FaceLandmarkType.rightEye)) {

        // Get eye positions relative to cropped image bounds
        final leftEye = face.landmarks[FaceLandmarkType.leftEye]!.position;
        final rightEye = face.landmarks[FaceLandmarkType.rightEye]!.position;

        // Calculate angle for alignment
        final deltaY = rightEye.y - leftEye.y;
        final deltaX = rightEye.x - leftEye.x;
        double angle = math.atan2(deltaY, deltaX) * 180 / math.pi;

        // Rotate to align eyes horizontally
        final rotated = img.copyRotate(faceImage, angle: -angle);

        // Resize to target dimensions
        return img.copyResize(rotated, width: targetSize, height: targetSize);
      } else {
        // Simple resize if no landmarks for alignment
        return img.copyResize(faceImage, width: targetSize, height: targetSize);
      }
    } catch (e) {
      print('ERROR: Failed to process face image: $e');
      return img.copyResize(faceImage, width: targetSize, height: targetSize);
    }
  }

  // Get enhanced face image for better feature extraction
  static img.Image enhanceFaceImage(img.Image input) {
    try {
      // Convert to grayscale for processing
      final grayscale = img.grayscale(input);

      // Apply contrast enhancement manually since image package doesn't have histogramEqualization
      return _enhanceContrast(input);
    } catch (e) {
      print('ERROR: Failed to enhance face image: $e');
      return input; // Return original on error
    }
  }

  // Manual contrast enhancement as alternative to histogram equalization
  static img.Image _enhanceContrast(img.Image input) {
    // Create a copy of the image to modify
    img.Image output = img.Image.from(input);

    // Find min and max values for each channel
    int minR = 255, minG = 255, minB = 255;
    int maxR = 0, maxG = 0, maxB = 0;

    // First pass - find min/max values
    for (int y = 0; y < input.height; y++) {
      for (int x = 0; x < input.width; x++) {
        final pixel = input.getPixel(x, y);

        // Update min/max for each channel - convert num to int
        minR = math.min(minR, pixel.r.toInt());
        minG = math.min(minG, pixel.g.toInt());
        minB = math.min(minB, pixel.b.toInt());

        maxR = math.max(maxR, pixel.r.toInt());
        maxG = math.max(maxG, pixel.g.toInt());
        maxB = math.max(maxB, pixel.b.toInt());
      }
    }

    // Avoid division by zero
    int rangeR = maxR - minR != 0 ? maxR - minR : 1;
    int rangeG = maxG - minG != 0 ? maxG - minG : 1;
    int rangeB = maxB - minB != 0 ? maxB - minB : 1;

    // Second pass - apply contrast stretching
    for (int y = 0; y < input.height; y++) {
      for (int x = 0; x < input.width; x++) {
        final pixel = input.getPixel(x, y);

        // Apply linear contrast stretching to each channel
        // Convert num to int before arithmetic operations
        int newR = (((pixel.r.toInt() - minR) * 255) ~/ rangeR).clamp(0, 255);
        int newG = (((pixel.g.toInt() - minG) * 255) ~/ rangeG).clamp(0, 255);
        int newB = (((pixel.b.toInt() - minB) * 255) ~/ rangeB).clamp(0, 255);

        // Set the new pixel with explicit integer values
        output.setPixel(x, y, img.ColorRgb8(newR, newG, newB));
      }
    }

    return output;
  }
}