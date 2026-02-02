import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/auth_service.dart';
import '../../services/location_service.dart';
import '../profile_page.dart';
import '../auth/login_page.dart';

class PatientHomePage extends StatefulWidget {
  const PatientHomePage({super.key});

  @override
  State<PatientHomePage> createState() => _PatientHomePageState();
}

class _PatientHomePageState extends State<PatientHomePage>
    with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocationService _locationService = LocationService();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

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

    _loadPatientData();
    // Run location share after UI is ready so it doesn't block or freeze the app
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        _shareLocationInBackground();
      });
    });
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

  @override
  void dispose() {
    _pulseController.dispose();
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
        child: SingleChildScrollView(
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
                      onPressed: () async {
                        await _authService.signOut();
                        if (mounted) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => const LoginPage()),
                          );
                        }
                      },
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