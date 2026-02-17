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
import '../caretaker/calendar_page.dart';

class PatientHomePage extends StatefulWidget {
  const PatientHomePage({super.key});

  @override
  State<PatientHomePage> createState() => _PatientHomePageState();
}

class _PatientHomePageState extends State<PatientHomePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocationService _locationService = LocationService();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Timer? _reminderCheckTimer;
  StreamSubscription<QuerySnapshot>? _reminderSubscription;
  StreamSubscription<QuerySnapshot>? _snoozedReminderSubscription;

  String patientName = "Loading...";
  List<Map<String, dynamic>> reminders = [];
  bool _isLoading = true;
  bool _isSharingLocation = false;
  bool _locationShared = false;

  // Track which reminder dialogs are currently showing to prevent duplicates
  final Set<String> _showingDialogs = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    // Set up notification tap handler
    NotificationService.onNotificationTap = (data) {
      _showReminderDialog(data);
    };

    // Set up real-time listener for reminders
    _setupReminderListener();

    // Start periodic reminder check timer (every 60 seconds)
    _startReminderCheckTimer();

    _loadPatientData();

    // Check for pending reminders after data loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        _checkForPendingReminders();
      });

      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        _shareLocationInBackground();
      });
    });
  }

  void _startReminderCheckTimer() {
    _reminderCheckTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      if (mounted) {
        _checkForPendingReminders();
      }
    });
  }

  void _setupReminderListener() {
    final user = _authService.currentUser;
    if (user == null) return;

    // Listen to all incomplete reminders for this patient
    _reminderSubscription = _firestore
        .collection('reminders')
        .where('patientId', isEqualTo: user.uid)
        .where('completed', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      final now = DateTime.now();

      for (var doc in snapshot.docs) {
        final reminder = doc.data();

        // Safely get time with null check
        final timeValue = reminder['time'];
        if (timeValue == null) continue;

        final time = (timeValue as Timestamp).toDate();

        // Check if reminder is due (within 1 minute of scheduled time)
        final difference = now.difference(time);
        if (difference.inSeconds >= 0 && difference.inSeconds < 60) {
          // Check if this is a snoozed reminder
          final isSnoozed = reminder['isSnoozed'] == true;

          String timeStr;
          if (isSnoozed && reminder['originalTimeText'] != null) {
            // Use the stored original time text for snoozed reminders
            timeStr = reminder['originalTimeText'] as String;
          } else {
            // Format time to LOCAL timezone for regular reminders
            timeStr = DateFormat('h:mm a').format(time.toLocal());
          }

          // Show dialog
          _showReminderDialog({
            'reminderId': doc.id,
            'title': reminder['title'] ?? 'Reminder',
            'description': reminder['description'] ?? '',
            'time': timeStr,
            'timestamp': time.millisecondsSinceEpoch,
            'isSnooze': isSnoozed,
          });

          // Only show one at a time
          break;
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // When app comes to foreground, check for pending reminders
    if (state == AppLifecycleState.resumed) {
      _checkForPendingReminders();
      // Restart timer if it was cancelled
      if (_reminderCheckTimer == null || !_reminderCheckTimer!.isActive) {
        _startReminderCheckTimer();
      }
    } else if (state == AppLifecycleState.paused) {
      // Cancel timer when app goes to background to save resources
      _reminderCheckTimer?.cancel();
    }
  }

  Future<void> _checkForPendingReminders() async {
    try {
      final user = _authService.currentUser;
      if (user == null) return;

      final now = Timestamp.now();

      // Get all reminders that are due but not completed
      final snapshot = await _firestore
          .collection('reminders')
          .where('patientId', isEqualTo: user.uid)
          .where('completed', isEqualTo: false)
          .where('time', isLessThanOrEqualTo: now)
          .orderBy('time')
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final reminder = doc.data();

        // Format time with null check
        final timeValue = reminder['time'];
        if (timeValue == null) return;

        final time = (timeValue as Timestamp).toDate();

        // Check if this is a snoozed reminder
        final isSnoozed = reminder['isSnoozed'] == true;

        String timeStr;
        if (isSnoozed && reminder['originalTimeText'] != null) {
          // Use the stored original time text for snoozed reminders
          timeStr = reminder['originalTimeText'] as String;
        } else {
          // Format time to LOCAL timezone for regular reminders
          timeStr = DateFormat('h:mm a').format(time.toLocal());
        }

        // Show dialog
        _showReminderDialog({
          'reminderId': doc.id,
          'title': reminder['title'] ?? 'Reminder',
          'description': reminder['description'] ?? '',
          'time': timeStr,
          'timestamp': time.millisecondsSinceEpoch,
          'isSnooze': isSnoozed,
        });
      }
    } catch (e) {
      print('Error checking pending reminders: $e');
    }
  }

  void _showReminderDialog(Map<String, dynamic> reminderData) {
    if (!mounted) return;

    final reminderId = reminderData['reminderId'] ?? '';
    if (reminderId.isEmpty) return;

    // Check if this dialog is already showing
    if (_showingDialogs.contains(reminderId)) {
      print('Dialog for reminder $reminderId is already showing, skipping duplicate');
      return;
    }

    // Mark this dialog as showing
    _showingDialogs.add(reminderId);
    print('Showing dialog for reminder $reminderId');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ReminderDialog(
        title: reminderData['title'] ?? 'Reminder',
        description: reminderData['description'] ?? '',
        time: reminderData['time'] ?? '',
        reminderId: reminderId,
        timestamp: reminderData['timestamp'],
        isSnooze: reminderData['isSnooze'] == true,
      ),
    ).then((_) {
      // Remove from tracking when dialog is dismissed
      _showingDialogs.remove(reminderId);
      print('Dialog for reminder $reminderId dismissed and removed from tracking');
    });
  }

  void _showSignOutConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.logout, color: Color(0xFF8FA9C9)),
            SizedBox(width: 12),
            Text('Sign Out'),
          ],
        ),
        content: const Text(
          'Are you sure you want to sign out?',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: Color(0xFF666666),
                fontSize: 16,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog first
              await _authService.signOut();
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8FA9C9),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Sign Out',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// Share location in background; never blocks UI or crashes the app.
  Future<void> _shareLocationInBackground() async {
    try {
      final user = _authService.currentUser;
      if (user != null) {
        final ok = await _locationService.shareLocation(user.uid);
        if (mounted && ok) setState(() => _locationShared = true);
      }
    } catch (e) {
      print('Location share error (non-fatal): $e');
    }
  }

  /// User taps "Share location" – request permission and share (visible ask).
  Future<void> _onShareLocationTap() async {
    final user = _authService.currentUser;
    if (user == null) return;
    if (_isSharingLocation) return;
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
            const SnackBar(
              content: Text(
                'Couldn\'t get location. Turn on GPS, try outdoors, and tap Allow location again.',
              ),
              backgroundColor: Color(0xFF8FA9C9),
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      print('Location share error: $e');
      if (mounted) {
        setState(() => _isSharingLocation = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Location error: $e')),
        );
      }
    }
  }

  Future<void> _loadPatientData() async {
    try {
      final user = _authService.currentUser;
      if (user != null) {
        final userData = await _authService.getUserData(user.uid);
        if (userData != null && mounted) {
          setState(() {
            patientName = '${userData['firstName']} ${userData['lastName']}';
          });
        }

        // Load today's reminders
        await _loadTodaysReminders(user.uid);
      }
    } catch (e) {
      print('Error loading patient data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadTodaysReminders(String patientId) async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

      final snapshot = await _firestore
          .collection('reminders')
          .where('patientId', isEqualTo: patientId)
          .where('time', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('time', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .orderBy('time')
          .get();

      if (mounted) {
        setState(() {
          reminders = snapshot.docs
              .map((doc) => {'id': doc.id, ...doc.data()})
              .where((reminder) => reminder['isSnoozed'] != true) // Exclude snoozed reminders
              .toList();
        });
      }
    } catch (e) {
      print('Error loading reminders: $e');
    }
  }

  /// Handle pull-to-refresh
  Future<void> _handleRefresh() async {
    try {
      final user = _authService.currentUser;
      if (user == null) return;

      // Reload user data
      final userData = await _authService.getUserData(user.uid);
      if (userData != null && mounted) {
        setState(() {
          patientName = '${userData['firstName']} ${userData['lastName']}';
        });
      }

      // Reload reminders and check for pending ones
      await Future.wait([
        _loadTodaysReminders(user.uid),
        _checkForPendingReminders(),
      ]);

      // Re-share location in background (don't await)
      _shareLocationInBackground();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Page refreshed'),
            backgroundColor: Color(0xFF8FA9C9),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Error refreshing: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error refreshing: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _reminderCheckTimer?.cancel();
    _reminderSubscription?.cancel();
    _snoozedReminderSubscription?.cancel();
    _showingDialogs.clear(); // Clear dialog tracking
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F5F5),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _handleRefresh,
          color: const Color(0xFF8FA9C9),
          backgroundColor: Colors.white,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Landing Page (Patient)',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF666666),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      IconButton(
                        onPressed: _showSignOutConfirmation,
                        icon: const Icon(Icons.logout),
                        tooltip: 'Logout',
                        color: const Color(0xFF666666),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildEmergencyButton(),
                  const SizedBox(height: 20),
                  _buildWelcomeCard(),
                  const SizedBox(height: 20),
                  _buildLocationShareCard(),
                  const SizedBox(height: 20),
                  _buildCalendarButton(),
                  const SizedBox(height: 20),
                  _buildActivityCard(),
                  const SizedBox(height: 20),
                  _buildRemindersCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmergencyButton() {
    return ScaleTransition(
      scale: _pulseAnimation,
      child: Container(
        width: double.infinity,
        height: 80,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF4757), Color(0xFFFF6B7A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF4757).withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _handleEmergencyCall,
            borderRadius: BorderRadius.circular(20),
            child: const Center(
              child: Text(
                'Emergency',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFE8C4C8),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ProfilePage(isCaretaker: false),
                ),
              );
            },
            borderRadius: BorderRadius.circular(25),
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person,
                size: 28,
                color: Color(0xFF8FA9C9),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Welcome $patientName',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF3D2C31),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationShareCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF8FA9C9).withOpacity(0.5), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF8FA9C9).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.location_on,
                  size: 28,
                  color: Color(0xFF8FA9C9),
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Share location with caretaker',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF3D2C31),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Allow location so your caretaker can see where you are on the map.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSharingLocation ? null : _onShareLocationTap,
              icon: _isSharingLocation
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
                  : Icon(
                _locationShared ? Icons.check_circle : Icons.my_location,
                color: Colors.white,
                size: 22,
              ),
              label: Text(
                _isSharingLocation
                    ? 'Getting location...'
                    : _locationShared
                    ? 'Location shared'
                    : 'Allow location',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8FA9C9),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarButton() {
    final user = _authService.currentUser;
    if (user == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      height: 80,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8FA9C9), Color(0xFFA5BDD4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8FA9C9).withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CalendarPage(
                  patientId: user.uid,
                  isCaretaker: false,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.calendar_month,
                    size: 32,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'View Calendar',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: Colors.white,
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActivityCard() {
    // Find the most recent non-snoozed reminder
    String displayText = 'No recent reminders';

    if (reminders.isNotEmpty) {
      // Get the most recent reminder (first one since they're ordered by time)
      final recentReminder = reminders.first;
      final time = (recentReminder['time'] as Timestamp?)?.toDate();
      final timeStr = time != null ? DateFormat('h:mm a').format(time) : '';
      displayText = '${recentReminder['title']} at $timeStr';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8C4C8), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Most Recent Reminder',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF3D2C31),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFE8C4C8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              displayText,
              style: const TextStyle(
                fontSize: 18,
                color: Color(0xFF3D2C31),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemindersCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8C4C8), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Today's reminders",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF3D2C31),
            ),
          ),
          const SizedBox(height: 16),
          if (reminders.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF5E6E8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'No reminders for today',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF7A6A70),
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            ...reminders.map((reminder) {
              final time = (reminder['time'] as Timestamp?)?.toDate();
              final timeStr = time != null ? DateFormat('h:mm a').format(time) : '';
              final description = reminder['description'] as String? ?? '';

              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8C4C8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reminder['title'] ?? '',
                      style: const TextStyle(
                        fontSize: 18,
                        color: Color(0xFF3D2C31),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (timeStr.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        timeStr,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF5A4046),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        description,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF5A4046),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  void _handleEmergencyCall() async {
    _showErrorDialog('Emergency calling feature not available. Please contact your caretaker directly.');
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Color(0xFFFF4757)),
            SizedBox(width: 12),
            Text('Error'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

// Reminder Dialog Widget
class ReminderDialog extends StatelessWidget {
  final String title;
  final String description;
  final String time;
  final String reminderId;
  final dynamic timestamp;
  final bool isSnooze;

  const ReminderDialog({
    super.key,
    required this.title,
    required this.description,
    required this.time,
    required this.reminderId,
    this.timestamp,
    this.isSnooze = false,
  });

  Future<void> _markAsComplete(BuildContext context) async {
    try {
      if (reminderId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('reminders')
            .doc(reminderId)
            .update({'completed': true});

        // Clear notification tracking so it can be shown again if needed
        if (timestamp != null) {
          try {
            final timestampInt = timestamp is int ? timestamp : int.tryParse(timestamp.toString());
            if (timestampInt != null) {
              final scheduledTime = DateTime.fromMillisecondsSinceEpoch(timestampInt);
              NotificationService.clearNotificationTracking(
                reminderId,
                scheduledTime,
                isSnooze: isSnooze,
              );
            }
          } catch (e) {
            print('Error clearing notification tracking: $e');
          }
        }
      }
    } catch (e) {
      print('Error marking reminder as complete: $e');
    }
  }

  Future<void> _snoozeReminder(BuildContext context) async {
    try {
      if (reminderId.isEmpty) return;

      // Get the original reminder data
      final originalReminder = await FirebaseFirestore.instance
          .collection('reminders')
          .doc(reminderId)
          .get();

      if (!originalReminder.exists) return;

      final reminderData = originalReminder.data()!;

      // Mark the ORIGINAL reminder as complete immediately
      await FirebaseFirestore.instance
          .collection('reminders')
          .doc(reminderId)
          .update({'completed': true});

      print('Marked original reminder $reminderId as complete');

      // Get the original timestamp and format it to LOCAL time
      DateTime originalScheduledTime;
      if (timestamp != null) {
        final timestampInt = timestamp is int ? timestamp : int.tryParse(timestamp.toString());
        originalScheduledTime = DateTime.fromMillisecondsSinceEpoch(timestampInt ?? 0);
      } else {
        final timeValue = reminderData['time'];
        originalScheduledTime = (timeValue as Timestamp).toDate();
      }

      // Format the time to LOCAL timezone
      final originalFormattedTime = DateFormat('h:mm a').format(originalScheduledTime.toLocal());

      // Create the body text with the formatted time
      final description = reminderData['description'] ?? '';
      final originalBodyText = 'Scheduled for $originalFormattedTime${description.isNotEmpty ? ':\n$description' : ''}';

      // Create a COMPLETELY NEW reminder 5 minutes from now
      final newTime = DateTime.now().add(const Duration(minutes: 5));

      // Create NEW reminder in 'reminders' collection
      final docRef = await FirebaseFirestore.instance.collection('reminders').add({
        'patientId': reminderData['patientId'],
        'title': reminderData['title'],
        'description': reminderData['description'],
        'time': Timestamp.fromDate(newTime),
        'originalTimeText': originalFormattedTime,  // Store the formatted time!
        'completed': false,
        'isSnoozed': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      print('Created new snoozed reminder ${docRef.id} for $newTime');

      // Schedule local notification for the NEW reminder
      await NotificationService.scheduleLocalNotification(
        id: docRef.id.hashCode,
        title: reminderData['title'] ?? 'Reminder',
        body: '$originalBodyText (Snoozed)',  // Use the formatted body text
        scheduledTime: newTime,
        payload: {
          'reminderId': docRef.id,
          'title': reminderData['title'] ?? 'Reminder',
          'description': reminderData['description'] ?? '',
          'timestamp': newTime.millisecondsSinceEpoch,
          'originalBodyText': originalBodyText,  // Store the formatted body text in payload
          'isSnooze': true,
        },
      );

      print('Scheduled local notification for new reminder ${docRef.id}');
    } catch (e) {
      print('Error snoozing reminder: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFFF5E6E8),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.notification_important,
              size: 64,
              color: Color(0xFF8FA9C9),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF3D2C31),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isSnooze ? 'Original time: $time' : 'Scheduled for: $time',
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF5A4046),
                fontWeight: FontWeight.w600,
              ),
            ),
            if (isSnooze) ...[
              const SizedBox(height: 4),
              const Text(
                '(Snoozed)',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF8FA9C9),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            if (description.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8C4C8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  description,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF3D2C31),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  await _markAsComplete(context);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8FA9C9),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Understood',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  await _snoozeReminder(context);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Reminder snoozed for 5 minutes'),
                        backgroundColor: Color(0xFF8FA9C9),
                      ),
                    );
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF8FA9C9),
                  side: const BorderSide(color: Color(0xFF8FA9C9), width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Remind me in 5 minutes',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}