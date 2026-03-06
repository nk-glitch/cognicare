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

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens — full CogniCare system, mirrored from phone app
// ─────────────────────────────────────────────────────────────────────────────
const _kBg         = Color(0xFFF7F4F2);
const _kCard       = Colors.white;
const _kAccent     = Color(0xFF5A7A1A);   // CogniCare green
const _kAccentSoft = Color(0xFFEEF3E6);
const _kRose       = Color(0xFFD4A5A5);   // CogniCare rose
const _kRoseSoft   = Color(0xFFF4E4E1);
const _kText       = Color(0xFF1E1A18);
const _kSubtext    = Color(0xFF7A6E6A);
const _kBorder     = Color(0xFFEDE5E2);
const _kShadow     = Color(0xFFB07A6E);
const _kEmergency  = Color(0xFFE57373);

// Shared base — prevents Flutter's default underline decoration on Wear OS
const _kBase = TextStyle(
  decoration: TextDecoration.none,
  decorationColor: Colors.transparent,
);

// ─────────────────────────────────────────────────────────────────────────────
class WatchPatientScreen extends StatefulWidget {
  final String patientId;
  const WatchPatientScreen({super.key, required this.patientId});

  @override
  State<WatchPatientScreen> createState() => _WatchPatientScreenState();
}

class _WatchPatientScreenState extends State<WatchPatientScreen>
    with TickerProviderStateMixin {

  // ── Services ────────────────────────────────────────────────────────────────
  final _db          = FirebaseFirestore.instance;
  final _authService = AuthService();

  // ── State ───────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _reminders    = [];
  bool   _isLoading    = true;
  bool   _isRefreshing = false;
  int    _currentIndex = 0;
  String _firstName    = '';

  Map<String, dynamic>? _alertReminder;
  final Set<String>     _alertedIds = {};

  // ── Heart rate ──────────────────────────────────────────────────────────────
  static const _hrChannel = EventChannel('cognicare/heart_rate');
  int?  _heartRate;
  StreamSubscription? _hrSub;

  // ── Subscriptions / timers ──────────────────────────────────────────────────
  Timer?                             _checkTimer;
  StreamSubscription<QuerySnapshot>? _reminderSub;

  // ── Animation controllers ───────────────────────────────────────────────────
  late AnimationController _entryCtrl;
  late AnimationController _alertPulseCtrl;
  late AnimationController _alertShakeCtrl;
  late AnimationController _swipeCtrl;

  late Animation<double> _entryFade;
  late Animation<Offset> _entrySlide;
  late Animation<double> _alertPulse;
  late Animation<double> _alertShake;
  late Animation<double> _swipe;
  bool _swipingLeft = true;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initHealth();
    _loadPatientName();
    _loadReminders();
    _setupRealtimeListener();

    _checkTimer = Timer.periodic(
        const Duration(seconds: 15), (_) { if (mounted) _checkDue(); });
    Future.delayed(
        const Duration(seconds: 2), () { if (mounted) _checkDue(); });

    NotificationService.onNotificationTap = _triggerAlert;
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _alertPulseCtrl.dispose();
    _alertShakeCtrl.dispose();
    _swipeCtrl.dispose();
    _checkTimer?.cancel();
    _reminderSub?.cancel();
    _hrSub?.cancel();
    super.dispose();
  }

  void _initAnimations() {
    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 550));
    _entryFade  = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _entrySlide = Tween<Offset>(
        begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(
        parent: _entryCtrl, curve: Curves.easeOutCubic));

    _alertPulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 650))
      ..repeat(reverse: true);
    _alertPulse = Tween<double>(begin: 0.97, end: 1.03).animate(
        CurvedAnimation(parent: _alertPulseCtrl, curve: Curves.easeInOut));

    _alertShakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 420));
    _alertShake = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0,  end: -7.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -7.0, end:  7.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin:  7.0, end: -5.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -5.0, end:  5.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin:  5.0, end:  0.0), weight: 1),
    ]).animate(CurvedAnimation(
        parent: _alertShakeCtrl, curve: Curves.easeInOut));

    _swipeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
    _swipe = CurvedAnimation(parent: _swipeCtrl, curve: Curves.easeOutCubic);
    _swipeCtrl.value = 1.0;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Health
  // ─────────────────────────────────────────────────────────────────────────

  void _initHealth() {
    try {
      _hrSub = _hrChannel.receiveBroadcastStream().listen(
            (v) {
          if (mounted && v is int && v > 0) setState(() => _heartRate = v);
        },
        onError: (e) => debugPrint('hr: $e'),
      );
    } catch (e) { debugPrint('initHealth: $e'); }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Data
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadPatientName() async {
    try {
      final doc = await _db.collection('users').doc(widget.patientId).get();
      if (!doc.exists || !mounted) return;
      final d = doc.data()!;
      final full = '${d['firstName'] ?? ''} ${d['lastName'] ?? ''}'.trim();
      setState(() => _firstName = full.split(' ').first);
    } catch (e) { debugPrint('loadName: $e'); }
  }

  Future<void> _loadReminders() async {
    final now      = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd   = DateTime(now.year, now.month, now.day, 23, 59, 59);
    try {
      final snap = await _db
          .collection('reminders')
          .where('patientId', isEqualTo: widget.patientId)
          .where('completed',  isEqualTo: false)
          .where('time', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
          .where('time', isLessThanOrEqualTo:    Timestamp.fromDate(dayEnd))
          .orderBy('time')
          .get();

      if (!mounted) return;
      setState(() {
        _reminders    =
            snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        _currentIndex =
            _currentIndex.clamp(0, max(0, _reminders.length - 1));
        _isLoading    = false;
      });
      if (!_entryCtrl.isCompleted) _entryCtrl.forward();
    } catch (e) {
      debugPrint('loadReminders: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    HapticFeedback.mediumImpact();
    await _loadReminders();
    if (mounted) setState(() => _isRefreshing = false);
  }

  void _setupRealtimeListener() {
    _reminderSub = _db
        .collection('reminders')
        .where('patientId', isEqualTo: widget.patientId)
        .where('completed',  isEqualTo: false)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final now = DateTime.now();
      for (final doc in snap.docs) {
        final r = doc.data();
        if (r['acknowledgedEarly'] == true) continue;
        if (_alertedIds.contains(doc.id)) continue;
        final tv = r['time'];
        if (tv == null) continue;
        final t    = (tv as Timestamp).toDate();
        final diff = now.difference(t);
        if (diff.inSeconds >= 0 && diff.inSeconds < 120) {
          _triggerAlert(_toAlertData(doc.id, r, t));
          break;
        }
      }
      _loadReminders();
    }, onError: (e) => debugPrint('listener: $e'));
  }

  Future<void> _checkDue() async {
    try {
      final snap = await _db
          .collection('reminders')
          .where('patientId', isEqualTo: widget.patientId)
          .where('completed',  isEqualTo: false)
          .where('time', isLessThanOrEqualTo: Timestamp.now())
          .orderBy('time')
          .limit(5)
          .get();
      if (snap.docs.isEmpty) return;
      final now = DateTime.now();
      for (final doc in snap.docs) {
        final r = doc.data();
        if (r['acknowledgedEarly'] == true) continue;
        if (_alertedIds.contains(doc.id)) continue;
        final tv = r['time'];
        if (tv == null) continue;
        final t    = (tv as Timestamp).toDate();
        if (now.difference(t).inMinutes < 5) {
          _triggerAlert(_toAlertData(doc.id, r, t));
          break;
        }
      }
    } catch (e) { debugPrint('checkDue: $e'); }
  }

  Map<String, dynamic> _toAlertData(
      String id, Map<String, dynamic> r, DateTime t) => {
    'reminderId': id,
    'title':     r['title'] ?? 'Reminder',
    'time':      DateFormat('h:mm a').format(t.toLocal()),
    'timestamp': t.millisecondsSinceEpoch,
    'notes':     (r['notes'] as String? ?? '').isNotEmpty
        ? r['notes'] : (r['description'] as String? ?? ''),
    'category':  r['category'] ?? '',
  };

  // ─────────────────────────────────────────────────────────────────────────
  // Alert
  // ─────────────────────────────────────────────────────────────────────────

  void _triggerAlert(Map<String, dynamic> data) {
    final id = data['reminderId'] as String? ?? '';
    if (id.isEmpty || _alertedIds.contains(id)) return;
    _alertedIds.add(id);
    HapticFeedback.heavyImpact();
    for (final ms in [300, 600, 1200]) {
      Future.delayed(Duration(milliseconds: ms),
              () { if (mounted) HapticFeedback.heavyImpact(); });
    }
    if (mounted) {
      setState(() => _alertReminder = data);
      Future.delayed(const Duration(milliseconds: 60),
              () { if (mounted) _alertShakeCtrl.forward(from: 0); });
    }
  }

  Future<void> _dismissAlert(
      {required bool markDone, bool snooze = false}) async {
    final data = _alertReminder;
    if (data == null) return;
    final id        = data['reminderId'] as String;
    final timestamp = data['timestamp'];
    setState(() => _alertReminder = null);

    try {
      final ref = _db.collection('reminders').doc(id);
      if (snooze) {
        await ref.update({
          'time':      Timestamp.fromDate(
              DateTime.now().add(const Duration(minutes: 5))),
          'completed': false,
          'isSnoozed': true,
        });
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

  // ─────────────────────────────────────────────────────────────────────────
  // Navigation
  // ─────────────────────────────────────────────────────────────────────────

  void _navigateTo(int index) {
    if (_reminders.isEmpty) return;
    final wrapped = index % _reminders.length;
    if (wrapped == _currentIndex) return;
    _swipingLeft = index > _currentIndex;
    setState(() => _currentIndex = wrapped);
    _swipeCtrl.forward(from: 0);
  }

  String _details(Map<String, dynamic> r) {
    final n = (r['notes'] as String? ?? '').trim();
    return n.isNotEmpty ? n : (r['description'] as String? ?? '').trim();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Root
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return WatchShape(
      builder: (_, shape, __) => AmbientMode(
        builder: (_, mode, __) =>
        mode == WearMode.ambient ? _buildAmbient() : _buildActive(),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Ambient — black, minimal OLED burn, just the essentials
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildAmbient() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          RichText(
            text: TextSpan(children: [
              TextSpan(text: 'Cogni',
                  style: _kBase.copyWith(
                      fontSize: 10, fontWeight: FontWeight.w300,
                      color: Colors.white38, letterSpacing: -0.3)),
              TextSpan(text: 'Care',
                  style: _kBase.copyWith(
                      fontSize: 10, fontWeight: FontWeight.w800,
                      color: Colors.white38, letterSpacing: -0.3)),
            ]),
          ),
          if (_reminders.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              DateFormat('h:mm a').format(
                  (_reminders.first['time'] as Timestamp).toDate().toLocal()),
              style: _kBase.copyWith(
                  color: Colors.white70, fontSize: 18,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            Text(
              _reminders.first['title'] ?? '',
              style: _kBase.copyWith(color: Colors.white30, fontSize: 8),
              textAlign: TextAlign.center,
            ),
          ],
          if (_heartRate != null) ...[
            const SizedBox(height: 7),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.favorite_rounded,
                  color: Colors.white24, size: 8),
              const SizedBox(width: 3),
              Text('$_heartRate bpm',
                  style: _kBase.copyWith(
                      color: Colors.white24, fontSize: 8)),
            ]),
          ],
        ]),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Active root
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildActive() {
    return ClipOval(
      child: Container(
        color: _kBg,
        child: LayoutBuilder(builder: (ctx, bc) {
          final d = bc.maxWidth;

          if (_alertReminder != null) return _buildAlert(d);

          Widget body;
          if (_isLoading) {
            body = _buildLoader();
          } else if (_reminders.isEmpty) {
            body = _buildEmpty(d);
          } else {
            body = _buildCarousel(d);
          }

          return GestureDetector(
            onVerticalDragEnd: (det) {
              if ((det.primaryVelocity ?? 0) > 200) _refresh();
            },
            child: Stack(children: [
              body,
              if (_isRefreshing) _buildRefreshPill(d),
            ]),
          );
        }),
      ),
    );
  }

  Widget _buildRefreshPill(double d) {
    return Positioned(
      top: d * 0.11, left: 0, right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(
                color: _kShadow.withOpacity(0.12),
                blurRadius: 10, offset: const Offset(0, 3))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 9, height: 9,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: _kAccent)),
            const SizedBox(width: 5),
            Text('Refreshing',
                style: _kBase.copyWith(
                    color: _kSubtext, fontSize: 8,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Loader
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildLoader() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: _kCard, shape: BoxShape.circle,
            boxShadow: [BoxShadow(
                color: _kShadow.withOpacity(0.12),
                blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: const Padding(
            padding: EdgeInsets.all(11),
            child: CircularProgressIndicator(
                strokeWidth: 2.5, color: _kAccent),
          ),
        ),
        const SizedBox(height: 9),
        Text('Loading…', style: _kBase.copyWith(
            color: _kSubtext, fontSize: 9,
            fontWeight: FontWeight.w500)),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Empty — all done for today
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildEmpty(double d) {
    final r   = d / 2;
    final ins = r * (1 - 1 / sqrt2) + 10;

    return FadeTransition(
      opacity: _entryFade,
      child: SlideTransition(
        position: _entrySlide,
        child: Padding(
          padding: EdgeInsets.all(ins),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 38, height: 38,
                decoration: const BoxDecoration(
                    color: _kAccentSoft, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded,
                    color: _kAccent, size: 20),
              ),
              const SizedBox(height: 9),
              Text(
                _firstName.isNotEmpty
                    ? 'All done,\n$_firstName!'
                    : 'All done!',
                style: _kBase.copyWith(
                    color: _kText, fontSize: 11,
                    fontWeight: FontWeight.w800, height: 1.3),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 3),
              Text('No reminders today',
                  style: _kBase.copyWith(
                      color: _kSubtext, fontSize: 8),
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              _buildStatusRow(),
            ]),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Status row — heart rate + sign out (reused in empty + carousel)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStatusRow() {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      // Heart rate pill
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: _kRoseSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: _kRose.withOpacity(0.22), width: 0.8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.favorite_rounded, color: _kRose, size: 9),
          const SizedBox(width: 3),
          Text(
            _heartRate != null ? '$_heartRate' : '--',
            style: _kBase.copyWith(
                color: _kRose, fontSize: 9,
                fontWeight: FontWeight.w700),
          ),
        ]),
      ),
      const SizedBox(width: 6),
      // Sign out pill
      GestureDetector(
        onTap: _showLogoutSheet,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [BoxShadow(
                color: _kShadow.withOpacity(0.10),
                blurRadius: 6,
                offset: const Offset(0, 2))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.logout_rounded, size: 9, color: _kSubtext),
            const SizedBox(width: 3),
            Text('Out',
                style: _kBase.copyWith(
                    color: _kSubtext, fontSize: 9,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Fullscreen alert overlay
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildAlert(double d) {
    final data    = _alertReminder!;
    final title   = data['title'] as String? ?? 'Reminder';
    final time    = data['time'] as String? ?? '';
    final rawNotes = (data['notes'] as String? ?? '').trim();
    final details  = rawNotes.isNotEmpty
        ? rawNotes
        : (data['description'] as String? ?? '').trim();

    return AnimatedBuilder(
      animation: Listenable.merge([_alertPulse, _alertShake]),
      builder: (_, __) => Transform.translate(
        offset: Offset(_alertShake.value, 0),
        child: Transform.scale(
          scale: _alertPulse.value,
          child: Container(
            width: d, height: d,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [_kEmergency, _kRose],
                center: Alignment.topCenter,
                radius: 1.3,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.22),
                  ),
                  child: const Icon(Icons.notifications_active_rounded,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(height: 7),
                if (time.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(time,
                        style: _kBase.copyWith(
                            color: Colors.white, fontSize: 8,
                            fontWeight: FontWeight.w700)),
                  ),
                const SizedBox(height: 5),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Text(title,
                      style: _kBase.copyWith(
                          color: Colors.white, fontSize: 12,
                          fontWeight: FontWeight.w800, height: 1.2),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(details,
                        style: _kBase.copyWith(
                            color: Colors.white.withOpacity(0.70),
                            fontSize: 8, height: 1.35),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
                const SizedBox(height: 11),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _AlertBtn(
                    label: '+5 min',
                    icon: Icons.snooze_rounded,
                    onTap: () =>
                        _dismissAlert(markDone: false, snooze: true),
                    bg: Colors.white.withOpacity(0.18),
                    fg: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  _AlertBtn(
                    label: 'Done',
                    icon: Icons.check_rounded,
                    onTap: () => _dismissAlert(markDone: true),
                    bg: Colors.white,
                    fg: _kEmergency,
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Carousel — main view when reminders exist
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildCarousel(double d) {
    final r = d / 2;

    const ow = 44.0;   // side oval width
    const oh = 80.0;   // side oval height

    final cd = ((d - 46) * 0.80).clamp(100.0, 200.0); // centre card diameter
    final cr = cd / 2;

    final current  = _reminders[_currentIndex];
    final timeVal  = (current['time'] as Timestamp?)?.toDate();
    final timeStr  = timeVal != null
        ? DateFormat('h:mm a').format(timeVal.toLocal()) : '';
    final details  = _details(current);
    final category = (current['category'] as String? ?? '').trim();

    return FadeTransition(
      opacity: _entryFade,
      child: GestureDetector(
        onHorizontalDragEnd: (det) {
          if (det.primaryVelocity == null) return;
          if (det.primaryVelocity! < -80) {
            _navigateTo((_currentIndex + 1) % _reminders.length);
          } else if (det.primaryVelocity! > 80) {
            _navigateTo(
                (_currentIndex - 1 + _reminders.length) % _reminders.length);
          }
        },
        child: SizedBox(
          width: d, height: d,
          child: Stack(alignment: Alignment.center, children: [

            // ── Greeting / counter strip ──────────────────────────────────
            Positioned(
              top: d * 0.08,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(
                      color: _kShadow.withOpacity(0.10),
                      blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.favorite_rounded,
                      color: _kRose, size: 8),
                  const SizedBox(width: 4),
                  Text(
                    _firstName.isNotEmpty
                        ? 'Hi, $_firstName' : 'Hello',
                    style: _kBase.copyWith(
                        color: _kText, fontSize: 9,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 6),
                  // Counter badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: _kAccentSoft,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${_currentIndex + 1}/${_reminders.length}',
                      style: _kBase.copyWith(
                          color: _kAccent, fontSize: 7,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ]),
              ),
            ),

            // ── Left oval ─────────────────────────────────────────────────
            Positioned(
              left: 3, top: r - oh / 2,
              child: GestureDetector(
                onTap: () => _navigateTo(_currentIndex - 1),
                child: Container(
                  width: ow, height: oh,
                  decoration: BoxDecoration(
                    color: _kCard,
                    borderRadius: BorderRadius.circular(ow / 2),
                    boxShadow: [BoxShadow(
                        color: _kShadow.withOpacity(0.13),
                        blurRadius: 10, offset: const Offset(0, 3))],
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.chevron_left_rounded,
                      color: _kSubtext.withOpacity(0.55), size: 20),
                ),
              ),
            ),

            // ── Right oval ────────────────────────────────────────────────
            Positioned(
              right: 3, top: r - oh / 2,
              child: GestureDetector(
                onTap: () => _navigateTo(_currentIndex + 1),
                child: Container(
                  width: ow, height: oh,
                  decoration: BoxDecoration(
                    color: _kCard,
                    borderRadius: BorderRadius.circular(ow / 2),
                    boxShadow: [BoxShadow(
                        color: _kShadow.withOpacity(0.13),
                        blurRadius: 10, offset: const Offset(0, 3))],
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.chevron_right_rounded,
                      color: _kSubtext.withOpacity(0.55), size: 20),
                ),
              ),
            ),

            // ── Centre card ───────────────────────────────────────────────
            Positioned(
              left: r - cr, top: r - cr,
              child: AnimatedBuilder(
                animation: _swipe,
                builder: (_, __) => Transform.translate(
                  offset: Offset(
                      (1.0 - _swipe.value) *
                          (_swipingLeft ? 22.0 : -22.0), 0),
                  child: Opacity(
                    opacity: 0.55 + 0.45 * _swipe.value,
                    child: GestureDetector(
                      onTap: () => _showDoneSheet(current, timeStr),
                      child: Container(
                        width: cr * 2, height: cr * 2,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _kCard,
                          boxShadow: [BoxShadow(
                              color: _kShadow.withOpacity(0.20),
                              blurRadius: 20,
                              offset: const Offset(0, 6))],
                        ),
                        child: ClipOval(
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Green accent arc at top — CogniCare signature
                              Positioned(
                                top: 0, left: 0, right: 0,
                                child: Container(
                                  height: cr * 0.30,
                                  color: _kAccent,
                                ),
                              ),

                              Column(
                                mainAxisAlignment:
                                MainAxisAlignment.center,
                                children: [
                                  // Time on the green band
                                  SizedBox(height: cr * 0.04),
                                  Text(timeStr,
                                      style: _kBase.copyWith(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.2)),

                                  SizedBox(height: cr * 0.10),

                                  // Title
                                  Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: cr * 0.20),
                                    child: Text(
                                      current['title'] ?? '',
                                      style: _kBase.copyWith(
                                          color: _kText,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          height: 1.25),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),

                                  // Category badge
                                  if (category.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _kRoseSoft,
                                        borderRadius:
                                        BorderRadius.circular(6),
                                      ),
                                      child: Text(category,
                                          style: _kBase.copyWith(
                                              color: _kRose,
                                              fontSize: 7,
                                              fontWeight:
                                              FontWeight.w700)),
                                    ),
                                  ],

                                  // Notes
                                  if (details.isNotEmpty) ...[
                                    const SizedBox(height: 5),
                                    Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: cr * 0.26),
                                      child: const Divider(
                                          color: _kBorder,
                                          thickness: 0.8,
                                          height: 1),
                                    ),
                                    const SizedBox(height: 4),
                                    Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: cr * 0.20),
                                      child: Text(
                                        details,
                                        style: _kBase.copyWith(
                                            color: _kSubtext,
                                            fontSize: 8,
                                            height: 1.4),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],

                                  const SizedBox(height: 5),
                                  Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.touch_app_rounded,
                                            size: 7,
                                            color: _kSubtext
                                                .withOpacity(0.35)),
                                        const SizedBox(width: 2),
                                        Text('tap to act',
                                            style: _kBase.copyWith(
                                                color: _kSubtext
                                                    .withOpacity(0.35),
                                                fontSize: 7)),
                                      ]),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Status row ────────────────────────────────────────────────
            Positioned(
              bottom: d * 0.085,
              child: _buildStatusRow(),
            ),

            // ── Dot indicator ─────────────────────────────────────────────
            Positioned(
              bottom: d * 0.042,
              child: _DotIndicator(
                  count: _reminders.length,
                  current: _currentIndex),
            ),
          ]),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Bottom sheets
  // ─────────────────────────────────────────────────────────────────────────

  void _showDoneSheet(Map<String, dynamic> r, String timeStr) {
    final id        = r['id'] as String;
    final timestamp =
        (r['time'] as Timestamp?)?.toDate()?.millisecondsSinceEpoch;
    final details   = _details(r);
    final category  = (r['category'] as String? ?? '').trim();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      isScrollControlled: true,
      builder: (_) => _WatchSheet(children: [
        Text(r['title'] ?? '',
            style: _kBase.copyWith(
                color: _kText, fontSize: 11,
                fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: _kRoseSoft,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(timeStr,
                style: _kBase.copyWith(
                    color: _kRose, fontSize: 8,
                    fontWeight: FontWeight.w700)),
          ),
          if (category.isNotEmpty) ...[
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: _kAccentSoft,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(category,
                  style: _kBase.copyWith(
                      color: _kAccent, fontSize: 8,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ]),
        if (details.isNotEmpty) ...[
          const SizedBox(height: 7),
          const Divider(color: _kBorder, thickness: 0.8, height: 1),
          const SizedBox(height: 6),
          Text(details,
              style: _kBase.copyWith(
                  color: _kSubtext, fontSize: 8.5, height: 1.45),
              textAlign: TextAlign.center),
        ],
        const SizedBox(height: 9),
        _WatchSheetBtn(
          label: 'Mark done',
          bg: _kAccent,
          fg: Colors.white,
          icon: Icons.check_rounded,
          onTap: () async {
            Navigator.pop(context);
            final ref = _db.collection('reminders').doc(id);
            final scheduled = timestamp != null
                ? DateTime.fromMillisecondsSinceEpoch(timestamp)
                : null;
            if (scheduled != null &&
                DateTime.now().isBefore(scheduled)) {
              await ref.update({'acknowledgedEarly': true});
            } else {
              await ref.update({'completed': true});
            }
            _loadReminders();
          },
        ),
        const SizedBox(height: 6),
        _WatchSheetBtn(
          label: 'Snooze 5 min',
          bg: _kRoseSoft,
          fg: _kRose,
          icon: Icons.snooze_rounded,
          onTap: () async {
            Navigator.pop(context);
            await _db.collection('reminders').doc(id).update({
              'time': Timestamp.fromDate(
                  DateTime.now().add(const Duration(minutes: 5))),
              'completed': false,
              'isSnoozed': true,
            });
            _loadReminders();
          },
        ),
      ]),
    );
  }

  void _showLogoutSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _WatchSheet(children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: const BoxDecoration(
              color: _kRoseSoft, shape: BoxShape.circle),
          child: const Icon(Icons.logout_rounded,
              color: _kRose, size: 18),
        ),
        const SizedBox(height: 7),
        Text('Sign out?',
            style: _kBase.copyWith(
                color: _kText, fontSize: 12,
                fontWeight: FontWeight.w800),
            textAlign: TextAlign.center),
        const SizedBox(height: 3),
        Text('You\'ll need to log back in.',
            style: _kBase.copyWith(
                color: _kSubtext, fontSize: 8, height: 1.4),
            textAlign: TextAlign.center),
        const SizedBox(height: 10),
        _WatchSheetBtn(
          label: 'Sign out',
          bg: _kRose,
          fg: Colors.white,
          onTap: () {
            Navigator.pop(context);
            Future.delayed(const Duration(milliseconds: 200),
                    () { if (mounted) _showLogoutConfirmSheet(); });
          },
        ),
        const SizedBox(height: 6),
        _WatchSheetBtn(
          label: 'Cancel',
          bg: _kBorder,
          fg: _kSubtext,
          onTap: () => Navigator.pop(context),
        ),
      ]),
    );
  }

  void _showLogoutConfirmSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _WatchSheet(
        borderColor: _kRose.withOpacity(0.45),
        children: [
          Text('Are you sure?',
              style: _kBase.copyWith(
                  color: _kRose, fontSize: 12,
                  fontWeight: FontWeight.w800),
              textAlign: TextAlign.center),
          const SizedBox(height: 3),
          Text('This is your final confirmation.',
              style: _kBase.copyWith(
                  color: _kSubtext, fontSize: 8, height: 1.4),
              textAlign: TextAlign.center),
          const SizedBox(height: 10),
          _WatchSheetBtn(
            label: 'Confirm',
            bg: _kRose,
            fg: Colors.white,
            onTap: () async {
              Navigator.pop(context);
              await _authService.signOut();
            },
          ),
          const SizedBox(height: 6),
          _WatchSheetBtn(
            label: 'Cancel',
            bg: _kBorder,
            fg: _kSubtext,
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helper widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Button on the fullscreen alert overlay.
class _AlertBtn extends StatelessWidget {
  final String    label;
  final IconData  icon;
  final VoidCallback onTap;
  final Color bg;
  final Color fg;

  const _AlertBtn({
    required this.label, required this.icon,
    required this.onTap, required this.bg, required this.fg,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: fg, size: 11),
        const SizedBox(width: 4),
        Text(label,
            style: _kBase.copyWith(
                color: fg, fontSize: 10,
                fontWeight: FontWeight.w700)),
      ]),
    ),
  );
}

/// White bottom sheet card styled to CogniCare.
class _WatchSheet extends StatelessWidget {
  final List<Widget> children;
  final Color?       borderColor;

  const _WatchSheet({required this.children, this.borderColor});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      border: Border.all(
          color: borderColor ?? const Color(0xFFEDE5E2), width: 1.2),
      boxShadow: [BoxShadow(
          color: const Color(0xFFB07A6E).withOpacity(0.13),
          blurRadius: 22, offset: const Offset(0, -4))],
    ),
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 26, height: 3,
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
              color: const Color(0xFFEDE5E2),
              borderRadius: BorderRadius.circular(2)),
        ),
        ...children,
      ],
    ),
  );
}

/// Full-width action button for bottom sheets.
class _WatchSheetBtn extends StatelessWidget {
  final String    label;
  final Color     bg;
  final Color     fg;
  final VoidCallback onTap;
  final IconData? icon;

  const _WatchSheetBtn({
    required this.label, required this.bg,
    required this.fg,    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 31, width: double.infinity,
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(11)),
      alignment: Alignment.center,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, color: fg, size: 12),
          const SizedBox(width: 5),
        ],
        Text(label,
            style: _kBase.copyWith(
                color: fg, fontSize: 10,
                fontWeight: FontWeight.w700)),
      ]),
    ),
  );
}

/// Animated pill-dot page indicator.
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
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width:  active ? 12 : 5,
          height: 5,
          decoration: BoxDecoration(
            color: active ? _kAccent : _kBorder,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}