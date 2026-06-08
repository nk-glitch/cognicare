import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import 'auth/login_page.dart';
import 'caretaker/location_map_page.dart';
import 'caretaker/calendar_page.dart';
import 'caretaker/caretaker_home_page.dart';

class ProfilePage extends StatefulWidget {
  final bool isCaretaker;
  final String? viewingPatientId;
  final String? viewingPatientName;

  const ProfilePage({
    super.key,
    required this.isCaretaker,
    this.viewingPatientId,
    this.viewingPatientName,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String firstName = '';
  String lastName = '';
  String email = '';
  String phone = '';
  String address = '';
  bool _isLoading = true;

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnimation = CurvedAnimation(
        parent: _animController, curve: Curves.easeOut);
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );
    _loadUserData();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      if (widget.viewingPatientId != null) {
        final patientDoc = await _firestore
            .collection('patients')
            .doc(widget.viewingPatientId)
            .get();
        if (patientDoc.exists) {
          final data = patientDoc.data()!;
          firstName = data['firstName'] ?? widget.viewingPatientName ?? '';
          lastName = data['lastName'] ?? '';
          address = data['address'] ?? '';
        } else {
          final parts = (widget.viewingPatientName ?? '').split(' ');
          firstName = parts.isNotEmpty ? parts.first : '';
          lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
        }

        // Fetch email and phone from users collection
        final userDoc = await _firestore
            .collection('users')
            .doc(widget.viewingPatientId)
            .get();
        if (userDoc.exists) {
          final data = userDoc.data()!;
          email = data['email'] ?? '';
          phone = data['phone'] ?? '';
          if (firstName.isEmpty) firstName = data['firstName'] ?? '';
          if (lastName.isEmpty) lastName = data['lastName'] ?? '';
        }
        return;
      }

      final user = _authService.currentUser;
      if (user != null) {
        email = user.email ?? '';
        final userData = await _authService.getUserData(user.uid);
        if (userData != null) {
          firstName = userData['firstName'] ?? '';
          lastName = userData['lastName'] ?? '';
          phone = userData['phone'] ?? '';
        }
        if (!widget.isCaretaker) {
          final patientData = await _authService.getPatientData(user.uid);
          if (patientData != null) {
            address = patientData['address'] ?? '';
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _animController.forward();
      }
    }
  }

  void _showSignOutConfirmation() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: const Text('Sign out?',
            style: TextStyle(
                fontWeight: FontWeight.w700, color: Color(0xFF3E2723))),
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
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                      (_) => false,
                );
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFFAF6F4),
        body: Center(
            child: CircularProgressIndicator(color: Color(0xFF5A7A1A))),
      );
    }

    final fullName = '${firstName.trim()} ${lastName.trim()}'.trim();
    final initials =
    '${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}'
        .toUpperCase();
    final isViewingPatient = widget.viewingPatientId != null;
    final roleLabel = isViewingPatient ? 'Patient' : (widget.isCaretaker ? 'Caretaker' : 'Patient');

    return Scaffold(
      backgroundColor: const Color(0xFFFAF6F4),
      bottomNavigationBar:
      widget.isCaretaker ? _buildBottomNav() : null,
      body: Stack(
        children: [
          // Background blobs
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFE8C9C0).withOpacity(0.35),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
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
              child: SlideTransition(
                position: _slideAnimation,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.popUntil(context, (route) => route.isFirst),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFB07A6E)
                                        .withOpacity(0.12),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: Color(0xFF5D4037),
                                size: 18,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          // Logo
                          Row(
                            children: [
                              Image.asset(
                                'assets/images/logo_no_text.png',
                                width: 22,
                                height: 22,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.favorite_rounded,
                                  color: Color(0xFFD4A5A5),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 6),
                              RichText(
                                text: const TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'Cogni',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w300,
                                        color: Color(0xFF5D4037),
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    TextSpan(
                                      text: 'Care',
                                      style: TextStyle(
                                        fontSize: 15,
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
                          // Sign out button - hidden when viewing a patient's profile
                          if (!isViewingPatient)
                            GestureDetector(
                              onTap: _showSignOutConfirmation,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFB07A6E)
                                          .withOpacity(0.10),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: const [
                                    Icon(Icons.logout_rounded,
                                        size: 15, color: Color(0xFF8D6E63)),
                                    SizedBox(width: 6),
                                    Text(
                                      'Sign out',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF8D6E63),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [

                            // ── Avatar + name card ───────────────
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFB07A6E)
                                        .withOpacity(0.10),
                                    blurRadius: 40,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFF4E4E1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        initials.isNotEmpty ? initials : '?',
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFFD4A5A5),
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 18),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          fullName.isNotEmpty
                                              ? fullName
                                              : 'Unknown',
                                          style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF3E2723),
                                            letterSpacing: -0.5,
                                            height: 1.1,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF5A7A1A)
                                                .withOpacity(0.10),
                                            borderRadius:
                                            BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            roleLabel,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF5A7A1A),
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 24),

                            const _SectionLabel(label: 'ACCOUNT INFO'),
                            const SizedBox(height: 10),

                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFB07A6E)
                                        .withOpacity(0.10),
                                    blurRadius: 30,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  _InfoRow(
                                    icon: Icons.alternate_email_rounded,
                                    label: 'Email',
                                    value: email.isNotEmpty
                                        ? email
                                        : 'Not provided',
                                    isFirst: true,
                                  ),
                                  const _RowDivider(),
                                  _InfoRow(
                                    icon: Icons.phone_outlined,
                                    label: 'Phone',
                                    value: phone.isNotEmpty
                                        ? phone
                                        : 'Not provided',
                                  ),
                                  if (!widget.isCaretaker || isViewingPatient) ...[
                                    const _RowDivider(),
                                    _InfoRow(
                                      icon: Icons.home_outlined,
                                      label: 'Address',
                                      value: address.isNotEmpty
                                          ? address
                                          : 'Not provided',
                                      isLast: true,
                                    ),
                                  ] else
                                    const SizedBox(height: 4),
                                ],
                              ),
                            ),

                            const SizedBox(height: 24),

                            const _SectionLabel(label: 'MEMBERSHIP'),
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFB07A6E)
                                        .withOpacity(0.08),
                                    blurRadius: 20,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF4E4E1),
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    child: const Icon(
                                      Icons.calendar_today_outlined,
                                      size: 18,
                                      color: Color(0xFFD4A5A5),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Member since',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF8D6E63),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        DateFormat('MMMM y')
                                            .format(DateTime.now()),
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF3E2723),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom nav (caretaker only) ───────────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB07A6E).withOpacity(0.10),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _BottomNavItem(
                icon: Icons.home_rounded,
                label: 'Home',
                onTap: () => Navigator.of(context).pop(),
              ),
              _BottomNavItem(
                icon: Icons.calendar_today_outlined,
                label: 'Calendar',
                onTap: () {
                  Navigator.popUntil(context, (route) => route.isFirst);
                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) => CalendarPage(
                        patientId: widget.viewingPatientId ?? '',
                        patientName: widget.viewingPatientName ?? '',
                        isCaretaker: true,
                      ),
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                    ),
                  );
                },
              ),
              _BottomNavItem(
                icon: Icons.location_on_outlined,
                label: 'Location',
                onTap: () {
                  Navigator.popUntil(context, (route) => route.isFirst);
                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) => LocationMapPage(
                        patientId: widget.viewingPatientId ?? '',
                        patientName: widget.viewingPatientName ?? '',
                      ),
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                    ),
                  );
                },
              ),
              _BottomNavItem(
                icon: Icons.person_outline_rounded,
                label: 'Profile',
                active: true,
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Info row ──────────────────────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isFirst;
  final bool isLast;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          18, isFirst ? 20 : 14, 18, isLast ? 20 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFFAF6F4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: const Color(0xFFD4A5A5)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8D6E63),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3E2723),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Divider ───────────────────────────────────────────────────────────────────
class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      indent: 18,
      endIndent: 18,
      color: Color(0xFFF0E8E5),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

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

// ── Bottom nav item ───────────────────────────────────────────────────────────
class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 24,
            color: active
                ? const Color(0xFF5A7A1A)
                : const Color(0xFFBDB0AC),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: active
                  ? const Color(0xFF5A7A1A)
                  : const Color(0xFFBDB0AC),
            ),
          ),
        ],
      ),
    );
  }
}