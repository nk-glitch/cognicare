import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'location_map_page.dart';
import 'calendar_page.dart';
import 'patient_detail_page.dart';

class PatientProfilePage extends StatefulWidget {
  final String patientId;
  final String patientName;

  const PatientProfilePage({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<PatientProfilePage> createState() => _PatientProfilePageState();
}

class _PatientProfilePageState extends State<PatientProfilePage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String firstName = '';
  String lastName  = '';
  String email     = '';
  String phone     = '';
  String address   = '';
  bool _fieldsLoading = true;

  late AnimationController _animController;
  late Animation<double>   _fadeAnimation;
  late Animation<Offset>   _slideAnimation;

  static const _bg      = Color(0xFFF7F4F2);
  static const _card    = Colors.white;
  static const _accent  = Color(0xFF5A7A1A);
  static const _rose    = Color(0xFFD4A5A5);
  static const _text    = Color(0xFF1E1A18);
  static const _subtext = Color(0xFF7A6E6A);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnimation  = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _loadPatientData();
  }

  @override
  void dispose() { _animController.dispose(); super.dispose(); }

  Future<void> _loadPatientData() async {
    try {
      final patientDoc = await _firestore.collection('patients').doc(widget.patientId).get();
      if (patientDoc.exists) {
        final d = patientDoc.data()!;
        firstName = d['firstName'] ?? '';
        lastName  = d['lastName']  ?? '';
        address   = d['address']   ?? '';
      }
      final userDoc = await _firestore.collection('users').doc(widget.patientId).get();
      if (userDoc.exists) {
        final d = userDoc.data()!;
        email = d['email'] ?? '';
        phone = d['phone'] ?? '';
        if (firstName.isEmpty) firstName = d['firstName'] ?? '';
        if (lastName.isEmpty)  lastName  = d['lastName']  ?? '';
      }
      if (firstName.isEmpty && lastName.isEmpty) {
        final parts = widget.patientName.split(' ');
        firstName = parts.isNotEmpty ? parts.first : '';
        lastName  = parts.length > 1 ? parts.sublist(1).join(' ') : '';
      }
    } catch (e) {
      debugPrint('Error loading patient profile: $e');
    } finally {
      if (mounted) { setState(() => _fieldsLoading = false); _animController.forward(); }
    }
  }


  void _goTo(Widget page) {
    Navigator.pushReplacement(context, InstantPushMaterialRoute(
      builder: (_) => page,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final fullName = '${firstName.trim()} ${lastName.trim()}'.trim();
    final initials =
    '${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}'
        .toUpperCase();

    return Scaffold(
      backgroundColor: _bg,
      bottomNavigationBar: _buildBottomNav(),
      body: Stack(
        children: [
          Positioned(top: -60, right: -60,
              child: Container(width: 240, height: 240,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                      color: _rose.withOpacity(0.20)))),
          Positioned(bottom: -80, left: -80,
              child: Container(width: 280, height: 280,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                      color: _accent.withOpacity(0.07)))),
          SafeArea(
            child: Column(
              children: [
                // Top bar — outside animation so it stays static on tab switch
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: _card,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [BoxShadow(
                                color: const Color(0xFFB07A6E).withOpacity(0.12),
                                blurRadius: 12, offset: const Offset(0, 4))],
                          ),
                          child: const Icon(Icons.arrow_back_ios_new_rounded,
                              color: _text, size: 18),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Row(
                        children: [
                          ColoredBox(
                            color: _bg,
                            child: Image.asset(
                              'assets/images/logo_no_text.png',
                              width: 26, height: 26,
                              errorBuilder: (_, __, ___) => const Icon(
                                  Icons.favorite_rounded,
                                  color: Color(0xFFD4A5A5), size: 22),
                            ),
                          ),
                          const SizedBox(width: 7),
                          RichText(text: const TextSpan(children: [
                            TextSpan(text: 'Cogni', style: TextStyle(fontSize: 16,
                                fontWeight: FontWeight.w300, color: Color(0xFF5D4037),
                                letterSpacing: -0.5)),
                            TextSpan(text: 'Care', style: TextStyle(fontSize: 16,
                                fontWeight: FontWeight.w800, color: Color(0xFF5D4037),
                                letterSpacing: -0.5)),
                          ])),
                        ],
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _card, borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(
                              color: const Color(0xFFB07A6E).withOpacity(0.10),
                              blurRadius: 10, offset: const Offset(0, 3))],
                        ),
                        child: Text(DateFormat('MMM d').format(DateTime.now()),
                            style: const TextStyle(fontSize: 13,
                                fontWeight: FontWeight.w700, color: _subtext)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Avatar card
                            Container(
                              width: double.infinity, padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: _card, borderRadius: BorderRadius.circular(24),
                                boxShadow: [BoxShadow(
                                    color: const Color(0xFFB07A6E).withOpacity(0.10),
                                    blurRadius: 40, offset: const Offset(0, 12))],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 64, height: 64,
                                    decoration: const BoxDecoration(
                                        color: Color(0xFFF4E4E1), shape: BoxShape.circle),
                                    child: Center(child: Text(
                                      initials.isNotEmpty ? initials : '?',
                                      style: const TextStyle(fontSize: 22,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFFD4A5A5), letterSpacing: 1),
                                    )),
                                  ),
                                  const SizedBox(width: 18),
                                  Expanded(child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(fullName.isNotEmpty ? fullName : 'Unknown',
                                          style: const TextStyle(fontSize: 22,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF3E2723),
                                              letterSpacing: -0.5, height: 1.1)),
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                            color: _accent.withOpacity(0.10),
                                            borderRadius: BorderRadius.circular(20)),
                                        child: const Text('Patient',
                                            style: TextStyle(fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF5A7A1A),
                                                letterSpacing: 0.3)),
                                      ),
                                    ],
                                  )),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            const _SectionLabel(label: 'ACCOUNT INFO'),
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: _card, borderRadius: BorderRadius.circular(20),
                                boxShadow: [BoxShadow(
                                    color: const Color(0xFFB07A6E).withOpacity(0.10),
                                    blurRadius: 30, offset: const Offset(0, 10))],
                              ),
                              child: Column(children: [
                                _InfoRow(icon: Icons.alternate_email_rounded,
                                    label: 'Email',
                                    value: _fieldsLoading ? '' : (email.isNotEmpty ? email : 'Not provided'),
                                    isLoading: _fieldsLoading,
                                    isFirst: true),
                                const _RowDivider(),
                                _InfoRow(icon: Icons.phone_outlined,
                                    label: 'Phone',
                                    value: _fieldsLoading ? '' : (phone.isNotEmpty ? phone : 'Not provided'),
                                    isLoading: _fieldsLoading),
                                const _RowDivider(),
                                _InfoRow(icon: Icons.home_outlined,
                                    label: 'Address',
                                    value: _fieldsLoading ? '' : (address.isNotEmpty ? address : 'Not provided'),
                                    isLoading: _fieldsLoading,
                                    isLast: true),
                              ]),
                            ),
                            const SizedBox(height: 24),
                            const _SectionLabel(label: 'MEMBERSHIP'),
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity, padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: _card, borderRadius: BorderRadius.circular(18),
                                boxShadow: [BoxShadow(
                                    color: const Color(0xFFB07A6E).withOpacity(0.08),
                                    blurRadius: 20, offset: const Offset(0, 6))],
                              ),
                              child: Row(children: [
                                Container(
                                  width: 38, height: 38,
                                  decoration: BoxDecoration(
                                      color: const Color(0xFFF4E4E1),
                                      borderRadius: BorderRadius.circular(11)),
                                  child: const Icon(Icons.calendar_today_outlined,
                                      size: 18, color: Color(0xFFD4A5A5)),
                                ),
                                const SizedBox(width: 14),
                                Column(crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Member since',
                                        style: TextStyle(fontSize: 12,
                                            color: Color(0xFF8D6E63),
                                            fontWeight: FontWeight.w500)),
                                    const SizedBox(height: 2),
                                    Text(DateFormat('MMMM y').format(DateTime.now()),
                                        style: const TextStyle(fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF3E2723))),
                                  ],
                                ),
                              ]),
                            ),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        boxShadow: [BoxShadow(
            color: const Color(0xFFB07A6E).withOpacity(0.10),
            blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _BottomNavItem(
                icon: Icons.home_rounded, label: 'Home',
                onTap: () {
                  Navigator.pushReplacement(context, InstantPushMaterialRoute(
                    builder: (_) => PatientDetailPage(
                      patientId: widget.patientId,
                      patientName: widget.patientName,
                    ),
                  ));
                },
              ),
              _BottomNavItem(
                icon: Icons.calendar_today_outlined, label: 'Calendar',
                onTap: () => _goTo(CalendarPage(
                    patientId: widget.patientId, patientName: widget.patientName,
                    isCaretaker: true)),
              ),
              _BottomNavItem(
                icon: Icons.location_on_outlined, label: 'Location',
                onTap: () => _goTo(LocationMapPage(
                    patientId: widget.patientId, patientName: widget.patientName)),
              ),
              const _BottomNavItem(
                icon: Icons.person_rounded, label: 'Profile', active: true,
                onTap: _noOp,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _noOp() {}

// ── Widgets ───────────────────────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final IconData icon; final String label; final String value;
  final bool isFirst; final bool isLast; final bool isLoading;
  const _InfoRow({required this.icon, required this.label, required this.value,
    this.isFirst = false, this.isLast = false, this.isLoading = false});
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(18, isFirst ? 20 : 14, 18, isLast ? 20 : 14),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 36, height: 36,
          decoration: BoxDecoration(color: const Color(0xFFFAF6F4),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 18, color: const Color(0xFFD4A5A5))),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF8D6E63),
                fontWeight: FontWeight.w500)),
            const SizedBox(height: 3),
            if (isLoading)
              Container(
                height: 14, width: 140,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE5E2),
                  borderRadius: BorderRadius.circular(6),
                ),
              )
            else
              Text(value, style: const TextStyle(fontSize: 15,
                  fontWeight: FontWeight.w600, color: Color(0xFF3E2723))),
          ])),
    ]),
  );
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();
  @override
  Widget build(BuildContext context) => const Divider(
      height: 1, indent: 18, endIndent: 18, color: Color(0xFFF0E8E5));
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});
  @override
  Widget build(BuildContext context) => Text(label,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          color: Color(0xFF8D6E63), letterSpacing: 1.2));
}

class _BottomNavItem extends StatelessWidget {
  final IconData icon; final String label;
  final VoidCallback onTap; final bool active;
  const _BottomNavItem({required this.icon, required this.label,
    required this.onTap, this.active = false});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 24,
          color: active ? const Color(0xFF5A7A1A) : const Color(0xFFBDB0AC)),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
          color: active ? const Color(0xFF5A7A1A) : const Color(0xFFBDB0AC))),
    ]),
  );
}