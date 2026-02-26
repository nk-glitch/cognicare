import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../auth/login_page.dart';
import '../profile_page.dart';
import '../inbox_page.dart';
import 'patient_detail_page.dart';

class CaretakerHomePage extends StatefulWidget {
  const CaretakerHomePage({super.key});

  @override
  State<CaretakerHomePage> createState() => _CaretakerHomePageState();
}

class _CaretakerHomePageState extends State<CaretakerHomePage>
    with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  String caretakerName = "Loading...";
  List<Map<String, dynamic>> patients = [];
  bool _isLoading = true;
  int _unreadAlertCount = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeIn,
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _loadCaretakerData();
    _animationController.forward();
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    await NotificationService.initialize();
    await NotificationService.saveFCMToken();
    _listenForUnreadCount();
  }

  // Fetch ALL alerts then count unread in Dart.
  // Using where('isRead', isEqualTo: false) makes Firestore deliver cached
  // docs one-at-a-time → badge animates 0→1→2→3. Fetching everything and
  // counting locally gives one atomic snapshot so the badge jumps straight
  // to the correct number.
  void _listenForUnreadCount() {
    final user = _authService.currentUser;
    if (user == null) return;
    _firestore
        .collection('caretaker_alerts')
        .where('caretakerId', isEqualTo: user.uid)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      final count = snapshot.docs.where((d) => d.data()['isRead'] != true).length;
      setState(() => _unreadAlertCount = count);
    });
  }

  void _openInbox() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const InboxPage(isCaretaker: true)),
    );
  }

  // Refresh data - can be called after returning from other screens
  Future<void> _refreshData() async {
    setState(() {
      _isLoading = true;
    });
    await _loadCaretakerData();
  }

  Future<void> _loadCaretakerData() async {
    try {
      final user = _authService.currentUser;
      print('DEBUG: Loading caretaker data for user: ${user?.uid}');

      if (user != null) {
        final userData = await _authService.getUserData(user.uid);
        if (userData != null) {
          setState(() {
            caretakerName = '${userData['firstName']} ${userData['lastName']}';
          });
        }

        // Load accepted patients
        print('DEBUG: Querying relationships...');
        final relationshipsSnapshot = await _firestore
            .collection('patient_caretaker_relationships')
            .where('caretakerId', isEqualTo: user.uid)
            .where('status', isEqualTo: 'accepted')
            .get();

        print('DEBUG: Found ${relationshipsSnapshot.docs.length} accepted relationships');

        List<Map<String, dynamic>> loadedPatients = [];
        for (var doc in relationshipsSnapshot.docs) {
          final data = doc.data();
          final patientId = data['patientId'];
          print('DEBUG: Loading patient: $patientId');

          // Get patient user data
          final patientUserData = await _authService.getUserData(patientId);
          final patientData = await _authService.getPatientData(patientId);

          print('DEBUG: Patient user data: $patientUserData');
          print('DEBUG: Patient data: $patientData');

          final patientName = patientUserData != null
              ? '${patientUserData['firstName']} ${patientUserData['lastName']}'
              : 'Patient';
          final location = patientData?['address'] ?? 'No location set';

          // Get today's reminders for this patient
          final now = DateTime.now();
          final startOfDay = DateTime(now.year, now.month, now.day);
          final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

          final remindersSnapshot = await _firestore
              .collection('reminders')
              .where('patientId', isEqualTo: patientId)
              .where('time', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
              .where('time', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
              .get();

          final remindersList = remindersSnapshot.docs
              .where((doc) => doc.data()['isSnoozed'] != true) // Filter out snoozed reminders
              .map((doc) => doc.data()['title'] as String)
              .toList();

          print('DEBUG: Found ${remindersList.length} reminders for patient');

          loadedPatients.add({
            'patientId': patientId,
            'name': patientName,
            'location': location,
            'reminders': remindersList,
          });
        }

        print('DEBUG: Total patients loaded: ${loadedPatients.length}');

        setState(() {
          patients = loadedPatients;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e, stackTrace) {
      print('Error loading caretaker data: $e');
      print('Stack trace: $stackTrace');
      if (e.toString().contains('index') || e.toString().contains('Index')) {
        print('Firebase: Create the composite index suggested in the error above in Firebase Console > Firestore > Indexes');
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5E6E8),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _buildPatientList(),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: _buildAddPatientFAB(),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFE8C4C8),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat('MMMM dd, yyyy').format(DateTime.now()),
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF5A4046),
                  fontWeight: FontWeight.w500,
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Image.asset(
                      'assets/images/logo_no_text.png',
                      width: 28,
                      height: 28,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.favorite,
                          color: Color(0xFFD47A8A),
                          size: 24,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.logout, color: Color(0xFF5A4046)),
                    onPressed: () async {
                      await _authService.signOut();
                      if (mounted) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                        );
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Welcome',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF3D2C31),
                        height: 1.2,
                      ),
                    ),
                    Text(
                      caretakerName,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF5A4046),
                      ),
                    ),
                  ],
                ),
              ),
              // Inbox bell with unread badge
              Stack(
                clipBehavior: Clip.none,
                children: [
                  InkWell(
                    onTap: _openInbox,
                    borderRadius: BorderRadius.circular(35),
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.notifications, size: 28, color: Color(0xFF8FA9C9)),
                    ),
                  ),
                  if (_unreadAlertCount > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Color(0xFFD32F2F), shape: BoxShape.circle),
                        child: Text(
                          _unreadAlertCount > 9 ? '9+' : '$_unreadAlertCount',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ProfilePage(isCaretaker: true),
                        ),
                      );
                      _refreshData();
                    },
                    borderRadius: BorderRadius.circular(35),
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.person,
                        size: 40,
                        color: Color(0xFF8FA9C9),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Profile',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF5A4046),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.6),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.people,
                  size: 18,
                  color: Color(0xFF5A4046),
                ),
                const SizedBox(width: 8),
                Text(
                  '${patients.length} ${patients.length == 1 ? 'Patient' : 'Patients'} Under Care',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF5A4046),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientList() {
    if (patients.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 80,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No patients yet',
                    style: TextStyle(
                      fontSize: 20,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap the button below to add a patient',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Patients appear here after they accept your\nconnection request from their Profile.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Pull down to refresh',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade400,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: patients.length,
        itemBuilder: (context, index) {
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: Duration(milliseconds: 300 + (index * 100)),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: Opacity(
                  opacity: value,
                  child: child,
                ),
              );
            },
            child: _buildPatientCard(patients[index]),
          );
        },
      ),
    );
  }

  Widget _buildPatientCard(Map<String, dynamic> patient) {
    final String name = patient['name'] ?? 'Unknown';
    final String location = patient['location'] ?? 'No location';
    final List<dynamic> reminders = patient['reminders'] ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
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
                builder: (context) => PatientDetailPage(
                  patientId: patient['patientId'] as String,
                  patientName: name,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.blue.shade300,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          name.split(' ').map((n) => n.isNotEmpty ? n[0] : '').join(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF3D2C31),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                size: 16,
                                color: Color(0xFF8FA9C9),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  location,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF7A6A70),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5E6E8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.chevron_right,
                        color: Color(0xFF8FA9C9),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8C4C8).withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.notifications_active,
                        size: 18,
                        color: Color(0xFFD47A8A),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      "Today's Reminders:",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF3D2C31),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (reminders.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5E6E8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 20,
                          color: Color(0xFF8FA9C9),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'No reminders scheduled',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF7A6A70),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ...reminders.map((reminder) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5E6E8),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFE8C4C8),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Color(0xFFD47A8A),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            reminder.toString(),
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF5A4046),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddPatientFAB() {
    return FloatingActionButton.extended(
      onPressed: _showAddPatientDialog,
      backgroundColor: const Color(0xFF8FA9C9),
      elevation: 8,
      icon: const Icon(Icons.person_add, color: Colors.white),
      label: const Text(
        'Add Patient',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }

  void _showAddPatientDialog() {
    final phoneController = TextEditingController();
    bool isSearching = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Add Patient'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter the patient\'s phone number to connect with them.'),
              const SizedBox(height: 16),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Patient Phone Number',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.phone),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSearching ? null : () async {
                final phone = phoneController.text.trim();
                if (phone.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a phone number')),
                  );
                  return;
                }

                setDialogState(() => isSearching = true);

                try {
                  // Search for patient by phone number
                  final usersSnapshot = await _firestore
                      .collection('users')
                      .where('phone', isEqualTo: phone)
                      .where('userType', isEqualTo: 'patient')
                      .limit(1)
                      .get();

                  if (usersSnapshot.docs.isEmpty) {
                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('No patient found with this phone number'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                    return;
                  }

                  final patientUserId = usersSnapshot.docs.first.id;
                  final currentUserId = _authService.currentUser!.uid;

                  // Check if relationship already exists
                  final existingRelationship = await _firestore
                      .collection('patient_caretaker_relationships')
                      .where('patientId', isEqualTo: patientUserId)
                      .where('caretakerId', isEqualTo: currentUserId)
                      .limit(1)
                      .get();

                  if (existingRelationship.docs.isNotEmpty) {
                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Connection request already sent'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                    return;
                  }

                  // Create connection request
                  await _firestore.collection('patient_caretaker_relationships').add({
                    'patientId': patientUserId,
                    'caretakerId': currentUserId,
                    'status': 'pending',
                    'createdAt': FieldValue.serverTimestamp(),
                  });

                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Connection request sent! Waiting for patient to accept.'),
                        backgroundColor: Color(0xFF8FA9C9),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  print('Error sending request: $e');
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } finally {
                  setDialogState(() => isSearching = false);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8FA9C9),
              ),
              child: isSearching
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Text('Send Request'),
            ),
          ],
        ),
      ),
    );
  }
}