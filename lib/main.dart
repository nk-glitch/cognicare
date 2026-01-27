import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'screens/auth/login_page.dart';
import 'screens/auth/account_setup_page.dart';
import 'screens/patient/patient_home_page.dart';
import 'screens/caretaker/caretaker_home_page.dart';

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
      title: 'CogniCare',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.brown,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        textTheme: const TextTheme(
          headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          bodyLarge: TextStyle(fontSize: 20),
          bodyMedium: TextStyle(fontSize: 18),
        ),
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    return FutureBuilder<Map<String, dynamic>>(
      future: authService.checkAuthStatus(),
      builder: (context, snapshot) {
        // Show loading while checking auth
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFFF5E6D3),
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // Check if user is logged in
        final authStatus = snapshot.data ?? {'isLoggedIn': false};

        if (!authStatus['isLoggedIn']) {
          return const LoginPage();
        }

        // User is logged in - route based on type and setup status
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