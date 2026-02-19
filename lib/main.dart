import 'package:flutter/material.dart';
import './services/auth_service.dart';
import './screens/auth/login_page.dart';
import './screens/patient/patient_home_page.dart';
import './screens/caretaker/caretaker_home_page.dart';
import './screens/auth/account_setup_page.dart';
import 'firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
      home: const AuthWrapper(),
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
    // Defer auth check to after first frame so startup doesn't overload main thread
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _authFuture = _authService.checkAuthStatus();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // Show loading until we've started the auth check
    if (_authFuture == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5E6D3),
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: _authFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFFF5E6D3),
            body: Center(
              child: CircularProgressIndicator(),
            ),
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
          if (setupComplete) {
            return const PatientHomePage();
          } else {
            return AccountSetupPage(userId: uid);
          }
        } else {
          return const CaretakerHomePage();
        }
      },
    );
  }
}