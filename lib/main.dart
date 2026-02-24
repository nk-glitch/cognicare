import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'package:cognicare/services/auth_service.dart';
import 'package:cognicare/screens/auth/login_page.dart';
import 'package:cognicare/screens/auth/account_setup_page.dart';
import 'package:cognicare/screens/patient/patient_home_page.dart';
import 'package:cognicare/screens/caretaker/caretaker_home_page.dart';
import 'package:cognicare/screens/watch/watch_patient_screen.dart';
import 'package:cognicare/screens/watch/watch_login_page.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/notification_service.dart';
import 'package:wear_plus/wear_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await NotificationService.initialize();

  runApp(const CogniCareApp());
}

class CogniCareApp extends StatelessWidget {
  const CogniCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CogniCare',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.brown,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        textTheme: const TextTheme(
          displayLarge: TextStyle(decoration: TextDecoration.none),
          displayMedium: TextStyle(decoration: TextDecoration.none),
          displaySmall: TextStyle(decoration: TextDecoration.none),
          headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, decoration: TextDecoration.none),
          headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, decoration: TextDecoration.none),
          headlineSmall: TextStyle(decoration: TextDecoration.none),
          titleLarge: TextStyle(decoration: TextDecoration.none),
          titleMedium: TextStyle(decoration: TextDecoration.none),
          titleSmall: TextStyle(decoration: TextDecoration.none),
          bodyLarge: TextStyle(fontSize: 20, decoration: TextDecoration.none),
          bodyMedium: TextStyle(fontSize: 18, decoration: TextDecoration.none),
          bodySmall: TextStyle(decoration: TextDecoration.none),
          labelLarge: TextStyle(decoration: TextDecoration.none),
          labelMedium: TextStyle(decoration: TextDecoration.none),
          labelSmall: TextStyle(decoration: TextDecoration.none),
        ),
      ),
      home: const AppEntry(),
    );
  }
}

class AppEntry extends StatelessWidget {
  const AppEntry({super.key});

  @override
  Widget build(BuildContext context) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final isWatch = shortestSide < 300;

    if (isWatch) {
      return AmbientMode(
        builder: (context, mode, _) {
          if (mode == WearMode.ambient) return const _WatchAmbientFace();
          return const _WatchActiveFace();
        },
      );
    }

    return const AuthWrapper();
  }
}

class _WatchActiveFace extends StatelessWidget {
  const _WatchActiveFace();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFFF5E6D3),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) return WatchLoginPage();

        // ✅ Pass the UID directly — no more internal auth lookup in the screen
        return WatchPatientScreen(patientId: user.uid);
      },
    );
  }
}

class _WatchAmbientFace extends StatelessWidget {
  const _WatchAmbientFace();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text(
          'CogniCare',
          style: TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final AuthService _authService = AuthService();
  Future<Map<String, dynamic>>? _authFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _authFuture = _authService.checkAuthStatus();
      });
    });
  }

  Future<void> _setupPatientNotifications() async {
    await NotificationService.saveFCMToken();
  }

  @override
  Widget build(BuildContext context) {
    if (_authFuture == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F5F5),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: _authFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFFF5F5F5),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final authStatus = snapshot.data ?? {'isLoggedIn': false};

        if (!authStatus['isLoggedIn']) {
          return const LoginPage();
        }

        final userType = authStatus['userType'];
        final setupComplete = authStatus['setupComplete'];
        final uid = authStatus['uid'];

        if (userType == 'patient') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _setupPatientNotifications();
          });
        }

        if (userType == 'patient') {
          return setupComplete
              ? const PatientHomePage()
              : AccountSetupPage(userId: uid);
        } else {
          return const CaretakerHomePage();
        }
      },
    );
  }
}