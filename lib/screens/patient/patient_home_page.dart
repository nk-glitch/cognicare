import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../../services/auth_service.dart';
import '../../services/location_service.dart';
import '../../services/notification_service.dart';
import '../profile_page.dart';
import '../auth/login_page.dart';
import '../inbox_page.dart';

class PatientHomePage extends StatefulWidget {
  const PatientHomePage({super.key});

  @override
  State<PatientHomePage> createState() => _PatientHomePageState();
}

class _PatientHomePageState extends State<PatientHomePage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocationService _locationService = LocationService();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  Timer? _reminderCheckTimer;
  Timer? _locationUpdateTimer;
  Timer? _clockTimer;

  String patientName = "";
  String patientFirstName = "";
  String caretakerName = "";
  String caretakerPhone = "";
  String currentLocation = "";
  List<Map<String, dynamic>> reminders = [];
  bool _isLoading = true;
  bool _isSharingLocation = false;
  bool _locationShared = false;

  DateTime _now = DateTime.now();

  final Set<String> _shownReminderDialogs = {};
  int _pendingRequestCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);

    // Update clock every minute
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    NotificationService.onNotificationTap = (data) => _showReminderDialog(data);
    _startReminderCheckTimer();
    _loadPatientData();
    _listenForPendingRequests();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _checkForPendingReminders();
      });
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) _shareLocationInBackground();
      });
      _locationUpdateTimer = Timer.periodic(const Duration(minutes: 5), (_) {
        if (mounted) _shareLocationInBackground();
      });
    });
  }

  void _listenForPendingRequests() {
    final user = _authService.currentUser;
    if (user == null) return;
    _firestore
        .collection('patient_caretaker_relationships')
        .where('patientId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      setState(() => _pendingRequestCount = snapshot.docs.length);
    });
  }

  void _startReminderCheckTimer() {
    _reminderCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _checkForPendingReminders();
    });
  }

  void _startLocationUpdateTimer() {
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted) _shareLocationInBackground();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      setState(() => _now = DateTime.now());
      _checkForPendingReminders();
      if (_reminderCheckTimer == null || !_reminderCheckTimer!.isActive) {
        _startReminderCheckTimer();
      }
      if (_locationUpdateTimer == null || !_locationUpdateTimer!.isActive) {
        _startLocationUpdateTimer();
      }
      _shareLocationInBackground();
    } else if (state == AppLifecycleState.paused) {
      _reminderCheckTimer?.cancel();
    }
  }

  Future<void> _checkForPendingReminders() async {
    try {
      final user = _authService.currentUser;
      if (user == null) return;
      final snapshot = await _firestore
          .collection('reminders')
          .where('patientId', isEqualTo: user.uid)
          .where('completed', isEqualTo: false)
          .where('time', isLessThanOrEqualTo: Timestamp.now())
          .orderBy('time')
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final reminder = doc.data();
        final time = (reminder['time'] as Timestamp).toDate();
        _showReminderDialog({
          'reminderId': doc.id,
          'title': reminder['title'] ?? 'Reminder',
          'description': reminder['description'] ?? '',
          'time': DateFormat('h:mm a').format(time),
        });
      }
    } catch (e) {
      debugPrint('Error checking pending reminders: $e');
    }
  }

  void _showReminderDialog(Map<String, dynamic> reminderData) {
    final reminderId = reminderData['reminderId'] ?? '';
    if (reminderId.isNotEmpty && _shownReminderDialogs.contains(reminderId)) return;
    if (reminderId.isNotEmpty) _shownReminderDialogs.add(reminderId);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReminderDialog(
        title: reminderData['title'] ?? 'Reminder',
        description: reminderData['description'] ?? '',
        time: reminderData['time'] ?? '',
        reminderId: reminderId,
      ),
    ).then((_) => _shownReminderDialogs.remove(reminderId));
  }

  Future<void> _shareLocationInBackground() async {
    try {
      final user = _authService.currentUser;
      if (user != null) {
        final ok = await _locationService.shareLocation(user.uid);
        if (mounted && ok) setState(() => _locationShared = true);
      }
    } catch (e) {
      debugPrint('Location share error (non-fatal): $e');
    }
  }

  Future<void> _onShareLocationTap() async {
    final user = _authService.currentUser;
    if (user == null || _isSharingLocation) return;
    setState(() => _isSharingLocation = true);
    try {
      final ok = await _locationService.shareLocation(user.uid);
      if (mounted) {
        setState(() {
          _locationShared = ok;
          _isSharingLocation = false;
        });
        if (!ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Could not get location. Make sure GPS is on.'),
              backgroundColor: const Color(0xFF5A7A1A),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isSharingLocation = false);
    }
  }

  Future<void> _loadPatientData() async {
    try {
      final user = _authService.currentUser;
      if (user != null) {
        final userData = await _authService.getUserData(user.uid);
        if (userData != null) {
          setState(() {
            patientFirstName = userData['firstName'] ?? '';
            patientName = '${userData['firstName']} ${userData['lastName']}';
          });
        }

        final patientData = await _authService.getPatientData(user.uid);
        if (patientData != null) {
          setState(() {
            currentLocation = patientData['address'] ?? '';
          });
        }

        // Load caretaker info for the "Call caretaker" button
        await _loadCaretakerInfo(user.uid);
        await _loadTodaysReminders(user.uid);
      }
    } catch (e) {
      debugPrint('Error loading patient data: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _fadeController.forward();
      }
    }
  }

  Future<void> _loadCaretakerInfo(String patientId) async {
    try {
      final snapshot = await _firestore
          .collection('patient_caretaker_relationships')
          .where('patientId', isEqualTo: patientId)
          .where('status', isEqualTo: 'accepted')
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final rel = snapshot.docs.first.data();
        final caretakerId = rel['caretakerId'] as String?;
        if (caretakerId != null) {
          final caretakerData = await _authService.getUserData(caretakerId);
          if (caretakerData != null && mounted) {
            setState(() {
              caretakerName = caretakerData['firstName'] ?? 'Caretaker';
              caretakerPhone = caretakerData['phone'] ?? '';
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading caretaker info: $e');
    }
  }

  Future<void> _loadTodaysReminders(String patientId) async {
    try {
      final now = DateTime.now();
      final snapshot = await _firestore
          .collection('reminders')
          .where('patientId', isEqualTo: patientId)
          .where('time',
          isGreaterThanOrEqualTo:
          Timestamp.fromDate(DateTime(now.year, now.month, now.day)))
          .where('time',
          isLessThanOrEqualTo: Timestamp.fromDate(
              DateTime(now.year, now.month, now.day, 23, 59, 59)))
          .orderBy('time')
          .get();

      setState(() {
        reminders =
            snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      });
    } catch (e) {
      debugPrint('Error loading reminders: $e');
    }
  }

  Future<void> _handleRefresh() async {
    try {
      final user = _authService.currentUser;
      if (user == null) return;
      setState(() => _now = DateTime.now());
      final results = await Future.wait([
        _authService.getUserData(user.uid),
        _authService.getPatientData(user.uid),
      ]);
      if (mounted) {
        final userData = results[0];
        final patientData = results[1];
        setState(() {
          if (userData != null) {
            patientFirstName = userData['firstName'] ?? '';
            patientName = '${userData['firstName']} ${userData['lastName']}';
          }
          if (patientData != null) {
            currentLocation = patientData['address'] ?? '';
          }
        });
        await Future.wait([
          _loadCaretakerInfo(user.uid),
          _loadTodaysReminders(user.uid),
          _checkForPendingReminders(),
        ]);
        _shareLocationInBackground();
      }
    } catch (e) {
      debugPrint('Error refreshing: $e');
    }
  }

  void _showSignOutConfirmation() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: const Text('Sign out?',
            style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF3E2723))),
        content: const Text('Are you sure you want to sign out?',
            style: TextStyle(color: Color(0xFF8D6E63))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF8D6E63))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _authService.signOut();
              if (mounted) {
                Navigator.pushReplacement(context,
                    MaterialPageRoute(builder: (_) => const LoginPage()));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5A7A1A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: const Text('Sign Out',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCallCaretaker() async {
    final phone = caretakerPhone.isNotEmpty ? caretakerPhone : '';
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No caretaker phone number available.'),
          backgroundColor: const Color(0xFF8D6E63),
          behavior: SnackBarBehavior.floating,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }
    final uri = Uri(
        scheme: 'tel', path: phone.replaceAll(RegExp(r'[^\d]'), ''));
    try {
      if (await canLaunchUrl(uri)) await launchUrl(uri);
    } catch (e) {
      debugPrint('Error calling caretaker: $e');
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.error_outline, color: Color(0xFFE57373)),
          SizedBox(width: 12),
          Text('Error'),
        ]),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'))
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _fadeController.dispose();
    _reminderCheckTimer?.cancel();
    _locationUpdateTimer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  String get _greeting {
    final hour = _now.hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Map<String, dynamic>? get _nextReminder {
    for (final r in reminders) {
      final time = (r['time'] as Timestamp?)?.toDate();
      if (time != null &&
          time.isAfter(DateTime.now()) &&
          r['completed'] != true) {
        return r;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFFAF6F4),
        body: Center(
            child: CircularProgressIndicator(color: Color(0xFF5A7A1A))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFAF6F4),
      body: Stack(
        children: [
          // Background blobs
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFE8C9C0).withOpacity(0.35),
              ),
            ),
          ),
          Positioned(
            bottom: 100,
            left: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF6B8E23).withOpacity(0.07),
              ),
            ),
          ),

          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: RefreshIndicator(
                onRefresh: _handleRefresh,
                color: const Color(0xFF5A7A1A),
                backgroundColor: Colors.white,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // ── Top bar ────────────────────────────────────
                      Row(
                        children: [
                          // Logo + wordmark
                          Row(
                            children: [
                              Image.asset(
                                'assets/images/logo_no_text.png',
                                width: 28,
                                height: 28,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.favorite_rounded,
                                  color: Color(0xFFD4A5A5),
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 7),
                              RichText(
                                text: const TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'Cogni',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w300,
                                        color: Color(0xFF5D4037),
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    TextSpan(
                                      text: 'Care',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF5D4037),
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          // Inbox
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              GestureDetector(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const InboxPage(
                                          isCaretaker: false)),
                                ),
                                child: _TopBarButton(
                                    icon: Icons.notifications_none_rounded),
                              ),
                              if (_pendingRequestCount > 0)
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFE57373),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        _pendingRequestCount > 9
                                            ? '9+'
                                            : '$_pendingRequestCount',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 8,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 8),
                          // Profile
                          GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                  const ProfilePage(isCaretaker: false)),
                            ),
                            child: _TopBarButton(icon: Icons.person_outline_rounded),
                          ),
                          const SizedBox(width: 8),
                          // Sign out
                          GestureDetector(
                            onTap: _showSignOutConfirmation,
                            child: _TopBarButton(icon: Icons.logout_rounded),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // ── Date + greeting card ───────────────────────
                      _buildDateCard(),

                      const SizedBox(height: 20),

                      // ── Call caretaker button (primary red) ─────────
                      ScaleTransition(
                        scale: _pulseAnimation,
                        child: GestureDetector(
                          onTap: _handleCallCaretaker,
                          child: Container(
                            width: double.infinity,
                            height: 72,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFFE53935),
                                  Color(0xFFEF5350)
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      const Color(0xFFE53935).withOpacity(0.35),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.phone_in_talk_rounded,
                                    color: Colors.white, size: 26),
                                const SizedBox(width: 12),
                                Text(
                                  caretakerName.isNotEmpty
                                      ? 'Call $caretakerName'
                                      : 'Call caretaker',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // ── Right now ──────────────────────────────────
                      const _SectionHeader(label: 'RIGHT NOW'),
                      const SizedBox(height: 10),
                      _buildNowCard(),

                      const SizedBox(height: 24),

                      // ── Today's reminders ──────────────────────────
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const _SectionHeader(label: "TODAY'S REMINDERS"),
                          Text(
                            '${reminders.length} total',
                            style: TextStyle(
                              fontSize: 12,
                              color:
                              const Color(0xFF8D6E63).withOpacity(0.6),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildRemindersList(),

                      const SizedBox(height: 24),

                      // ── Bottom row: location + emergency contact ───
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildLocationTile()),
                          const SizedBox(width: 12),
                          Expanded(child: _buildEmergencyContactTile()),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Date + greeting card ──────────────────────────────────────────────────
  Widget _buildDateCard() {
    final dayName = DateFormat('EEEE').format(_now);       // "Tuesday"
    final dateStr = DateFormat('MMMM d, y').format(_now);  // "March 3, 2026"
    final timeStr = DateFormat('h:mm a').format(_now);     // "9:41 AM"

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB07A6E).withOpacity(0.09),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_greeting, $patientFirstName',
                  style: TextStyle(
                    fontSize: 14,
                    color: const Color(0xFF8D6E63).withOpacity(0.8),
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  dayName,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF3E2723),
                    letterSpacing: -0.5,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateStr,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF8D6E63),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Time display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFAF6F4),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              timeStr,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF5A7A1A),
                letterSpacing: -0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── "Right now" card ──────────────────────────────────────────────────────
  Widget _buildNowCard() {
    final next = _nextReminder;
    if (next == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFB07A6E).withOpacity(0.09),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF5A7A1A).withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.check_circle_outline_rounded,
                color: Color(0xFF5A7A1A),
                size: 26,
              ),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Text(
                'Nothing scheduled right now.\nTake it easy — you\'re all caught up!',
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xFF5D4037),
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final time = (next['time'] as Timestamp?)?.toDate();
    final timeStr =
    time != null ? DateFormat('h:mm a').format(time) : '';
    final description = next['description'] as String? ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF5A7A1A),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5A7A1A).withOpacity(0.30),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.20),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  timeStr,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(Icons.access_time_rounded,
                  color: Colors.white54, size: 18),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            next['title'] ?? '',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.3,
              height: 1.2,
            ),
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(
                fontSize: 15,
                color: Colors.white.withOpacity(0.75),
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Reminders list ────────────────────────────────────────────────────────
  Widget _buildRemindersList() {
    if (reminders.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFB07A6E).withOpacity(0.07),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Text(
          'No reminders for today',
          style: TextStyle(
            fontSize: 15,
            color: Color(0xFF8D6E63),
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB07A6E).withOpacity(0.09),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: reminders.asMap().entries.map((entry) {
          final i = entry.key;
          final reminder = entry.value;
          final time = (reminder['time'] as Timestamp?)?.toDate();
          final timeStr =
          time != null ? DateFormat('h:mm a').format(time) : '';
          final isCompleted = reminder['completed'] == true;
          final isLast = i == reminders.length - 1;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 14),
                child: Row(
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isCompleted
                              ? const Color(0xFFBDB0AC)
                              : const Color(0xFF5A7A1A),
                        ),
                      ),
                    ),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isCompleted
                            ? const Color(0xFFDDD5D0)
                            : const Color(0xFF5A7A1A),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        reminder['title'] ?? '',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isCompleted
                              ? const Color(0xFFBDB0AC)
                              : const Color(0xFF3E2723),
                          decoration: isCompleted
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                        ),
                      ),
                    ),
                    if (isCompleted)
                      const Icon(Icons.check_rounded,
                          color: Color(0xFF5A7A1A), size: 18),
                  ],
                ),
              ),
              if (!isLast)
                const Divider(
                  height: 1,
                  indent: 18,
                  endIndent: 18,
                  color: Color(0xFFF0E8E5),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ── Location tile ─────────────────────────────────────────────────────────
  Widget _buildLocationTile() {
    return GestureDetector(
      onTap: _isSharingLocation ? null : _onShareLocationTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFB07A6E).withOpacity(0.09),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _locationShared
                    ? const Color(0xFF5A7A1A).withOpacity(0.10)
                    : const Color(0xFFF4E4E1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: _isSharingLocation
                  ? const Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF5A7A1A)),
              )
                  : Icon(
                _locationShared
                    ? Icons.location_on_rounded
                    : Icons.location_off_rounded,
                size: 18,
                color: _locationShared
                    ? const Color(0xFF5A7A1A)
                    : const Color(0xFFD4A5A5),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _locationShared ? 'Sharing' : 'Location',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _locationShared
                    ? const Color(0xFF5A7A1A)
                    : const Color(0xFF5D4037),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _locationShared ? 'Caretaker can see you' : 'Tap to share',
              style: const TextStyle(fontSize: 12, color: Color(0xFF8D6E63)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Emergency contact tile ────────────────────────────────────────────────
  Widget _buildEmergencyContactTile() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB07A6E).withOpacity(0.09),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFF4E4E1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.favorite_border_rounded,
                size: 18, color: Color(0xFFD4A5A5)),
          ),
          const SizedBox(height: 10),
          const Text(
            'Call caretaker',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF5D4037)),
          ),
        ],
      ),
    );
  }
}

// ── Reusable top bar icon button ──────────────────────────────────────────────
class _TopBarButton extends StatelessWidget {
  final IconData icon;
  const _TopBarButton({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB07A6E).withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, color: const Color(0xFFD4A5A5), size: 18),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Color(0xFF8D6E63),
        letterSpacing: 1.2,
      ),
    );
  }
}

// ── Reminder Dialog ───────────────────────────────────────────────────────────
class ReminderDialog extends StatelessWidget {
  final String title;
  final String description;
  final String time;
  final String reminderId;

  const ReminderDialog({
    super.key,
    required this.title,
    required this.description,
    required this.time,
    required this.reminderId,
  });

  Future<void> _markAsComplete(BuildContext context) async {
    try {
      if (reminderId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('reminders')
            .doc(reminderId)
            .update({'completed': true});
      }
    } catch (e) {
      debugPrint('Error marking reminder complete: $e');
    }
  }

  Future<void> _snoozeReminder(BuildContext context) async {
    try {
      if (reminderId.isEmpty) return;
      await FirebaseFirestore.instance
          .collection('reminders')
          .doc(reminderId)
          .update({
        'time': Timestamp.fromDate(
            DateTime.now().add(const Duration(minutes: 5))),
        'completed': false,
      });
    } catch (e) {
      debugPrint('Error snoozing reminder: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFB07A6E).withOpacity(0.18),
              blurRadius: 40,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFF5A7A1A).withOpacity(0.10),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.alarm_rounded,
                  color: Color(0xFF5A7A1A), size: 30),
            ),
            const SizedBox(height: 16),
            if (time.isNotEmpty)
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAF6F4),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  time,
                  style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF8D6E63),
                      fontWeight: FontWeight.w600),
                ),
              ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF3E2723),
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                description,
                style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF8D6E63),
                    height: 1.5),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () async {
                  await _markAsComplete(context);
                  if (context.mounted) Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5A7A1A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Text('Got it',
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton(
                onPressed: () async {
                  await _snoozeReminder(context);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                        const Text('Reminder snoozed for 5 minutes'),
                        backgroundColor: const Color(0xFF5A7A1A),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        margin: const EdgeInsets.all(16),
                      ),
                    );
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF5A7A1A),
                  side: const BorderSide(
                      color: Color(0xFFEDE5E2), width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Remind me in 5 minutes',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}