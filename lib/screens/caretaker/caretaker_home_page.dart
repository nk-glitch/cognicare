import 'package:flutter/material.dart';
import 'dart:async';
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

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  String caretakerFirstName = '';
  String caretakerName = '';
  List<Map<String, dynamic>> patients = [];
  bool _isLoading = true;
  int _unreadAlertCount = 0;

  final List<StreamSubscription> _reminderSubscriptions = [];

  // Palette — slightly different from patient side to feel more "pro"
  static const _bg = Color(0xFFF7F4F2);
  static const _card = Colors.white;
  static const _accent = Color(0xFF5A7A1A);
  static const _accentSoft = Color(0xFFEEF3E6);
  static const _rose = Color(0xFFD4A5A5);
  static const _roseSoft = Color(0xFFF4E4E1);
  static const _text = Color(0xFF1E1A18);
  static const _subtext = Color(0xFF7A6E6A);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
    _fadeAnimation = CurvedAnimation(
        parent: _animController, curve: Curves.easeOut);
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(
          CurvedAnimation(
              parent: _animController, curve: Curves.easeOutCubic),
        );
    _loadCaretakerData();
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    await NotificationService.initialize();
    await NotificationService.saveFCMToken();
    _listenForUnreadCount();
  }

  void _listenForUnreadCount() {
    final user = _authService.currentUser;
    if (user == null) return;
    _firestore
        .collection('caretaker_alerts')
        .where('caretakerId', isEqualTo: user.uid)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      final count =
          snapshot.docs.where((d) => d.data()['isRead'] != true).length;
      setState(() => _unreadAlertCount = count);
    });
  }

  Future<void> _loadCaretakerData() async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      final userData = await _authService.getUserData(user.uid);
      if (userData != null) {
        caretakerFirstName = userData['firstName'] ?? '';
        caretakerName =
        '${userData['firstName']} ${userData['lastName']}';
      }

      final relSnap = await _firestore
          .collection('patient_caretaker_relationships')
          .where('caretakerId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'accepted')
          .get();

      for (final sub in _reminderSubscriptions) sub.cancel();
      _reminderSubscriptions.clear();

      List<Map<String, dynamic>> loaded = [];
      for (var doc in relSnap.docs) {
        final patientId = doc.data()['patientId'] as String;
        final patientUserData = await _authService.getUserData(patientId);
        final patientData = await _authService.getPatientData(patientId);

        final name = patientUserData != null
            ? '${patientUserData['firstName']} ${patientUserData['lastName']}'
            : 'Patient';

        loaded.add({
          'patientId': patientId,
          'name': name,
          'location': patientData?['address'] ?? 'No address set',
          'reminders': <Map<String, dynamic>>[],
          'completedCount': 0,
        });
      }

      setState(() {
        patients = loaded;
        _isLoading = false;
      });
      _animController.forward();

      // Live reminder streams
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

      for (var i = 0; i < loaded.length; i++) {
        final patientId = loaded[i]['patientId'] as String;

        final sub = _firestore
            .collection('reminders')
            .where('patientId', isEqualTo: patientId)
            .where('time',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
            .where('time',
            isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
            .snapshots()
            .listen((snapshot) {
          if (!mounted) return;
          final allReminders = snapshot.docs
              .where((doc) => doc.data()['isSnoozed'] != true)
              .map((doc) {
            final d = doc.data();
            return {
              'title': d['title'] as String? ?? '',
              'time': d['time'] as Timestamp?,
              'completed': d['completed'] == true,
            };
          }).toList()
            ..sort((a, b) {
              final ta = a['time'] as Timestamp?;
              final tb = b['time'] as Timestamp?;
              if (ta == null || tb == null) return 0;
              return ta.compareTo(tb);
            });

          final completed =
              allReminders.where((r) => r['completed'] == true).length;

          final idx =
          patients.indexWhere((p) => p['patientId'] == patientId);
          if (idx != -1 && mounted) {
            setState(() {
              patients[idx]['reminders'] = allReminders;
              patients[idx]['completedCount'] = completed;
            });
          }
        });

        _reminderSubscriptions.add(sub);
      }
    } catch (e, st) {
      debugPrint('Error loading caretaker data: $e\n$st');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshData() async {
    setState(() => _isLoading = true);
    _animController.reset();
    await _loadCaretakerData();
  }

  @override
  void dispose() {
    for (final sub in _reminderSubscriptions) sub.cancel();
    _animController.dispose();
    super.dispose();
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  // Colour for patient avatar based on name hash
  Color _avatarColor(String name) {
    final colors = [
      const Color(0xFF7B9E6B),
      const Color(0xFF8FA9C9),
      const Color(0xFFD4A5A5),
      const Color(0xFFB5977A),
      const Color(0xFF9B8EC4),
    ];
    return colors[name.hashCode.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // Subtle background blobs
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _rose.withOpacity(0.18),
              ),
            ),
          ),
          Positioned(
            bottom: 60,
            left: -70,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accent.withOpacity(0.06),
              ),
            ),
          ),

          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: Column(
                  children: [
                    _buildTopBar(),
                    _buildGreetingStrip(),
                    Expanded(
                      child: _isLoading
                          ? const Center(
                          child: CircularProgressIndicator(
                              color: _accent))
                          : _buildBody(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  // ── Top bar ──────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          // Logo + wordmark
          Row(
            children: [
              ColoredBox(
                color: _bg,
                child: Image.asset(
                  'assets/images/logo_no_text.png',
                  width: 26,
                  height: 26,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.favorite_rounded,
                    color: _rose,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              RichText(
                text: const TextSpan(
                  children: [
                    TextSpan(
                      text: 'Cogni',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w300,
                        color: Color(0xFF5D4037),
                        letterSpacing: -0.5,
                      ),
                    ),
                    TextSpan(
                      text: 'Care',
                      style: TextStyle(
                        fontSize: 16,
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
          // Inbox bell
          Stack(
            clipBehavior: Clip.none,
            children: [
              _IconBtn(
                icon: Icons.notifications_none_rounded,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                      const InboxPage(isCaretaker: true)),
                ),
              ),
              if (_unreadAlertCount > 0)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE57373),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        _unreadAlertCount > 9
                            ? '9+'
                            : '$_unreadAlertCount',
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
          _IconBtn(
            icon: Icons.person_outline_rounded,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                    const ProfilePage(isCaretaker: true)),
              );
              _refreshData();
            },
          ),
          const SizedBox(width: 8),
          // Sign out
          _IconBtn(
            icon: Icons.logout_rounded,
            onTap: _showSignOutConfirmation,
          ),
        ],
      ),
    );
  }

  // ── Greeting strip ────────────────────────────────────────────────────────
  Widget _buildGreetingStrip() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_greeting,',
                  style: const TextStyle(
                    fontSize: 14,
                    color: _subtext,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  caretakerFirstName.isNotEmpty
                      ? caretakerFirstName
                      : caretakerName,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: _text,
                    letterSpacing: -0.8,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          // Stats pill
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFB07A6E).withOpacity(0.10),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.people_outline_rounded,
                    size: 16, color: _accent),
                const SizedBox(width: 6),
                Text(
                  '${patients.length} ${patients.length == 1 ? 'patient' : 'patients'}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _accent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Body ─────────────────────────────────────────────────────────────────
  Widget _buildBody() {
    if (patients.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshData,
        color: _accent,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.55,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color:
                          const Color(0xFFB07A6E).withOpacity(0.10),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.people_outline_rounded,
                        size: 32, color: _rose),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No patients yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Tap + Add Patient to send a connection request',
                    style: TextStyle(fontSize: 14, color: _subtext),
                    textAlign: TextAlign.center,
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
      color: _accent,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: patients.length,
        itemBuilder: (_, i) {
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: Duration(milliseconds: 250 + i * 80),
            curve: Curves.easeOutCubic,
            builder: (_, v, child) => Opacity(
              opacity: v,
              child: Transform.translate(
                  offset: Offset(0, 16 * (1 - v)), child: child),
            ),
            child: _PatientCard(
              patient: patients[i],
              avatarColor: _avatarColor(patients[i]['name'] as String),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  settings: const RouteSettings(name: '/patient_detail'),
                  builder: (_) => PatientDetailPage(
                    patientId: patients[i]['patientId'] as String,
                    patientName: patients[i]['name'] as String,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── FAB ───────────────────────────────────────────────────────────────────
  Widget _buildFAB() {
    return FloatingActionButton.extended(
      onPressed: _showAddPatientDialog,
      backgroundColor: _accent,
      elevation: 4,
      icon: const Icon(Icons.person_add_rounded, color: Colors.white, size: 20),
      label: const Text(
        'Add Patient',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
    );
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────
  void _showSignOutConfirmation() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: const Text('Sign out?',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF3E2723))),
        content: const Text('Are you sure you want to sign out?',
            style: TextStyle(color: _subtext)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: _subtext)),
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
              backgroundColor: _accent,
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

  void _showAddPatientDialog() {
    final phoneController = TextEditingController();
    bool isSearching = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: _accentSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.person_add_rounded,
                      color: _accent, size: 24),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Add a Patient',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _text,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Enter their phone number to send a connection request.",
                  style: TextStyle(
                      fontSize: 14, color: _subtext, height: 1.4),
                ),
                const SizedBox(height: 20),
                // Phone field
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Phone number',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF5D4037),
                      ),
                    ),
                    const SizedBox(height: 7),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(
                          fontSize: 15,
                          color: _text,
                          fontWeight: FontWeight.w500),
                      decoration: InputDecoration(
                        hintText: '(555) 123-4567',
                        hintStyle: const TextStyle(
                            color: Color(0xFFBDB0AC), fontSize: 15),
                        prefixIcon: const Icon(Icons.phone_outlined,
                            color: _rose, size: 20),
                        filled: true,
                        fillColor: const Color(0xFFFAF6F4),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFFEDE5E2), width: 1.5),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFFEDE5E2), width: 1.5),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: _accent, width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: TextButton.styleFrom(
                        foregroundColor: _subtext,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                      child: const Text('Cancel',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        onPressed: isSearching
                            ? null
                            : () => _sendRequest(
                            phoneController.text.trim(),
                            ctx,
                                (v) => setDialogState(
                                    () => isSearching = v)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                          _accent.withOpacity(0.5),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: isSearching
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white),
                        )
                            : const Text('Send Request',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sendRequest(
      String phone,
      BuildContext dialogContext,
      void Function(bool) setSearching,
      ) async {
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        _snack('Please enter a phone number'),
      );
      return;
    }
    setSearching(true);
    try {
      final usersSnap = await _firestore
          .collection('users')
          .where('phone', isEqualTo: phone)
          .where('userType', isEqualTo: 'patient')
          .limit(1)
          .get();

      if (usersSnap.docs.isEmpty) {
        if (mounted) {
          Navigator.pop(dialogContext);
          ScaffoldMessenger.of(context)
              .showSnackBar(_snack('No patient found with this number'));
        }
        return;
      }

      final patientId = usersSnap.docs.first.id;
      final currentUserId = _authService.currentUser!.uid;

      final existing = await _firestore
          .collection('patient_caretaker_relationships')
          .where('patientId', isEqualTo: patientId)
          .where('caretakerId', isEqualTo: currentUserId)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        if (mounted) {
          Navigator.pop(dialogContext);
          ScaffoldMessenger.of(context)
              .showSnackBar(_snack('Request already sent'));
        }
        return;
      }

      await _firestore.collection('patient_caretaker_relationships').add({
        'patientId': patientId,
        'caretakerId': currentUserId,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(dialogContext);
        ScaffoldMessenger.of(context).showSnackBar(
          _snack('Request sent — waiting for patient to accept',
              success: true),
        );
      }
    } catch (e) {
      debugPrint('Error sending request: $e');
      if (mounted) {
        Navigator.pop(dialogContext);
        ScaffoldMessenger.of(context)
            .showSnackBar(_snack('Something went wrong, try again'));
      }
    } finally {
      setSearching(false);
    }
  }

  SnackBar _snack(String msg, {bool success = false}) => SnackBar(
    content: Text(msg,
        style: const TextStyle(fontWeight: FontWeight.w600)),
    backgroundColor: success ? _accent : _subtext,
    behavior: SnackBarBehavior.floating,
    shape:
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    margin: const EdgeInsets.all(16),
  );
}

// ── Patient card ──────────────────────────────────────────────────────────────
class _PatientCard extends StatelessWidget {
  final Map<String, dynamic> patient;
  final Color avatarColor;
  final VoidCallback onTap;

  static const _text = Color(0xFF1E1A18);
  static const _subtext = Color(0xFF7A6E6A);
  static const _accent = Color(0xFF5A7A1A);

  const _PatientCard({
    required this.patient,
    required this.avatarColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final String name = patient['name'] as String? ?? 'Unknown';
    final String location = patient['location'] as String? ?? '';
    final List<dynamic> reminders = patient['reminders'] as List<dynamic>? ?? [];
    final int completed = patient['completedCount'] as int? ?? 0;
    final int total = reminders.length;

    final initials = name
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();

    // Progress
    final double progress = total > 0 ? completed / total : 0.0;
    final upcomingReminders = reminders
        .where((r) => (r as Map)['completed'] != true)
        .take(3)
        .toList();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFB07A6E).withOpacity(0.09),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Patient header ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: Row(
                children: [
                  // Avatar
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: avatarColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: _text,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined,
                                size: 13, color: _subtext),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                location.isEmpty
                                    ? 'No address set'
                                    : location,
                                style: const TextStyle(
                                    fontSize: 12, color: _subtext),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Chevron
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F4F2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: _subtext,
                    ),
                  ),
                ],
              ),
            ),

            // ── Progress bar ────────────────────────────────────
            if (total > 0) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 5,
                          backgroundColor:
                          const Color(0xFFEDE5E2),
                          valueColor:
                          const AlwaysStoppedAnimation<Color>(
                              _accent),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '$completed/$total done',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: progress == 1.0
                            ? _accent
                            : _subtext,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Divider
            const Divider(
                height: 1, color: Color(0xFFF0EBE8)),

            // ── Reminders section ───────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        "TODAY",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _subtext,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (total > 3)
                        Text(
                          '+${total - 3} more',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _accent,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (upcomingReminders.isEmpty)
                    Row(
                      children: [
                        const Icon(
                            Icons.check_circle_outline_rounded,
                            size: 16,
                            color: _accent),
                        const SizedBox(width: 8),
                        Text(
                          total == 0
                              ? 'No reminders scheduled'
                              : 'All reminders complete!',
                          style: const TextStyle(
                            fontSize: 13,
                            color: _subtext,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    )
                  else
                    ...upcomingReminders.map((r) {
                      final reminder = r as Map<String, dynamic>;
                      final ts = reminder['time'] as Timestamp?;
                      final timeStr = ts != null
                          ? DateFormat('h:mm a').format(ts.toDate())
                          : '';
                      return Padding(
                        padding:
                        const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.only(
                                  right: 10, top: 1),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color:
                                avatarColor.withOpacity(0.7),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                reminder['title'] as String? ??
                                    '',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: _text,
                                ),
                              ),
                            ),
                            if (timeStr.isNotEmpty)
                              Text(
                                timeStr,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: _subtext,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Small icon button ─────────────────────────────────────────────────────────
class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
      ),
    );
  }
}