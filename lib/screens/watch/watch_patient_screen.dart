import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:wear_plus/wear_plus.dart';
import 'dart:async';
import 'dart:math';
import '../../services/notification_service.dart';

// ─── Design tokens ─────────────────────────────────────────────────────────────
const _kBg        = Color(0xFFF9EDE8);
const _kCard      = Color(0xFFEDD5D0);
const _kDivider   = Color(0xFFD9B8B4);
const _kEmergency = Color(0xFFE8736C);
const _kAction    = Color(0xFF8FA9C9);
const _kTextDark  = Color(0xFF3D2C31);
const _kTextMid   = Color(0xFF7A5A5A);
const _kTextMuted = Color(0xFFA08080);

// Base style — suppresses watch spell-check squiggles on every Text
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

class _WatchPatientScreenState extends State<WatchPatientScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Scroll controller drives the collapsing header
  final ScrollController _scrollCtrl = ScrollController();

  List<Map<String, dynamic>> _reminders = [];
  bool _isLoading    = true;
  bool _isRefreshing = false;
  bool _refreshExploded = false;

  Timer? _checkTimer;
  StreamSubscription<QuerySnapshot>? _reminderSub;
  final Set<String> _shownDialogs = {};

  String _firstName = '';

  // Header collapses over the first 36 px of scroll
  static const double _headerMax  = 36.0;
  static const double _headerMin  = 0.0;
  double get _scrollOffset =>
      _scrollCtrl.hasClients ? _scrollCtrl.offset.clamp(0.0, _headerMax) : 0.0;
  double get _headerHeight =>
      (_headerMax - _scrollOffset).clamp(_headerMin, _headerMax);
  double get _headerOpacity =>
      (1.0 - _scrollOffset / _headerMax).clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(() => setState(() {}));
    _loadPatientName();
    _loadReminders();
    _setupListener();
    _checkTimer = Timer.periodic(
        const Duration(seconds: 30), (_) { if (mounted) _checkDue(); });
    NotificationService.onNotificationTap = _showReminderDialog;
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _checkTimer?.cancel();
    _reminderSub?.cancel();
    super.dispose();
  }

  // ── Data ────────────────────────────────────────────────────────────────────

  Future<void> _loadPatientName() async {
    try {
      final doc =
      await _firestore.collection('users').doc(widget.patientId).get();
      if (!doc.exists || !mounted) return;
      final d    = doc.data()!;
      final full =
      '${d['firstName'] ?? ''} ${d['lastName'] ?? ''}'.trim();
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
      Timestamp.fromDate(
          DateTime(now.year, now.month, now.day, 23, 59, 59)))
          .orderBy('time')
          .get();
      if (mounted) {
        setState(() {
          _reminders =
              snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('loadReminders: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    setState(() { _isRefreshing = true; _refreshExploded = false; });
    await _loadReminders();
    await _checkDue();
    if (mounted) setState(() => _refreshExploded = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) setState(() => _isRefreshing = false);
  }

  void _setupListener() {
    _reminderSub = _firestore
        .collection('reminders')
        .where('patientId', isEqualTo: widget.patientId)
        .where('completed', isEqualTo: false)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final now = DateTime.now();
      for (final doc in snap.docs) {
        final r  = doc.data();
        final tv = r['time'];
        if (tv == null || r['acknowledgedEarly'] == true) continue;
        final t    = (tv as Timestamp).toDate();
        final diff = now.difference(t);
        if (diff.inSeconds >= 0 && diff.inSeconds < 60) {
          _showReminderDialog({
            'reminderId': doc.id,
            'title': r['title'] ?? 'Reminder',
            'time': DateFormat('h:mm a').format(t.toLocal()),
            'timestamp': t.millisecondsSinceEpoch,
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
          .orderBy('time')
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return;
      final doc = snap.docs.first;
      final r   = doc.data();
      final tv  = r['time'];
      if (tv == null || r['acknowledgedEarly'] == true) return;
      final t = (tv as Timestamp).toDate();
      _showReminderDialog({
        'reminderId': doc.id,
        'title': r['title'] ?? 'Reminder',
        'time': DateFormat('h:mm a').format(t.toLocal()),
        'timestamp': t.millisecondsSinceEpoch,
      });
    } catch (e) { debugPrint('checkDue: $e'); }
  }

  void _showReminderDialog(Map<String, dynamic> data) {
    if (!mounted) return;
    final id = data['reminderId'] ?? '';
    if (id.isEmpty || _shownDialogs.contains(id)) return;
    _shownDialogs.add(id);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => WatchReminderDialog(
        title: data['title'] ?? 'Reminder',
        time: data['time'] ?? '',
        reminderId: id,
        timestamp: data['timestamp'],
      ),
    ).then((_) { _shownDialogs.remove(id); _loadReminders(); });
  }

  // ── Build ───────────────────────────────────────────────────────────────────

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
              style: _kBase.copyWith(
                  color: _kAction, fontSize: 10, letterSpacing: 2)),
          if (_reminders.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              DateFormat('h:mm a').format(
                  (_reminders.first['time'] as Timestamp).toDate()),
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
          // Safe inset: distance from circle edge to inscribed square corner
          final r   = bc.maxWidth / 2;
          final ins = r * (1 - 1 / sqrt2) + 6;

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.all(ins),
              child: _isLoading ? _buildLoader() : _buildBody(),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildLoader() {
    return const Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 22, height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: _kAction),
        ),
        SizedBox(height: 8),
        Text('Loading…',
            style: TextStyle(
              color: _kTextMuted, fontSize: 9,
              decoration: TextDecoration.none,
            )),
      ]),
    );
  }

  Widget _buildBody() {
    return Stack(children: [
      Column(children: [
        // ── Collapsing greeting header ─────────────────────────────────────
        // ClipRect stops the text painting outside its shrinking box
        ClipRect(
          child: SizedBox(
            height: _headerHeight,
            child: Opacity(
              opacity: _headerOpacity,
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  _firstName.isNotEmpty
                      ? 'Here are your reminders, $_firstName'
                      : 'Here are your reminders',
                  style: _kBase.copyWith(
                    color: _kTextDark,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.clip,
                ),
              ),
            ),
          ),
        ),

        // Small gap that also collapses proportionally
        SizedBox(height: _headerOpacity * 6),

        // ── Scrollable reminder list ───────────────────────────────────────
        Expanded(
          child: _reminders.isEmpty
              ? _buildEmpty()
              : ListView.separated(
            controller: _scrollCtrl,
            padding: EdgeInsets.zero,
            // Extra bottom item = refresh button
            itemCount: _reminders.length + 1,
            separatorBuilder: (_, i) =>
            i < _reminders.length - 1
                ? const SizedBox(height: 4)
                : const SizedBox.shrink(),
            itemBuilder: (_, i) {
              if (i == _reminders.length) return _buildRefreshButton();
              return _buildTile(i);
            },
          ),
        ),
      ]),

      // Fwoop overlay
      if (_isRefreshing)
        _FwoopRefreshOverlay(exploded: _refreshExploded),
    ]);
  }

  Widget _buildEmpty() {
    return Column(children: [
      Expanded(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.check_circle_outline,
                color: _kAction.withOpacity(0.5), size: 22),
            const SizedBox(height: 6),
            Text('No reminders today',
                style: _kBase.copyWith(color: _kTextMuted, fontSize: 8.5),
                textAlign: TextAlign.center),
          ]),
        ),
      ),
      _buildRefreshButton(),
    ]);
  }

  Widget _buildRefreshButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Center(
        child: GestureDetector(
          onTap: _handleRefresh,
          child: Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _kAction.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border:
              Border.all(color: _kAction.withOpacity(0.35), width: 0.8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.refresh, color: _kAction, size: 10),
              const SizedBox(width: 3),
              Text('Refresh',
                  style: _kBase.copyWith(
                      color: _kAction,
                      fontSize: 8,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildTile(int i) {
    final r       = _reminders[i];
    final time    = (r['time'] as Timestamp?)?.toDate();
    final timeStr = time != null
        ? DateFormat('h:mm a').format(time.toLocal())
        : '';

    return GestureDetector(
      onTap: () => _showReminderDialog({
        'reminderId': r['id'],
        'title': r['title'] ?? 'Reminder',
        'time': timeStr,
        'timestamp': time?.millisecondsSinceEpoch,
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: _kDivider, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r['title'] ?? '',
                style: _kBase.copyWith(
                    color: _kTextDark,
                    fontSize: 9,
                    fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text(timeStr,
                style: _kBase.copyWith(
                    color: _kTextMuted, fontSize: 7.5)),
          ],
        ),
      ),
    );
  }
}

// ── Fwoop Refresh Overlay ──────────────────────────────────────────────────────

class _FwoopRefreshOverlay extends StatefulWidget {
  final bool exploded;
  const _FwoopRefreshOverlay({required this.exploded});

  @override
  State<_FwoopRefreshOverlay> createState() => _FwoopRefreshOverlayState();
}

class _FwoopRefreshOverlayState extends State<_FwoopRefreshOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _spinCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _explodeCtrl;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _pulseAnim;
  late final Animation<double> _explodeAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.88, end: 1.12).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _explodeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _explodeAnim =
        CurvedAnimation(parent: _explodeCtrl, curve: Curves.easeOut);
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = Tween<double>(begin: 1, end: 0).animate(_fadeCtrl);
  }

  @override
  void didUpdateWidget(_FwoopRefreshOverlay old) {
    super.didUpdateWidget(old);
    if (widget.exploded && !old.exploded) {
      _spinCtrl.stop();
      _pulseCtrl.stop();
      _explodeCtrl.forward().then((_) => _fadeCtrl.forward());
    }
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    _pulseCtrl.dispose();
    _explodeCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Container(
          decoration: BoxDecoration(
              color: _kBg.withOpacity(0.85), shape: BoxShape.circle),
          child: Center(
            child: SizedBox(
              width: 70, height: 70,
              child: Stack(alignment: Alignment.center, children: [
                AnimatedBuilder(
                  animation: _explodeAnim,
                  builder: (_, __) {
                    if (_explodeAnim.value == 0)
                      return const SizedBox.shrink();
                    return CustomPaint(
                        size: const Size(70, 70),
                        painter: _ExplosionPainter(
                            progress: _explodeAnim.value));
                  },
                ),
                AnimatedBuilder(
                  animation:
                  Listenable.merge([_spinCtrl, _pulseAnim]),
                  builder: (_, __) => Transform.scale(
                    scale:
                    widget.exploded ? 1.35 : _pulseAnim.value,
                    child: Transform.rotate(
                      angle: widget.exploded
                          ? 0
                          : _spinCtrl.value * 2 * pi,
                      child: Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _kAction.withOpacity(0.15),
                          border:
                          Border.all(color: _kAction, width: 1.5),
                        ),
                        child: widget.exploded
                            ? const Icon(Icons.check,
                            color: _kAction, size: 20)
                            : Padding(
                          padding: const EdgeInsets.all(8),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _kAction,
                            backgroundColor:
                            _kAction.withOpacity(0.2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Explosion Painter ──────────────────────────────────────────────────────────

class _ExplosionPainter extends CustomPainter {
  final double progress;
  static const int _n = 12;
  static final List<Color> _colors = [
    _kEmergency, _kAction, const Color(0xFFB8CCE0),
    const Color(0xFFFFD54F), const Color(0xFF81C784),
  ];
  const _ExplosionPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rng    = Random(42);
    for (int i = 0; i < _n; i++) {
      final angle   = (i / _n) * 2 * pi + rng.nextDouble() * 0.5;
      final dist    = size.width * 0.5 * progress;
      final opacity = (1.0 - progress).clamp(0.0, 1.0);
      final radius  = (3.5 * (1 - progress * 0.5)).clamp(1.0, 5.0);
      canvas.drawCircle(
        Offset(center.dx + cos(angle) * dist,
            center.dy + sin(angle) * dist),
        radius,
        Paint()
          ..color =
          _colors[i % _colors.length].withOpacity(opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_ExplosionPainter old) =>
      old.progress != progress;
}

// ── Watch Reminder Dialog ──────────────────────────────────────────────────────

class WatchReminderDialog extends StatelessWidget {
  final String title;
  final String time;
  final String reminderId;
  final dynamic timestamp;

  const WatchReminderDialog({
    super.key,
    required this.title,
    required this.time,
    required this.reminderId,
    this.timestamp,
  });

  Future<void> _markComplete() async {
    final scheduled = timestamp != null
        ? DateTime.fromMillisecondsSinceEpoch(timestamp as int)
        : null;
    final ref = FirebaseFirestore.instance
        .collection('reminders')
        .doc(reminderId);
    if (scheduled != null && DateTime.now().isBefore(scheduled)) {
      await ref.update({'acknowledgedEarly': true});
    } else {
      await ref.update({'completed': true});
    }
  }

  Future<void> _snooze() async {
    await FirebaseFirestore.instance
        .collection('reminders')
        .doc(reminderId)
        .update({
      'time': Timestamp.fromDate(
          DateTime.now().add(const Duration(minutes: 5))),
      'completed': false,
      'isSnoozed': true,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(10),
      child: Container(
        decoration: BoxDecoration(
          color: _kBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _kDivider, width: 1),
          boxShadow: [
            BoxShadow(
                color: _kEmergency.withOpacity(0.15),
                blurRadius: 20,
                spreadRadius: 2),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kEmergency.withOpacity(0.14),
            ),
            child: const Icon(Icons.notifications_active,
                color: _kEmergency, size: 18),
          ),
          const SizedBox(height: 7),
          Text(title,
              style: _kBase.copyWith(
                  color: _kTextDark,
                  fontSize: 11,
                  fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(time,
              style: _kBase.copyWith(
                  color: _kAction,
                  fontSize: 10,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity, height: 30,
            child: ElevatedButton(
              onPressed: () async {
                await _markComplete();
                if (context.mounted) Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAction,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9)),
              ),
              child: Text('Done',
                  style: _kBase.copyWith(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            width: double.infinity, height: 28,
            child: OutlinedButton(
              onPressed: () async {
                await _snooze();
                if (context.mounted) Navigator.of(context).pop();
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: _kTextMid,
                backgroundColor: _kCard,
                side: const BorderSide(color: _kDivider, width: 1),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9)),
              ),
              child: Text('+5 min',
                  style: _kBase.copyWith(
                      color: _kTextMid,
                      fontSize: 10,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }
}