import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';
import '../../constants/legal.dart';
import '../../services/notification_service.dart';
import 'location_map_page.dart';
import 'calendar_page.dart';
import 'caretaker_home_page.dart';
import 'patient_profile_page.dart';

class InstantPushMaterialRoute<T> extends MaterialPageRoute<T> {
  InstantPushMaterialRoute({required super.builder});

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    if (animation.status == AnimationStatus.forward ||
        animation.status == AnimationStatus.dismissed) {
      return child;
    }
    return super.buildTransitions(context, animation, secondaryAnimation, child);
  }
}

class PatientDetailPage extends StatefulWidget {
  final String patientId;
  final String patientName;

  const PatientDetailPage({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<PatientDetailPage> createState() => _PatientDetailPageState();
}

class _PatientDetailPageState extends State<PatientDetailPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Map<String, dynamic>? _patientData;
  List<Map<String, dynamic>> _reminders = [];
  bool _isLoading = true;

  // Heart rate
  int? _heartRate;
  DateTime? _heartRateUpdatedAt;
  bool _hasWatchData = false; // True once Firestore confirms the field exists
  StreamSubscription<DocumentSnapshot>? _patientSub;

  // HR alert state
  static const _hrElevatedThreshold = 100; // bpm — above normal resting range
  static const _hrAlertCooldown = Duration(minutes: 10);
  bool _hrCurrentlyElevated = false;
  DateTime? _lastHrAlertTime;

  // Colors
  static const _bg = Color(0xFFF7F4F2);
  static const _card = Colors.white;
  static const _accent = Color(0xFF5A7A1A);
  static const _accentSoft = Color(0xFFEEF3E6);
  static const _rose = Color(0xFFD4A5A5);
  static const _roseSoft = Color(0xFFF4E4E1);
  static const _text = Color(0xFF1E1A18);
  static const _subtext = Color(0xFF7A6E6A);
  static const _divider = Color(0xFFF0EBE8);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnimation =
        CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );
    _loadPatientData();
  }

  @override
  void dispose() {
    _animController.dispose();
    _patientSub?.cancel();
    super.dispose();
  }

  // ── Notifications ──────────────────────────────────────────────────────────

  /// runs at most once per heart rate cooldown to avoid repeated/spamming alerts.
  Future<void> _checkHeartRateAlert(int bpm) async {
    final isElevated = bpm > _hrElevatedThreshold;

    if (!isElevated) {
      _hrCurrentlyElevated = false;
      return;
    }


    if (_hrCurrentlyElevated) {
      final lastAlert = _lastHrAlertTime;
      if (lastAlert != null &&
          DateTime.now().difference(lastAlert) < _hrAlertCooldown) {
        return;
      }
    }

    _hrCurrentlyElevated = true;
    _lastHrAlertTime     = DateTime.now();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          backgroundColor: const Color(0xFFE57373),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          content: Row(
            children: [
              const Icon(Icons.favorite_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${widget.patientName}\'s heart rate is elevated at $bpm bpm',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // System notification
    await NotificationService.flutterLocalNotificationsPlugin.show(
      id:    widget.patientId.hashCode,
      title: '❤️ Elevated Heart Rate',
      body:  '${widget.patientName}\'s heart rate is $bpm bpm — above the normal resting range.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'reminder_channel',        // reuse the existing high-importance channel
          'Reminder Notifications',
          channelDescription: 'Notifications for medication and task reminders',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
      ),
    );
  }

  // ── Data ───────────────────────────────────────────────────────────────────

  Future<void> _loadPatientData() async {
    // Cancel any existing subscription first
    await _patientSub?.cancel();

    //heart rate updates live
    _patientSub = _firestore
        .collection('patients')
        .doc(widget.patientId)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      if (snap.exists) {
        final data = snap.data()!;
        final newHr = data['heartRate'] as int?;
        setState(() {
          _patientData = data;
          _heartRate = newHr;
          final ts = data['heartRateUpdatedAt'] as Timestamp?;
          _heartRateUpdatedAt = ts?.toDate();
          _hasWatchData = data.containsKey('heartRate');
        });
        if (newHr != null) _checkHeartRateAlert(newHr);
      }
    }, onError: (e) => debugPrint('Patient stream error: $e'));

    try {
      final remindersSnapshot = await _firestore
          .collection('reminders')
          .where('patientId', isEqualTo: widget.patientId)
          .orderBy('time')
          .get();

      if (mounted) {
        setState(() {
          _reminders = remindersSnapshot.docs
              .map((doc) => {'id': doc.id, ...doc.data()})
              .toList();
          _isLoading = false;
        });
        _animController.forward();
      }
    } catch (e) {
      debugPrint('Error loading patient data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRefresh() async {
    _animController.reset();
    await _loadPatientData();
  }

  List<Map<String, dynamic>> get _todaysReminders {
    final today = DateTime.now();
    return _reminders.where((r) {
      final t = (r['time'] as Timestamp?)?.toDate();
      return t != null &&
          t.year == today.year &&
          t.month == today.month &&
          t.day == today.day &&
          r['isSnoozed'] != true;
    }).toList();
  }

  int get _completedToday =>
      _todaysReminders.where((r) => r['completed'] == true).length;

  Color _avatarColor() {
    final colors = [
      const Color(0xFF7B9E6B),
      const Color(0xFF8FA9C9),
      const Color(0xFFD4A5A5),
      const Color(0xFFB5977A),
      const Color(0xFF9B8EC4),
    ];
    return colors[widget.patientName.hashCode.abs() % colors.length];
  }

  String get _initials => widget.patientName
      .split(' ')
      .map((w) => w.isNotEmpty ? w[0] : '')
      .take(2)
      .join()
      .toUpperCase();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // Background blobs
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _rose.withOpacity(0.15),
              ),
            ),
          ),
          Positioned(
            bottom: 80,
            left: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accent.withOpacity(0.06),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: _isLoading
                      ? const Center(
                      child: CircularProgressIndicator(color: _accent))
                      : FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: RefreshIndicator(
                        onRefresh: _handleRefresh,
                        color: _accent,
                        child: SingleChildScrollView(
                          physics:
                          const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(
                              20, 8, 20, 32),
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              _buildPatientHeader(),
                              const SizedBox(height: 16),
                              _buildHeartRateCard(),
                              const SizedBox(height: 20),
                              _buildRemindersCard(),
                              const SizedBox(height: 20),
                              _buildQuickActions(),
                            ],
                          ),
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
      floatingActionButton: _buildFAB(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFB07A6E).withOpacity(0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: _text, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          // Logo
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
                    color: Color(0xFFD4A5A5),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFB07A6E).withOpacity(0.10),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Text(
              DateFormat('MMM d').format(DateTime.now()),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _subtext,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Patient header card ────────────────────────────────────────────────────
  Widget _buildPatientHeader() {
    final total = _todaysReminders.length;
    final done = _completedToday;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB07A6E).withOpacity(0.10),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: _avatarColor(),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: Text(
                _initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
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
                  widget.patientName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _text,
                    letterSpacing: -0.4,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: _accentSoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Patient',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$done/$total',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _accent,
                  letterSpacing: -0.5,
                ),
              ),
              const Text(
                'done today',
                style: TextStyle(
                    fontSize: 11,
                    color: _subtext,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Heart rate card ────────────────────────────────────────────────────────
  Widget _buildHeartRateCard() {
    // show when it was last updated
    String lastUpdated = '';
    if (_heartRateUpdatedAt != null) {
      final diff = DateTime.now().difference(_heartRateUpdatedAt!);
      if (diff.inMinutes < 1) {
        lastUpdated = 'Just now';
      } else if (diff.inMinutes < 60) {
        lastUpdated = '${diff.inMinutes}m ago';
      } else if (diff.inHours < 24) {
        lastUpdated = '${diff.inHours}h ago';
      } else {
        lastUpdated = DateFormat('MMM d, h:mm a').format(_heartRateUpdatedAt!);
      }
    }

    final bool noWatch   = !_hasWatchData;
    final bool elevated  = (_heartRate ?? 0) > _hrElevatedThreshold;

    // Colours shift to warning red when HR is elevated
    final iconBg    = noWatch
        ? const Color(0xFFF0EBE8)
        : elevated
        ? const Color(0xFFFFEBEB)
        : _roseSoft;
    final iconColor = noWatch
        ? _subtext
        : elevated
        ? const Color(0xFFE57373)
        : _rose;
    final bpmColor  = elevated ? const Color(0xFFE57373) : _rose;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(22),
        border: elevated
            ? Border.all(color: const Color(0xFFE57373).withOpacity(0.40), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: elevated
                ? const Color(0xFFE57373).withOpacity(0.15)
                : const Color(0xFFB07A6E).withOpacity(0.10),
            blurRadius: 30,
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
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  noWatch ? Icons.watch_off_outlined : Icons.favorite_rounded,
                  color: iconColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: noWatch
                    ? const Text(
                  'Patient does not have a watch linked to this account.',
                  style: TextStyle(
                    fontSize: 13,
                    color: _subtext,
                    fontStyle: FontStyle.italic,
                    height: 1.4,
                  ),
                )
                    : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Heart Rate',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _subtext,
                          ),
                        ),
                        if (elevated) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFEBEB),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '⚠ Elevated',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFE57373),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _heartRate != null ? '$_heartRate' : '--',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: bpmColor,
                            letterSpacing: -0.5,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            'bpm',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: bpmColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (lastUpdated.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        elevated
                            ? 'Updated $lastUpdated · above normal (>$_hrElevatedThreshold bpm)'
                            : 'Updated $lastUpdated · syncs every 5 min',
                        style: TextStyle(
                          fontSize: 11,
                          color: elevated
                              ? const Color(0xFFE57373).withOpacity(0.8)
                              : _subtext,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            kMedicalDisclaimer,
            style: TextStyle(
              fontSize: 11,
              color: _subtext.withOpacity(0.85),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  // ── Today's reminders card ─────────────────────────────────────────────────
  Widget _buildRemindersCard() {
    final reminders = _todaysReminders;
    final total = reminders.length;
    final done = _completedToday;
    final progress = total > 0 ? done / total : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB07A6E).withOpacity(0.10),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _roseSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                  const Icon(Icons.alarm_rounded, size: 18, color: _rose),
                ),
                const SizedBox(width: 12),
                const Text(
                  "Today's Reminders",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _text,
                    letterSpacing: -0.2,
                  ),
                ),
                const Spacer(),
                Text(
                  '$total total',
                  style: const TextStyle(
                    fontSize: 12,
                    color: _subtext,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          if (total > 0) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 5,
                        backgroundColor: const Color(0xFFEDE5E2),
                        valueColor:
                        const AlwaysStoppedAnimation<Color>(_accent),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    progress == 1.0 ? 'All done!' : '$done/$total done',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: progress == 1.0 ? _accent : _subtext,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),
          const Divider(height: 1, color: _divider),

          if (reminders.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: const [
                  Icon(Icons.check_circle_outline_rounded,
                      size: 18, color: _accent),
                  SizedBox(width: 10),
                  Text(
                    'No reminders scheduled for today',
                    style: TextStyle(
                        fontSize: 14,
                        color: _subtext,
                        fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            )
          else
            ...reminders.asMap().entries.map((entry) {
              final i = entry.key;
              final reminder = entry.value;
              final time = (reminder['time'] as Timestamp?)?.toDate();
              final timeStr =
              time != null ? DateFormat('h:mm a').format(time) : '';
              final desc = reminder['description'] as String? ?? '';
              final isCompleted = reminder['completed'] == true;
              final isLast = i == reminders.length - 1;

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isCompleted
                                ? _accent
                                : _rose.withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                reminder['title'] ?? 'Untitled',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color:
                                  isCompleted ? _subtext : _text,
                                  decoration: isCompleted
                                      ? TextDecoration.lineThrough
                                      : TextDecoration.none,
                                ),
                              ),
                              if (desc.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  desc,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: _subtext,
                                      height: 1.4),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (timeStr.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: isCompleted
                                  ? _accentSoft
                                  : const Color(0xFFF7F4F2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              timeStr,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color:
                                isCompleted ? _accent : _subtext,
                              ),
                            ),
                          ),
                        if (isCompleted) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.check_rounded,
                              size: 16, color: _accent),
                        ],
                      ],
                    ),
                  ),
                  if (!isLast)
                    const Divider(
                        height: 1,
                        indent: 42,
                        endIndent: 20,
                        color: _divider),
                ],
              );
            }),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _showReminderSheet,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text(
                  'Add Reminder',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Quick actions ──────────────────────────────────────────────────────────
  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'QUICK ACCESS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _subtext,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ActionTile(
                icon: Icons.calendar_month_rounded,
                label: 'Calendar',
                sublabel: 'All reminders',
                color: const Color(0xFF8FA9C9),
                colorSoft: const Color(0xFFEAF1F8),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CalendarPage(
                      patientId: widget.patientId,
                      patientName: widget.patientName,
                      isCaretaker: true,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionTile(
                icon: Icons.location_on_rounded,
                label: 'Location',
                sublabel: 'Live map',
                color: _accent,
                colorSoft: _accentSoft,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LocationMapPage(
                      patientId: widget.patientId,
                      patientName: widget.patientName,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── FAB ────────────────────────────────────────────────────────────────────
  Widget _buildFAB() {
    return FloatingActionButton(
      onPressed: _showReminderSheet,
      backgroundColor: _accent,
      elevation: 4,
      child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
    );
  }

  // ── Bottom nav ─────────────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: _card,
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
              _NavItem(
                icon: Icons.home_rounded,
                label: 'Home',
                onTap: () {},
                highlight: true,
              ),
              _NavItem(
                icon: Icons.calendar_today_outlined,
                label: 'Calendar',
                onTap: () {
                  Navigator.pushReplacement(context, InstantPushMaterialRoute(
                    builder: (_) => CalendarPage(
                      patientId: widget.patientId,
                      patientName: widget.patientName,
                      isCaretaker: true,
                    ),
                  ));
                },
              ),
              _NavItem(
                icon: Icons.location_on_outlined,
                label: 'Location',
                onTap: () {
                  Navigator.pushReplacement(context, InstantPushMaterialRoute(
                    builder: (_) => LocationMapPage(
                      patientId: widget.patientId,
                      patientName: widget.patientName,
                    ),
                  ));
                },
              ),
              _NavItem(
                icon: Icons.person_outline_rounded,
                label: 'Profile',
                onTap: () {
                  Navigator.pushReplacement(context, InstantPushMaterialRoute(
                    builder: (_) => PatientProfilePage(
                      patientId: widget.patientId,
                      patientName: widget.patientName,
                    ),
                  ));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showReminderSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReminderSheet(
        patientId: widget.patientId,
        onSave: _loadPatientData,
      ),
    );
  }
}

// ── Action tile ───────────────────────────────────────────────────────────────
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final Color color;
  final Color colorSoft;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.colorSoft,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
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
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: colorSoft,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E1A18),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sublabel,
              style:
              const TextStyle(fontSize: 12, color: Color(0xFF7A6E6A)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bottom nav item ───────────────────────────────────────────────────────────
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlight;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlight = false,
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
            color: highlight
                ? const Color(0xFF5A7A1A)
                : const Color(0xFFBDB0AC),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: highlight
                  ? const Color(0xFF5A7A1A)
                  : const Color(0xFFBDB0AC),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reminder bottom sheet ─────────────────────────────────────────────────────
class ReminderSheet extends StatefulWidget {
  final String patientId;
  final VoidCallback onSave;

  const ReminderSheet({
    super.key,
    required this.patientId,
    required this.onSave,
  });

  @override
  State<ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<ReminderSheet> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String _selectedRepeat = 'Once';
  int? _missedAlertDelayMinutes = 5; // null = no caretaker alert
  bool _isSaving = false;

  static const _accent = Color(0xFF5A7A1A);
  static const _text = Color(0xFF1E1A18);
  static const _subtext = Color(0xFF7A6E6A);

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a title',
              style: TextStyle(fontWeight: FontWeight.w600)),
          backgroundColor: const Color(0xFFE57373),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final now = DateTime.now();
      final date = _selectedDate ?? now;
      final reminderTime = DateTime(
        date.year,
        date.month,
        date.day,
        _selectedTime?.hour ?? now.hour,
        _selectedTime?.minute ?? now.minute,
      );

      await _firestore.collection('reminders').add({
        'patientId': widget.patientId,
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'type': 'reminder',
        'time': Timestamp.fromDate(reminderTime),
        'repeating': _selectedRepeat.toLowerCase(),
        'completed': false,
        'missedAlertDelayMinutes': _missedAlertDelayMinutes,
        'createdAt': FieldValue.serverTimestamp(),
      });

      widget.onSave();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Reminder added!',
                style: TextStyle(fontWeight: FontWeight.w600)),
            backgroundColor: _accent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving reminder: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to save, try again'),
            backgroundColor: const Color(0xFF8D6E63),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(0, 0, 0, bottomPad),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFEDE5E2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF3E6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.alarm_add_rounded,
                      color: _accent, size: 22),
                ),
                const SizedBox(width: 14),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'New Reminder',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _text,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      'Fill in the details below',
                      style: TextStyle(fontSize: 13, color: _subtext),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFF0EBE8)),

          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Field(
                  label: 'Title',
                  child: _textField(_titleController,
                      hint: 'e.g. Take morning medication'),
                ),
                const SizedBox(height: 16),
                _Field(
                  label: 'Description',
                  child: _textField(_descriptionController,
                      hint: 'Optional notes', maxLines: 2),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _Field(
                        label: 'Date',
                        child: _Picker(
                          icon: Icons.calendar_today_outlined,
                          value: _selectedDate != null
                              ? DateFormat('MMM d, y').format(_selectedDate!)
                              : 'Select',
                          onTap: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: _selectedDate ?? DateTime.now(),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now()
                                  .add(const Duration(days: 730)),
                              builder: (ctx, child) => Theme(
                                data: Theme.of(ctx).copyWith(
                                  colorScheme: const ColorScheme.light(
                                      primary: _accent),
                                ),
                                child: child!,
                              ),
                            );
                            if (d != null) setState(() => _selectedDate = d);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Field(
                        label: 'Time',
                        child: _Picker(
                          icon: Icons.access_time_rounded,
                          value: _selectedTime != null
                              ? _selectedTime!.format(context)
                              : 'Select',
                          onTap: () async {
                            final t = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.now(),
                              builder: (ctx, child) => Theme(
                                data: Theme.of(ctx).copyWith(
                                  colorScheme: const ColorScheme.light(
                                      primary: _accent),
                                ),
                                child: child!,
                              ),
                            );
                            if (t != null) setState(() => _selectedTime = t);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _Field(
                  label: 'Repeat',
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAF6F4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFFEDE5E2), width: 1.5),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedRepeat,
                        isExpanded: true,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded,
                            color: _subtext, size: 20),
                        style: const TextStyle(
                            fontSize: 14,
                            color: _text,
                            fontWeight: FontWeight.w500),
                        dropdownColor: Colors.white,
                        items: ['Once', 'Daily', 'Weekly', 'Monthly']
                            .map((v) =>
                            DropdownMenuItem(value: v, child: Text(v)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _selectedRepeat = v);
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _Field(
                  label: 'Alert caretaker if missed after',
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAF6F4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFFEDE5E2), width: 1.5),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int?>(
                        value: _missedAlertDelayMinutes,
                        isExpanded: true,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded,
                            color: _subtext, size: 20),
                        style: const TextStyle(
                            fontSize: 14,
                            color: _text,
                            fontWeight: FontWeight.w500),
                        dropdownColor: Colors.white,
                        items: const [
                          DropdownMenuItem(
                              value: null, child: Text('No alert')),
                          DropdownMenuItem(
                              value: 1, child: Text('1 minute')),
                          DropdownMenuItem(
                              value: 3, child: Text('3 minutes')),
                          DropdownMenuItem(
                              value: 5, child: Text('5 minutes')),
                          DropdownMenuItem(
                              value: 10, child: Text('10 minutes')),
                          DropdownMenuItem(
                              value: 15, child: Text('15 minutes')),
                          DropdownMenuItem(
                              value: 30, child: Text('30 minutes')),
                        ],
                        onChanged: (v) =>
                            setState(() => _missedAlertDelayMinutes = v),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _accent.withOpacity(0.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                        : const Text(
                      'Save Reminder',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _textField(
      TextEditingController controller, {
        required String hint,
        int maxLines = 1,
      }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(
          fontSize: 14, color: _text, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
        const TextStyle(color: Color(0xFFBDB0AC), fontSize: 14),
        filled: true,
        fillColor: const Color(0xFFFAF6F4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
          const BorderSide(color: Color(0xFFEDE5E2), width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
          const BorderSide(color: Color(0xFFEDE5E2), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accent, width: 2),
        ),
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

// ── Form field wrapper ────────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  final String label;
  final Widget child;
  const _Field({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF5D4037),
          ),
        ),
        const SizedBox(height: 7),
        child,
      ],
    );
  }
}

// ── Date / time picker ────────────────────────────────────────────────────────
class _Picker extends StatelessWidget {
  final IconData icon;
  final String value;
  final VoidCallback onTap;

  const _Picker(
      {required this.icon, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFFFAF6F4),
          borderRadius: BorderRadius.circular(12),
          border:
          Border.all(color: const Color(0xFFEDE5E2), width: 1.5),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFFD4A5A5)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1E1A18),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}