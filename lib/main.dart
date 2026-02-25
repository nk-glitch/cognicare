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

// ── Watch active face ─────────────────────────────────────────────────────────
//
// The StreamBuilder gives us the Firebase Auth user, but we ALSO need to check
// userType in Firestore before routing — otherwise a caretaker who signs in
// will reach WatchPatientScreen before the login page's signOut() fires.
//
// We use a FutureBuilder nested inside the StreamBuilder so that every time the
// auth state changes (sign-in or sign-out) we re-fetch the role from Firestore.

class _WatchActiveFace extends StatelessWidget {
  const _WatchActiveFace();

  Future<String?> _fetchUserType(String uid) async {
    try {
      final authService = AuthService();
      final data = await authService.getUserData(uid);
      return (data?['userType'] as String? ?? '').trim();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        // Still connecting — show a neutral loader
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const _WatchLoader();
        }

        final user = authSnap.data;

        // Not signed in → login page
        if (user == null) return const WatchLoginPage();

        // Signed in — now verify the role before granting access
        return FutureBuilder<String?>(
          future: _fetchUserType(user.uid),
          builder: (context, roleSnap) {
            // Still fetching role — show loader
            if (roleSnap.connectionState == ConnectionState.waiting) {
              return const _WatchLoader();
            }

            final userType = roleSnap.data ?? '';

            // Caretaker account — show rejection screen; it signs out on swipe
            if (userType == 'caretaker') {
              return const _WatchCaretakerRejection();
            }

            // Patient (or empty/unknown type — fail safe to patient screen)
            return WatchPatientScreen(patientId: user.uid);
          },
        );
      },
    );
  }
}

// ── Small helper widgets ──────────────────────────────────────────────────────

class _WatchLoader extends StatelessWidget {
  const _WatchLoader();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF5E6D3),
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

/// Displayed when a caretaker tries to log in on the watch.
/// Stays visible until the user swipes it away, then signs out.
class _WatchCaretakerRejection extends StatefulWidget {
  const _WatchCaretakerRejection();

  @override
  State<_WatchCaretakerRejection> createState() =>
      _WatchCaretakerRejectionState();
}

class _WatchCaretakerRejectionState extends State<_WatchCaretakerRejection> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    await FirebaseAuth.instance.signOut();
    // Auth stream in _WatchActiveFace will detect null and show login page.
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Any horizontal or vertical swipe dismisses the screen
      onHorizontalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0).abs() > 80) _signOut();
      },
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0).abs() > 80) _signOut();
      },
      child: LayoutBuilder(
        builder: (context, bc) {
          final diameter = bc.maxWidth;
          return ClipOval(
            child: Container(
              width: diameter,
              height: diameter,
              color: const Color(0xFFF5E6D3),
              child: _signingOut
                  ? const Center(child: CircularProgressIndicator(
                  color: Color(0xFFE8736C), strokeWidth: 2))
                  : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8736C).withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.watch_off_rounded,
                        color: Color(0xFFE8736C), size: 22),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Patients only',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF3D2C31),
                      decoration: TextDecoration.none,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 5),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Sorry, this app is only usable for patients!',
                      style: TextStyle(
                        fontSize: 9,
                        color: Color(0xFF7A6060),
                        height: 1.4,
                        decoration: TextDecoration.none,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Swipe hint
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.swipe,
                          size: 10, color: Color(0xFFA08080)),
                      const SizedBox(width: 3),
                      const Text(
                        'swipe to dismiss',
                        style: TextStyle(
                          fontSize: 8,
                          color: Color(0xFFA08080),
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Watch ambient face ────────────────────────────────────────────────────────

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

// ── Phone auth wrapper ────────────────────────────────────────────────────────

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