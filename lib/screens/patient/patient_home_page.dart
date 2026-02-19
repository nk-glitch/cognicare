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
  Timer? _locationUpdateTimer;

  String patientName = "Loading...";
  String emergencyContactName = "Not set";
  String emergencyContactPhone = "";
  String currentLocation = "Loading...";
  String currentActivity = "No activity scheduled";
  List<Map<String, dynamic>> reminders = [];
  bool _isLoading = true;
  bool _isSharingLocation = false;
  bool _locationShared = false;

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

    // Start periodic reminder check timer (every 30 seconds)
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

      // Update location every 5 min so caretaker sees fresh location
      _locationUpdateTimer?.cancel();
      _locationUpdateTimer = Timer.periodic(const Duration(minutes: 5), (_) {
        if (mounted) _shareLocationInBackground();
      });
    });
  }

  void _startLocationUpdateTimer() {
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted) _shareLocationInBackground();
    });
  }

  void _startReminderCheckTimer() {
    _reminderCheckTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _checkForPendingReminders();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _checkForPendingReminders();
      if (_reminderCheckTimer == null || !_reminderCheckTimer!.isActive) {
        _startReminderCheckTimer();
      }
      // Restart location timer if it was stopped (e.g. by OS in background)
      if (_locationUpdateTimer == null || !_locationUpdateTimer!.isActive) {
        _startLocationUpdateTimer();
      }
      // Send location immediately when app comes to foreground so caretaker sees fresh update
      _shareLocationInBackground();
    } else if (state == AppLifecycleState.paused) {
      _reminderCheckTimer?.cancel();
      // Keep location timer running in background so updates continue every 5 min
      // (OS may still suspend; when resumed we restart timer and send once)
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

        // Format time
        final time = (reminder['time'] as Timestamp).toDate();
        final timeStr = DateFormat('h:mm a').format(time);

        // Show dialog
        _showReminderDialog({
          'reminderId': doc.id,
          'title': reminder['title'] ?? 'Reminder',
          'description': reminder['description'] ?? '',
          'time': timeStr,
        });
      }
    } catch (e) {
      print('Error checking pending reminders: $e');
    }
  }

  void _showReminderDialog(Map<String, dynamic> reminderData) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ReminderDialog(
        title: reminderData['title'] ?? 'Reminder',
        description: reminderData['description'] ?? '',
        time: reminderData['time'] ?? '',
        reminderId: reminderData['reminderId'] ?? '',
      ),
    );
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
        if (userData != null) {
          setState(() {
            patientName = '${userData['firstName']} ${userData['lastName']}';
          });
        }

        final patientData = await _authService.getPatientData(user.uid);
        if (patientData != null) {
          setState(() {
            emergencyContactName = patientData['emergencyContact'] ?? 'Not set';
            emergencyContactPhone = patientData['emergencyContactNumber'] ?? '';
            currentLocation = patientData['address'] ?? 'Home';
          });
        }

        // Load today's reminders
        await _loadTodaysReminders(user.uid);
        // Location is shared in background via _shareLocationInBackground() after UI loads
      }
    } catch (e) {
      print('Error loading patient data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
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

      setState(() {
        reminders = snapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList();

        // Set current activity to the next upcoming reminder
        if (reminders.isNotEmpty) {
          final nextReminder = reminders.first;
          final time = (nextReminder['time'] as Timestamp?)?.toDate();
          final timeStr = time != null ? DateFormat('h:mm a').format(time) : '';
          currentActivity = '${nextReminder['title']} at $timeStr';
        }
      });
    } catch (e) {
      print('Error loading reminders: $e');
    }
  }

  /// Handle pull-to-refresh
  Future<void> _handleRefresh() async {
    try {
      final user = _authService.currentUser;
      if (user == null) return;

      // Reload user and patient data
      final userData = await _authService.getUserData(user.uid);
      if (userData != null && mounted) {
        setState(() {
          patientName = '${userData['firstName']} ${userData['lastName']}';
        });
      }

      final patientData = await _authService.getPatientData(user.uid);
      if (patientData != null && mounted) {
        setState(() {
          emergencyContactName = patientData['emergencyContact'] ?? 'Not set';
          emergencyContactPhone = patientData['emergencyContactNumber'] ?? '';
          currentLocation = patientData['address'] ?? 'Home';
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
    _locationUpdateTimer?.cancel();
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFD4ADB1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.home,
                  size: 22,
                  color: Color(0xFF3D2C31),
                ),
                const SizedBox(width: 12),
                Text(
                  currentLocation.isEmpty ? 'You are Home' : currentLocation,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3D2C31),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFFD4ADB1), thickness: 1.5),
          const SizedBox(height: 12),
          const Text(
            'Emergency Contact',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF3D2C31),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            emergencyContactName,
            style: const TextStyle(
              fontSize: 16,
              color: Color(0xFF5A4046),
              fontWeight: FontWeight.w500,
            ),
          ),
          if (emergencyContactPhone.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.phone,
                  size: 18,
                  color: Color(0xFF5A4046),
                ),
                const SizedBox(width: 6),
                Text(
                  emergencyContactPhone,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF5A4046),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
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

  Widget _buildActivityCard() {
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
            'What you are supposed to be doing',
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
              currentActivity,
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
    if (emergencyContactPhone.isEmpty) {
      _showErrorDialog('No emergency contact number set');
      return;
    }

    final phoneNumber = emergencyContactPhone.replaceAll(RegExp(r'[^\d]'), '');
    final uri = Uri(scheme: 'tel', path: phoneNumber);

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) {
          _showErrorDialog('Unable to make phone call');
        }
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Error: ${e.toString()}');
      }
    }
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
      print('Error marking reminder as complete: $e');
    }
  }

  Future<void> _snoozeReminder(BuildContext context) async {
    try {
      if (reminderId.isEmpty) return;

      // Update the same reminder's time to 5 minutes from now
      final newTime = DateTime.now().add(const Duration(minutes: 5));

      await FirebaseFirestore.instance
          .collection('reminders')
          .doc(reminderId)
          .update({
        'time': Timestamp.fromDate(newTime),
        'completed': false,
      });
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
              'Scheduled for: $time',
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF5A4046),
                fontWeight: FontWeight.w600,
              ),
            ),
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