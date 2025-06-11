import 'package:flutter/material.dart';
import 'package:ta/pages/login.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/firebase_options.dart';
import 'package:ta/services/auth_services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Background notification handler
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Handling a background message: ${message.messageId}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Register background handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  @override
  void initState() {
    super.initState();
    _setupFCM();
  }

  Future<void> _setupFCM() async {
    // ✅ Minta izin notifikasi (khusus iOS)
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('Notifikasi diizinkan');

      // ✅ Ambil token FCM
      String? token = await _firebaseMessaging.getToken();
      print("Token FCM: $token");

      // ⚠️ Simpan token ke Firestore saat login user atau di sini jika ingin langsung
    } else {
      print('Izin notifikasi ditolak');
    }

    // ✅ Listener notifikasi saat app di foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('🔔 Notifikasi saat aktif: ${message.notification?.title}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${message.notification?.title ?? 'Notifikasi'}: ${message.notification?.body ?? ''}',
          ),
        ),
      );
    });

    // ✅ Listener saat klik notifikasi
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('🔓 Notifikasi diklik: ${message.notification?.title}');
      // ➕ Arahkan ke halaman tertentu jika dibutuhkan
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => DataLogin()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: LoginPage(),
      ),
    );
  }
}
