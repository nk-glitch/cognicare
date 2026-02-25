import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:wear_plus/wear_plus.dart';
import 'dart:async';
import 'dart:math';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';

// ─── Design tokens ─────────────────────────────────────────────────────────────
const _kBg        = Color(0xFFF9EDE8); // warm cream
const _kCard      = Color(0xFFC4878A); // muted rose (matches screenshot ovals)
const _kCardInner = Color(0xFFB07275); // slightly deeper for centre card
const _kDivider   = Color(0xFFD9B8B4);
const _kEmergency = Color(0xFFE8736C); // coral alert
const _kAction    = Color(0xFF8FA9C9); // steel blue
const _kTextDark  = Color(0xFF3D2C31);
const _kTextLight = Color(0xFFF5EDED);
const _kTextMuted = Color(0xFFA08080);

const _kBase = TextStyle(
  decoration: TextDecoration.none,
  decorationColor: Colors.transparent,
  fontFamily: 'sans-serif',
);

class WatchPatientScreen extends StatefulWidget {
  final String patientId;
  const WatchPatientScreen({super.key, required this.patientId});

  @override
  State<WatchPatientScreen> createState() => _WatchPatientScreenState();
}

class _WatchPatientScreenState extends State<WatchPatientScreen>
    with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();

  List<Map<String, dynamic>> _reminders = [];
  bool _isLoading = true;
  int  _currentIndex = 0;

  Timer? _checkTimer;
  StreamSubscription<QuerySnapshot>? _reminderSub;
  final Set<String> _alertedIds = {};

  String _firstName = '';

  // Alert animation
  late AnimationController _alertPulse;
  late AnimationController _alertShake;
  late Animation<double>   _alertPulseAnim;
  late Animation<double>   _alertShakeAnim;

  // Card swipe animation
  late AnimationController _swipeCtrl;
  late Animation<double>   _swipeAnim;
  bool _swipingLeft = true;

  // Active alert reminder (null = no alert showing)
  Map<String, dynamic>? _alertReminder;

  @override
  void initState() {
    super.initState();

    _alertPulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    _alertPulseAnim = Tween<double>(begin: 0.96, end: 1.04)
        .animate(CurvedAnimation(parent: _alertPulse, curve: Curves.easeInOut));

    _alertShake = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _alertShakeAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -6.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -6.0, end:  6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin:  6.0, end: -4.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -4.0, end:  4.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin:  4.0, end:  0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _alertShake, curve: Curves.easeInOut));

    _swipeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _swipeAnim = CurvedAnimation(parent: _swipeCtrl, curve: Curves.easeOutCubic);
    _swipeCtrl.value = 1.0; // Start fully visible so first card is in focus

    _loadPatientName();
    _loadReminders();
    _setupListener();

    // Check every 15 seconds for due reminders
    _checkTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _checkDue();
    });
    // Also check immediately on start
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _checkDue();
    });

    NotificationService.onNotificationTap = (data) => _triggerAlert(data);
  }

  @override
  void dispose() {
    _alertPulse.dispose();
    _alertShake.dispose();
    _swipeCtrl.dispose();
    _checkTimer?.cancel();
    _reminderSub?.cancel();
    super.dispose();
  }

  // ── Data ─────────────────────────────────────────────────────────────────────

  Future<void> _loadPatientName() async {
    try {
      final doc = await _firestore.collection('users').doc(widget.patientId).get();
      if (!doc.exists || !mounted) return;
      final d    = doc.data()!;
      final full = '${d['firstName'] ?? ''} ${d['lastName'] ?? ''}'.trim();
      setState(() => _firstName = full.split(' ').first);
    } catch (e) { debugPrint('loadName: $e'); }
  }

  Future<void> _loadReminders() async {
    final now = DateTime.now();
    try {
      final snap = await _firestore
          .collection('reminders')
          .where('patientId', isEqualTo: widget.patientId)
          .where('completed', isEqualTo: false)
          .where('time', isGreaterThanOrEqualTo:
      Timestamp.fromDate(DateTime(now.year, now.month, now.day)))
          .where('time', isLessThanOrEqualTo:
      Timestamp.fromDate(DateTime(now.year, now.month, now.day, 23, 59, 59)))
          .orderBy('time')
          .get();
      if (mounted) {
        setState(() {
          _reminders = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
          _currentIndex = _currentIndex.clamp(0, max(0, _reminders.length - 1));
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('loadReminders: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setupListener() {
    _reminderSub = _firestore
        .collection('reminders')
        .where('patientId', isEqualTo: widget.patientId)
        .where('completed', isEqualTo: false)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final currentTime = DateTime.now();
      for (final doc in snap.docs) {
        final r  = doc.data();
        final tv = r['time'];
        if (tv == null || r['acknowledgedEarly'] == true) continue;
        if (_alertedIds.contains(doc.id)) continue;
        final t    = (tv as Timestamp).toDate();
        final diff = currentTime.difference(t);
        // Trigger if within a 2-minute window of the reminder time
        if (diff.inSeconds >= 0 && diff.inSeconds < 120) {
          _triggerAlert({
            'reminderId': doc.id,
            'title': r['title'] ?? 'Reminder',
            'time': DateFormat('h:mm a').format(t.toLocal()),
            'timestamp': t.millisecondsSinceEpoch,
            // ── FIX: read both notes and description ──
            'notes': (r['notes'] as String? ?? '').isNotEmpty
                ? r['notes']
                : (r['description'] as String? ?? ''),
            'category': r['category'] ?? '',
          });
          break;
        }
      }
      _loadReminders();
    }, onError: (e) => debugPrint('listener: $e'));
  }

  Future<void> _checkDue() async {
    try {
      final snap = await _firestore
          .collection('reminders')
          .where('patientId', isEqualTo: widget.patientId)
          .where('completed', isEqualTo: false)
          .where('time', isLessThanOrEqualTo: Timestamp.now())
          .orderBy('time').limit(5).get();

      if (snap.docs.isEmpty) return;

      final now = DateTime.now();
      for (final doc in snap.docs) {
        final r = doc.data();
        if (r['acknowledgedEarly'] == true) continue;
        if (_alertedIds.contains(doc.id)) continue;
        final tv = r['time'];
        if (tv == null) continue;
        final t = (tv as Timestamp).toDate();
        final diff = now.difference(t);
        // Only alert if within 5 minutes (avoid alerting very old reminders)
        if (diff.inMinutes < 5) {
          _triggerAlert({
            'reminderId': doc.id,
            'title': r['title'] ?? 'Reminder',
            'time': DateFormat('h:mm a').format(t.toLocal()),
            'timestamp': t.millisecondsSinceEpoch,
            // ── FIX: read both notes and description ──
            'notes': (r['notes'] as String? ?? '').isNotEmpty
                ? r['notes']
                : (r['description'] as String? ?? ''),
            'category': r['category'] ?? '',
          });
          break;
        }
      }
    } catch (e) { debugPrint('checkDue: $e'); }
  }

  void _triggerAlert(Map<String, dynamic> data) {
    final id = data['reminderId'] ?? '';
    if (id.isEmpty || _alertedIds.contains(id)) return;
    _alertedIds.add(id);

    // Vibrate pattern
    _vibrateAlert();

    if (mounted) {
      setState(() => _alertReminder = data);
      // Start shake after a brief delay so the widget is rendered
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted) _alertShake.forward(from: 0);
      });
    }
  }

  void _vibrateAlert() {
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) HapticFeedback.heavyImpact();
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) HapticFeedback.heavyImpact();
    });
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) HapticFeedback.heavyImpact();
    });
  }

  void _dismissAlert({required bool markDone, bool snooze = false}) async {
    final data = _alertReminder;
    if (data == null) return;
    final id        = data['reminderId'] as String;
    final timestamp = data['timestamp'];

    setState(() => _alertReminder = null);

    try {
      final ref = _firestore.collection('reminders').doc(id);
      if (snooze) {
        final newTime = DateTime.now().add(const Duration(minutes: 5));
        await ref.update({
          'time': Timestamp.fromDate(newTime),
          'completed': false,
          'isSnoozed': true,
        });
        // Allow re-alerting after snooze
        _alertedIds.remove(id);
      } else if (markDone) {
        final scheduled = timestamp != null
            ? DateTime.fromMillisecondsSinceEpoch(timestamp as int)
            : null;
        if (scheduled != null && DateTime.now().isBefore(scheduled)) {
          await ref.update({'acknowledgedEarly': true});
        } else {
          await ref.update({'completed': true});
        }
      }
    } catch (e) { debugPrint('dismissAlert: $e'); }

    _loadReminders();
  }

  // ── Carousel navigation ──────────────────────────────────────────────────────

  void _navigateTo(int index) {
    if (_reminders.isEmpty) return;
    // Wrap around
    final wrapped = index % _reminders.length;
    if (wrapped == _currentIndex) return;
    _swipingLeft = index > _currentIndex;
    setState(() => _currentIndex = wrapped);
    _swipeCtrl.forward(from: 0);
  }

  // ── Helper: resolve details text from either field ────────────────────────────

  /// Returns the best available details string for a reminder map.
  /// Prefers `notes`; falls back to `description`; returns '' if neither.
  String _details(Map<String, dynamic> r) {
    final notes = (r['notes'] as String? ?? '').trim();
    if (notes.isNotEmpty) return notes;
    return (r['description'] as String? ?? '').trim();
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return WatchShape(
      builder: (_, shape, __) => AmbientMode(
        builder: (_, mode, __) =>
        mode == WearMode.ambient ? _buildAmbient() : _buildActive(),
      ),
    );
  }

  Widget _buildAmbient() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('CogniCare',
              style: _kBase.copyWith(color: _kAction, fontSize: 10, letterSpacing: 2)),
          if (_reminders.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              DateFormat('h:mm a')
                  .format((_reminders.first['time'] as Timestamp).toDate()),
              style: _kBase.copyWith(color: Colors.white, fontSize: 17),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _buildActive() {
    return ClipOval(
      child: Container(
        color: _kBg,
        child: LayoutBuilder(builder: (ctx, bc) {
          final diameter = bc.maxWidth;

          // Show fullscreen alert if one is active
          if (_alertReminder != null) {
            return _buildFullscreenAlert(diameter);
          }

          if (_isLoading) return _buildLoader();
          if (_reminders.isEmpty) return _buildEmpty(diameter);
          return _buildCarousel(diameter);
        }),
      ),
    );
  }

  // ── Loader ───────────────────────────────────────────────────────────────────

  Widget _buildLoader() {
    return const Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 22, height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: _kAction)),
        SizedBox(height: 8),
        Text('Loading…',
            style: TextStyle(color: _kTextMuted, fontSize: 9,
                decoration: TextDecoration.none)),
      ]),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────────

  Widget _buildEmpty(double diameter) {
    final r   = diameter / 2;
    final ins = r * (1 - 1 / sqrt2) + 8;
    return Stack(
      alignment: Alignment.center,
      children: [
        Padding(
          padding: EdgeInsets.all(ins),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle_outline,
                  color: _kAction.withOpacity(0.5), size: 26),
              const SizedBox(height: 8),
              Text(
                _firstName.isNotEmpty ? 'All done,\n$_firstName!' : 'All done!',
                style: _kBase.copyWith(color: _kTextDark, fontSize: 10,
                    fontWeight: FontWeight.w700, height: 1.3),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text('No reminders today',
                  style: _kBase.copyWith(color: _kTextMuted, fontSize: 8),
                  textAlign: TextAlign.center),
            ]),
          ),
        ),
        // ── Logout button — top-left arc ────────────────────────────────────
        Positioned(
          top: r * 0.18,
          left: r * 0.18,
          child: GestureDetector(
            onTap: _showLogoutSheet,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: _kDivider.withOpacity(0.55),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.logout,
                  size: 11, color: _kTextMuted.withOpacity(0.7)),
            ),
          ),
        ),
      ],
    );
  }

  // ── Fullscreen alert ──────────────────────────────────────────────────────────

  Widget _buildFullscreenAlert(double diameter) {
    final data  = _alertReminder!;
    final title = data['title'] as String? ?? 'Reminder';
    final time  = data['time'] as String? ?? '';
    // ── FIX: use helper so description is also shown in alerts ──
    final details = (data['notes'] as String? ?? '').trim().isNotEmpty
        ? (data['notes'] as String).trim()
        : (data['description'] as String? ?? '').trim();

    return AnimatedBuilder(
      animation: Listenable.merge([_alertPulseAnim, _alertShakeAnim]),
      builder: (_, __) {
        return Transform.translate(
          offset: Offset(_alertShakeAnim.value, 0),
          child: Transform.scale(
            scale: _alertPulseAnim.value,
            child: Container(
              width: diameter,
              height: diameter,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: _kEmergency,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Bell icon
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.25),
                    ),
                    child: const Icon(Icons.notifications_active,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: Text(title,
                        style: _kBase.copyWith(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            height: 1.2),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(height: 3),
                  Text(time,
                      style: _kBase.copyWith(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 9,
                          fontWeight: FontWeight.w500)),
                  // ── FIX: show details in alert (was labelled 'notes') ──
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(details,
                          style: _kBase.copyWith(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 8),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                  const SizedBox(height: 10),
                  // Buttons
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    // Snooze
                    _AlertButton(
                      label: '+5',
                      icon: Icons.snooze,
                      onTap: () => _dismissAlert(markDone: false, snooze: true),
                      bg: Colors.white.withOpacity(0.2),
                      fg: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    // Done
                    _AlertButton(
                      label: 'Done',
                      icon: Icons.check,
                      onTap: () => _dismissAlert(markDone: true),
                      bg: Colors.white,
                      fg: _kEmergency,
                    ),
                  ]),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Carousel ──────────────────────────────────────────────────────────────────

  Widget _buildCarousel(double diameter) {
    final r = diameter / 2;

    // Side oval dimensions
    const sideW = 48.0;
    const sideH = 84.0;

    final cardDiameter = (diameter - 46).clamp(100.0, 200.0) * 0.78;
    final centreR = cardDiameter / 2;

    final current = _reminders[_currentIndex];
    final timeVal = (current['time'] as Timestamp?)?.toDate();
    final timeStr = timeVal != null ? DateFormat('h:mm a').format(timeVal.toLocal()) : '';
    // ── FIX: use helper for details ──
    final details  = _details(current);
    final category = (current['category'] as String? ?? '').trim();

    const greetingTop = 8.0;
    const dotsBottom = 10.0;

    return GestureDetector(
      // Horizontal swipe to navigate
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        if (details.primaryVelocity! < -100) {
          _navigateTo((_currentIndex + 1) % _reminders.length);
        } else if (details.primaryVelocity! > 100) {
          _navigateTo((_currentIndex - 1 + _reminders.length) % _reminders.length);
        }
      },
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: Stack(alignment: Alignment.center, children: [

          // ── Centre card ───────────────────────────────────────────────────
          Positioned(
            left: r - centreR,
            top:  r - centreR,
            child: AnimatedBuilder(
              animation: _swipeAnim,
              builder: (_, __) {
                final offset = (1.0 - _swipeAnim.value) *
                    (_swipingLeft ? 18.0 : -18.0);
                return Transform.translate(
                  offset: Offset(offset, 0),
                  child: Opacity(
                    opacity: 0.6 + 0.4 * _swipeAnim.value,
                    child: GestureDetector(
                      onTap: () => _showDoneSheet(current, timeStr),
                      child: Container(
                        width: centreR * 2,
                        height: centreR * 2,
                        decoration: BoxDecoration(
                          color: _kCardInner,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.18),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Title
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Text(
                                current['title'] ?? '',
                                style: _kBase.copyWith(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    height: 1.3),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Time
                            Text(timeStr,
                                style: _kBase.copyWith(
                                    color: Colors.white.withOpacity(0.85),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500)),
                            // Category badge (if present)
                            if (category.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(category,
                                    style: _kBase.copyWith(
                                        color: Colors.white.withOpacity(0.9),
                                        fontSize: 8,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ],
                            // ── FIX: Details section (notes OR description) ──
                            if (details.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              // Subtle divider
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24),
                                child: Divider(
                                  color: Colors.white.withOpacity(0.25),
                                  thickness: 0.8,
                                  height: 1,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 18),
                                child: Text(
                                  details,
                                  style: _kBase.copyWith(
                                      color: Colors.white.withOpacity(0.82),
                                      fontSize: 8.5,
                                      height: 1.4),
                                  textAlign: TextAlign.center,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            const SizedBox(height: 6),
                            // Tap hint
                            Text('tap to act',
                                style: _kBase.copyWith(
                                    color: Colors.white.withOpacity(0.45),
                                    fontSize: 7)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // ── Left oval (prev) ──────────────────────────────────────────────
          Positioned(
            left: 4,
            top: r - sideH / 2,
            child: GestureDetector(
              onTap: () => _navigateTo(_currentIndex - 1),
              child: AnimatedOpacity(
                opacity: 0.7,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  width: sideW,
                  height: sideH,
                  decoration: BoxDecoration(
                    color: _kCard,
                    borderRadius: BorderRadius.circular(sideW / 2),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.chevron_left,
                      color: Colors.white.withOpacity(0.7),
                      size: 18),
                ),
              ),
            ),
          ),

          // ── Right oval (next) ─────────────────────────────────────────────
          Positioned(
            right: 4,
            top: r - sideH / 2,
            child: GestureDetector(
              onTap: () => _navigateTo(_currentIndex + 1),
              child: AnimatedOpacity(
                opacity: 0.7,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  width: sideW,
                  height: sideH,
                  decoration: BoxDecoration(
                    color: _kCard,
                    borderRadius: BorderRadius.circular(sideW / 2),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.chevron_right,
                      color: Colors.white.withOpacity(0.7),
                      size: 18),
                ),
              ),
            ),
          ),

          // ── Greeting at top ────────────────────────────────────────────────
          Positioned(
            top: greetingTop,
            child: Text(
              _firstName.isNotEmpty ? 'Hello, $_firstName' : 'Hello',
              style: _kBase.copyWith(
                  color: _kTextDark,
                  fontSize: 9,
                  fontWeight: FontWeight.w600),
            ),
          ),

          // ── Logout button — top-left arc (hard to accidentally press) ─────
          Positioned(
            top: r * 0.18,
            left: r * 0.18,
            child: GestureDetector(
              onTap: _showLogoutSheet,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: _kDivider.withOpacity(0.55),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.logout,
                    size: 11, color: _kTextMuted.withOpacity(0.7)),
              ),
            ),
          ),

          // ── Dot indicator at BOTTOM ───────────────────────────────────────
          Positioned(
            bottom: dotsBottom,
            child: _DotIndicator(
                count: _reminders.length, current: _currentIndex),
          ),
        ]),
      ),
    );
  }

  // ── Logout ────────────────────────────────────────────────────────────────────

  void _showLogoutSheet() {
    // Step 1: first confirmation sheet
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: _kBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          border: Border.all(color: _kDivider),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Drag handle
          Container(
            width: 24, height: 3,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
                color: _kDivider, borderRadius: BorderRadius.circular(2)),
          ),
          Icon(Icons.logout, color: _kTextMuted, size: 20),
          const SizedBox(height: 6),
          Text('Sign out?',
              style: _kBase.copyWith(
                  color: _kTextDark, fontSize: 11, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center),
          const SizedBox(height: 3),
          Text('You will need to log in again on your watch.',
              style: _kBase.copyWith(color: _kTextMuted, fontSize: 8, height: 1.4),
              textAlign: TextAlign.center),
          const SizedBox(height: 10),
          _SheetButton(
            label: 'Yes, sign out',
            color: _kEmergency,
            textColor: Colors.white,
            onTap: () {
              Navigator.pop(context); // close first sheet
              // Small delay so first sheet finishes dismissing
              Future.delayed(const Duration(milliseconds: 220), () {
                if (mounted) _showLogoutConfirmSheet();
              });
            },
          ),
          const SizedBox(height: 6),
          _SheetButton(
            label: 'Cancel',
            color: _kCard,
            textColor: Colors.white,
            onTap: () => Navigator.pop(context),
          ),
        ]),
      ),
    );
  }

  void _showLogoutConfirmSheet() {
    // Step 2: second confirmation sheet
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: _kBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          border: Border.all(color: _kEmergency.withOpacity(0.5), width: 1.5),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 24, height: 3,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
                color: _kDivider, borderRadius: BorderRadius.circular(2)),
          ),
          Text('Are you sure?',
              style: _kBase.copyWith(
                  color: _kEmergency, fontSize: 11, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text('This is your final confirmation.',
              style: _kBase.copyWith(color: _kTextMuted, fontSize: 8, height: 1.4),
              textAlign: TextAlign.center),
          const SizedBox(height: 10),
          _SheetButton(
            label: 'Confirm sign out',
            color: _kEmergency,
            textColor: Colors.white,
            onTap: () async {
              Navigator.pop(context);
              await _authService.signOut();
              // Auth stream in WatchActiveFace will redirect to login
            },
          ),
          const SizedBox(height: 6),
          _SheetButton(
            label: 'Cancel',
            color: _kCard,
            textColor: Colors.white,
            onTap: () => Navigator.pop(context),
          ),
        ]),
      ),
    );
  }

  // ── Bottom sheet to mark done / snooze from carousel ─────────────────────────

  void _showDoneSheet(Map<String, dynamic> r, String timeStr) {
    final id        = r['id'] as String;
    final timestamp = (r['time'] as Timestamp?)?.toDate()?.millisecondsSinceEpoch;
    // ── FIX: show details in sheet too ──
    final details = _details(r);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: _kBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          border: Border.all(color: _kDivider),
        ),
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Drag handle
          Container(
            width: 24, height: 3,
            margin: const EdgeInsets.only(bottom: 5),
            decoration: BoxDecoration(
                color: _kDivider,
                borderRadius: BorderRadius.circular(2)),
          ),
          Text(r['title'] ?? '',
              style: _kBase.copyWith(color: _kTextDark, fontSize: 10,
                  fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          Text(timeStr,
              style: _kBase.copyWith(color: _kTextMuted, fontSize: 8)),
          // ── FIX: show details beneath the time in the sheet ──
          if (details.isNotEmpty) ...[
            const SizedBox(height: 4),
            Divider(color: _kDivider, thickness: 0.8, height: 1),
            const SizedBox(height: 6),
            Text(
              details,
              style: _kBase.copyWith(
                  color: _kTextDark.withOpacity(0.75), fontSize: 8.5, height: 1.45),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
          ],
          const SizedBox(height: 5),
          _SheetButton(
            label: 'Done',
            color: _kAction,
            textColor: Colors.white,
            onTap: () async {
              Navigator.pop(context);
              final ref = _firestore.collection('reminders').doc(id);
              final scheduled = timestamp != null
                  ? DateTime.fromMillisecondsSinceEpoch(timestamp)
                  : null;
              if (scheduled != null && DateTime.now().isBefore(scheduled)) {
                await ref.update({'acknowledgedEarly': true});
              } else {
                await ref.update({'completed': true});
              }
              _loadReminders();
            },
          ),
          const SizedBox(height: 4),
          _SheetButton(
            label: '+5 min',
            color: _kCard,
            textColor: Colors.white,
            onTap: () async {
              Navigator.pop(context);
              final newTime = DateTime.now().add(const Duration(minutes: 5));
              await _firestore.collection('reminders').doc(id).update({
                'time': Timestamp.fromDate(newTime),
                'completed': false,
                'isSnoozed': true,
              });
              _loadReminders();
            },
          ),
        ]),
      ),
    );
  }
}

// ── Alert button ──────────────────────────────────────────────────────────────

class _AlertButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color bg;
  final Color fg;

  const _AlertButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: fg, size: 11),
          const SizedBox(width: 3),
          Text(label,
              style: _kBase.copyWith(
                  color: fg, fontSize: 9, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

// ── Sheet button ──────────────────────────────────────────────────────────────

class _SheetButton extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback onTap;

  const _SheetButton({
    required this.label,
    required this.color,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 28,
        width: double.infinity,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: _kBase.copyWith(
                color: textColor,
                fontSize: 10,
                fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// ── Dot indicator ─────────────────────────────────────────────────────────────

class _DotIndicator extends StatelessWidget {
  final int count;
  final int current;
  const _DotIndicator({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: active ? 10 : 5,
          height: 5,
          decoration: BoxDecoration(
            color: active ? _kAction : _kDivider,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}