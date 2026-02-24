import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:wear_plus/wear_plus.dart';
import 'dart:async';
import 'dart:math';
import '../../services/notification_service.dart';

class WatchPatientScreen extends StatefulWidget {
  final String patientId;

  const WatchPatientScreen({super.key, required this.patientId});

  @override
  State<WatchPatientScreen> createState() => _WatchPatientScreenState();
}

class _WatchPatientScreenState extends State<WatchPatientScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _reminders = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _refreshExploded = false;
  Timer? _checkTimer;
  StreamSubscription<QuerySnapshot>? _reminderSubscription;
  final Set<String> _shownDialogs = {};
  String _patientName = '';

  @override
  void initState() {
    super.initState();
    _loadReminders();
    _loadPatientName();
    _setupReminderListener();

    _checkTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _checkForDueReminders();
    });

    NotificationService.onNotificationTap = (data) {
      _showWatchReminderDialog(data);
    };
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    _reminderSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadReminders() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

    try {
      final snapshot = await _firestore
          .collection('reminders')
          .where('patientId', isEqualTo: widget.patientId)
          .where('completed', isEqualTo: false)
          .where('time', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('time', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .orderBy('time')
          .get();

      if (mounted) {
        setState(() {
          _reminders = snapshot.docs
              .map((doc) => {'id': doc.id, ...doc.data()})
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('WatchPatientScreen _loadReminders error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPatientName() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.patientId)
          .get();
      if (doc.exists && mounted) {
        final data = doc.data();
        setState(() {
          _patientName =
              '${data?['firstName'] ?? ''} ${data?['lastName'] ?? ''}'.trim();
        });
      }
    } catch (e) {
      debugPrint('Could not load patient name: $e');
    }
  }

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    _dragStartY = null;
    setState(() {
      _isRefreshing = true;
      _refreshExploded = false;
    });
    await _loadReminders();
    await _checkForDueReminders();
    if (mounted) setState(() => _refreshExploded = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) setState(() => _isRefreshing = false);
  }

  void _setupReminderListener() {
    _reminderSubscription = _firestore
        .collection('reminders')
        .where('patientId', isEqualTo: widget.patientId)
        .where('completed', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      final now = DateTime.now();
      for (var doc in snapshot.docs) {
        final reminder = doc.data();
        final timeValue = reminder['time'];
        if (timeValue == null) continue;

        final time = (timeValue as Timestamp).toDate();
        final diff = now.difference(time);

        if (reminder['acknowledgedEarly'] == true) continue;

        if (diff.inSeconds >= 0 && diff.inSeconds < 60) {
          final timeStr = DateFormat('h:mm a').format(time.toLocal());
          _showWatchReminderDialog({
            'reminderId': doc.id,
            'title': reminder['title'] ?? 'Reminder',
            'description': reminder['description'] ?? '',
            'time': timeStr,
            'timestamp': time.millisecondsSinceEpoch,
          });
          break;
        }
      }

      _loadReminders();
    }, onError: (e) => debugPrint('Reminder listener error: $e'));
  }

  Future<void> _checkForDueReminders() async {
    try {
      final snapshot = await _firestore
          .collection('reminders')
          .where('patientId', isEqualTo: widget.patientId)
          .where('completed', isEqualTo: false)
          .where('time', isLessThanOrEqualTo: Timestamp.now())
          .orderBy('time')
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final reminder = doc.data();
        final timeValue = reminder['time'];
        if (timeValue == null) return;

        final time = (timeValue as Timestamp).toDate();
        final timeStr = DateFormat('h:mm a').format(time.toLocal());

        if (reminder['acknowledgedEarly'] == true) return;

        _showWatchReminderDialog({
          'reminderId': doc.id,
          'title': reminder['title'] ?? 'Reminder',
          'description': reminder['description'] ?? '',
          'time': timeStr,
          'timestamp': time.millisecondsSinceEpoch,
        });
      }
    } catch (e) {
      debugPrint('WatchPatientScreen _checkForDueReminders error: $e');
    }
  }

  void _showWatchReminderDialog(Map<String, dynamic> data) {
    if (!mounted) return;
    final reminderId = data['reminderId'] ?? '';
    if (reminderId.isEmpty || _shownDialogs.contains(reminderId)) return;

    _shownDialogs.add(reminderId);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => WatchReminderDialog(
        title: data['title'] ?? 'Reminder',
        time: data['time'] ?? '',
        reminderId: reminderId,
        timestamp: data['timestamp'],
      ),
    ).then((_) {
      _shownDialogs.remove(reminderId);
      _loadReminders();
    });
  }

  @override
  Widget build(BuildContext context) {
    return WatchShape(
      builder: (context, shape, _) {
        return AmbientMode(
          builder: (context, mode, _) {
            if (mode == WearMode.ambient) return _buildAmbientScreen();
            return _buildActiveScreen();
          },
        );
      },
    );
  }

  Widget _buildAmbientScreen() {
    final nextReminder = _reminders.isNotEmpty ? _reminders.first : null;
    final time = nextReminder != null
        ? DateFormat('h:mm a')
        .format((nextReminder['time'] as Timestamp).toDate())
        : null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('CogniCare',
                style: TextStyle(color: Colors.white, fontSize: 12)),
            if (time != null) ...[
              const SizedBox(height: 4),
              Text('Next: $time',
                  style: const TextStyle(color: Colors.grey, fontSize: 10)),
            ]
          ],
        ),
      ),
    );
  }

  double? _dragStartY;

  Widget _buildActiveScreen() {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => _dragStartY = e.position.dy,
      onPointerUp: (e) {
        if (_dragStartY != null) {
          final delta = e.position.dy - _dragStartY!;
          if (delta > 40) _handleRefresh();
          _dragStartY = null;
        }
      },
      onPointerCancel: (_) => _dragStartY = null,
      child: ClipOval(
        child: ColoredBox(
          color: const Color(0xFFF5E6D3),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildContent(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Stack(
      children: [
        _reminders.isEmpty ? _buildEmptyState() : _buildReminderList(),
        if (_isRefreshing) _FwoopRefreshOverlay(exploded: _refreshExploded),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (_patientName.isNotEmpty) ...[
            Text(
              'Welcome, $_patientName',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF3D2C31)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
          ],
          const Text('↑ swipe to refresh',
              style: TextStyle(fontSize: 8, color: Colors.grey)),
          const SizedBox(height: 8),
          const Text('No reminders today',
              style: TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildReminderList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          _patientName.isNotEmpty ? 'Welcome, $_patientName' : 'Today',
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFF3D2C31)),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        const Text(
          '↓ swipe to refresh',
          style: TextStyle(fontSize: 7, color: Colors.grey),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: false,
            itemCount: _reminders.length,
            itemBuilder: (context, index) {
              final reminder = _reminders[index];
              final time = (reminder['time'] as Timestamp?)?.toDate();
              final timeStr = time != null
                  ? DateFormat('h:mm a').format(time.toLocal())
                  : '';
              final isSnoozed = reminder['isSnoozed'] == true;
              final acknowledgedEarly = reminder['acknowledgedEarly'] == true;
              final isNext = index == 0;

              final statusPrefix = acknowledgedEarly
                  ? 'Seen'
                  : isSnoozed
                  ? 'Snoozed'
                  : isNext
                  ? 'Next'
                  : 'Reminder';

              return GestureDetector(
                onTap: () => _showWatchReminderDialog({
                  'reminderId': reminder['id'],
                  'title': reminder['title'] ?? 'Reminder',
                  'description': reminder['description'] ?? '',
                  'time': timeStr,
                  'timestamp': time?.millisecondsSinceEpoch,
                }),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (index > 0)
                        Divider(
                          height: 1,
                          thickness: 0.5,
                          color: Colors.grey.withOpacity(0.3),
                        ),
                      if (index > 0) const SizedBox(height: 5),
                      Text(
                        '$statusPrefix:  ${reminder['title'] ?? ''}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                          isNext ? FontWeight.bold : FontWeight.normal,
                          color: acknowledgedEarly
                              ? Colors.grey
                              : const Color(0xFF3D2C31),
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        timeStr,
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
} // ← END of _WatchPatientScreenState

// ─── Fwoop Refresh Overlay ───────────────────────────────────────────────────

class _FwoopRefreshOverlay extends StatefulWidget {
  final bool exploded;
  const _FwoopRefreshOverlay({required this.exploded});

  @override
  State<_FwoopRefreshOverlay> createState() => _FwoopRefreshOverlayState();
}

class _FwoopRefreshOverlayState extends State<_FwoopRefreshOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _spinController;
  late final AnimationController _pulseController;
  late final AnimationController _explodeController;
  late final AnimationController _fadeController;

  late final Animation<double> _pulseAnim;
  late final Animation<double> _explodeAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();

    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.elasticInOut),
    );

    _explodeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _explodeAnim =
        CurvedAnimation(parent: _explodeController, curve: Curves.easeOut);

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnim = Tween<double>(begin: 1.0, end: 0.0).animate(_fadeController);
  }

  @override
  void didUpdateWidget(_FwoopRefreshOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.exploded && !oldWidget.exploded) {
      _spinController.stop();
      _pulseController.stop();
      _explodeController.forward().then((_) => _fadeController.forward());
    }
  }

  @override
  void dispose() {
    _spinController.dispose();
    _pulseController.dispose();
    _explodeController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Center(
          child: SizedBox(
            width: 70,
            height: 70,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _explodeAnim,
                  builder: (_, __) {
                    if (_explodeAnim.value == 0) return const SizedBox.shrink();
                    return CustomPaint(
                      size: const Size(70, 70),
                      painter:
                      _ExplosionPainter(progress: _explodeAnim.value),
                    );
                  },
                ),
                AnimatedBuilder(
                  animation:
                  Listenable.merge([_spinController, _pulseAnim]),
                  builder: (_, __) {
                    return Transform.scale(
                      scale: widget.exploded ? 1.4 : _pulseAnim.value,
                      child: Transform.rotate(
                        angle: widget.exploded
                            ? 0
                            : _spinController.value * 2 * pi,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF8FA9C9).withOpacity(0.4),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: widget.exploded
                              ? const Icon(Icons.check,
                              color: Color(0xFF8FA9C9), size: 20)
                              : Padding(
                            padding: const EdgeInsets.all(6),
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: const Color(0xFF8FA9C9),
                              backgroundColor:
                              const Color(0xFF8FA9C9).withOpacity(0.2),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Explosion Painter ───────────────────────────────────────────────────────

class _ExplosionPainter extends CustomPainter {
  final double progress;
  static const int _particleCount = 10;
  static final List<Color> _colors = [
    const Color(0xFF8FA9C9),
    const Color(0xFFE8C4C8),
    const Color(0xFFF5E6D3),
    Colors.orangeAccent,
    Colors.lightGreenAccent,
  ];

  const _ExplosionPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final random = Random(42);

    for (int i = 0; i < _particleCount; i++) {
      final angle =
          (i / _particleCount) * 2 * pi + random.nextDouble() * 0.4;
      final distance = (size.width * 0.55) * progress;
      final opacity = (1.0 - progress).clamp(0.0, 1.0);
      final radius = (3.5 * (1 - progress * 0.5)).clamp(1.0, 5.0);

      final particleOffset = Offset(
        center.dx + cos(angle) * distance,
        center.dy + sin(angle) * distance,
      );

      final paint = Paint()
        ..color = _colors[i % _colors.length].withOpacity(opacity)
        ..style = PaintingStyle.fill;

      if (i % 3 == 0) {
        final path = Path();
        const starSize = 4.0;
        for (int s = 0; s < 4; s++) {
          final starAngle = (s / 4) * 2 * pi * progress;
          final tip = Offset(
            particleOffset.dx +
                cos(starAngle) * starSize * (1 - progress * 0.6),
            particleOffset.dy +
                sin(starAngle) * starSize * (1 - progress * 0.6),
          );
          if (s == 0) {
            path.moveTo(tip.dx, tip.dy);
          } else {
            path.lineTo(tip.dx, tip.dy);
          }
        }
        path.close();
        canvas.drawPath(path, paint);
      } else {
        canvas.drawCircle(particleOffset, radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_ExplosionPainter old) => old.progress != progress;
}

// ─── Watch Reminder Dialog ───────────────────────────────────────────────────

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
    final scheduledTime = timestamp != null
        ? DateTime.fromMillisecondsSinceEpoch(timestamp as int)
        : null;
    final now = DateTime.now();

    if (scheduledTime != null && now.isBefore(scheduledTime)) {
      await FirebaseFirestore.instance
          .collection('reminders')
          .doc(reminderId)
          .update({'acknowledgedEarly': true});
    } else {
      await FirebaseFirestore.instance
          .collection('reminders')
          .doc(reminderId)
          .update({'completed': true});
    }
  }

  Future<void> _snooze() async {
    final newTime = DateTime.now().add(const Duration(minutes: 5));
    await FirebaseFirestore.instance
        .collection('reminders')
        .doc(reminderId)
        .update({
      'time': Timestamp.fromDate(newTime),
      'completed': false,
      'isSnoozed': true,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF5E6E8),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.notifications_active,
                color: Color(0xFF8FA9C9), size: 22),
            const SizedBox(height: 4),
            Text(
              title,
              style:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Text(time,
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 32,
              child: ElevatedButton(
                onPressed: () async {
                  await _markComplete();
                  if (context.mounted) Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8FA9C9),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Done', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              height: 32,
              child: OutlinedButton(
                onPressed: () async {
                  await _snooze();
                  if (context.mounted) Navigator.of(context).pop();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF8FA9C9),
                  side: const BorderSide(color: Color(0xFF8FA9C9)),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('+5 min', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}