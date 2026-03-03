import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../services/auth_service.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

enum NotificationType {
  connectionRequest,
  scheduleUpdate,
  missedReminder,
}

class NotificationItem {
  final String title;
  final String message;
  final NotificationType type;
  final DateTime timestamp;
  final String? requestId;
  final String? fromUserId;
  final String? alertId;
  bool isRead;

  NotificationItem({
    required this.title,
    required this.message,
    required this.type,
    required this.timestamp,
    this.requestId,
    this.fromUserId,
    this.alertId,
    this.isRead = false,
  });

  factory NotificationItem.connectionRequest({
    required String fromName,
    required bool isCaretaker,
    required String requestId,
    required String fromUserId,
    DateTime? timestamp,
  }) {
    return NotificationItem(
      title: 'Connection Request',
      message: isCaretaker
          ? '$fromName wants to be added to your care list'
          : '$fromName wants to add you as their patient',
      type: NotificationType.connectionRequest,
      timestamp: timestamp ?? DateTime.now(),
      requestId: requestId,
      fromUserId: fromUserId,
    );
  }

  factory NotificationItem.scheduleUpdate({
    required String patientName,
    required String updatedBy,
    DateTime? timestamp,
  }) {
    return NotificationItem(
      title: 'Schedule Updated',
      message: '$updatedBy updated the schedule for $patientName',
      type: NotificationType.scheduleUpdate,
      timestamp: timestamp ?? DateTime.now(),
    );
  }

  factory NotificationItem.missedReminder({
    required String alertId,
    required String message,
    DateTime? timestamp,
    bool isRead = false,
  }) {
    return NotificationItem(
      title: 'Missed Reminder',
      message: message,
      type: NotificationType.missedReminder,
      timestamp: timestamp ?? DateTime.now(),
      alertId: alertId,
      isRead: isRead,
    );
  }
}

// ─── Page ─────────────────────────────────────────────────────────────────────

class InboxPage extends StatefulWidget {
  final bool isCaretaker;
  const InboxPage({super.key, required this.isCaretaker});

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage>
    with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<NotificationItem> _notifications = [];
  bool _isLoading = true;
  StreamSubscription? _subscription;

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
    _fadeAnimation =
        CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(
          CurvedAnimation(
              parent: _animController, curve: Curves.easeOutCubic),
        );
    _startListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _startListeners() async {
    final user = _authService.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }
    if (widget.isCaretaker) {
      _listenForCaretakerAlerts(user.uid);
    } else {
      _listenForConnectionRequests(user.uid);
    }
  }

  void _listenForCaretakerAlerts(String userId) {
    _subscription = _firestore
        .collection('caretaker_alerts')
        .where('caretakerId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) async {
      if (!mounted) return;

      final writeFutures = <Future>[];
      for (final doc in snapshot.docs) {
        if (doc.data()['isRead'] != true) {
          writeFutures.add(doc.reference.update({'isRead': true}));
        }
      }

      final items = snapshot.docs.map((doc) {
        final data = doc.data();
        return NotificationItem.missedReminder(
          alertId: doc.id,
          message: data['message'] ?? 'A patient missed a reminder',
          timestamp:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          isRead: true,
        );
      }).toList();

      setState(() {
        _notifications = items;
        _isLoading = false;
      });
      _animController.forward();

      if (writeFutures.isNotEmpty) {
        try {
          await Future.wait(writeFutures);
        } catch (e) {
          debugPrint('Warning: could not mark alerts as read: $e');
        }
      }
    }, onError: (e) {
      debugPrint('Error listening for caretaker alerts: $e');
      setState(() => _isLoading = false);
    });
  }

  void _listenForConnectionRequests(String userId) {
    _subscription = _firestore
        .collection('patient_caretaker_relationships')
        .where('patientId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) async {
      if (!mounted) return;

      List<NotificationItem> items = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final caretakerId = data['caretakerId'] as String?;
        if (caretakerId == null) continue;
        final otherUserData = await _authService.getUserData(caretakerId);
        if (otherUserData != null) {
          items.add(NotificationItem.connectionRequest(
            fromName:
            '${otherUserData['firstName']} ${otherUserData['lastName']}',
            isCaretaker: false,
            requestId: doc.id,
            fromUserId: caretakerId,
            timestamp:
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          ));
        }
      }

      items.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      if (mounted) {
        setState(() {
          _notifications = items;
          _isLoading = false;
        });
        _animController.forward();
      }
    }, onError: (e) {
      debugPrint('Error listening for connection requests: $e');
      setState(() => _isLoading = false);
    });
  }

  void _showSnack(String message, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor:
        success ? const Color(0xFF5A7A1A) : const Color(0xFF8D6E63),
        behavior: SnackBarBehavior.floating,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _acceptRequest(NotificationItem notification) async {
    try {
      await _firestore
          .collection('patient_caretaker_relationships')
          .doc(notification.requestId)
          .update({
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) _showSnack('Connection accepted!', success: true);
    } catch (e) {
      if (mounted) _showSnack('Failed to accept request');
    }
  }

  Future<void> _rejectRequest(NotificationItem notification) async {
    try {
      await _firestore
          .collection('patient_caretaker_relationships')
          .doc(notification.requestId)
          .delete();
      if (mounted) _showSnack('Request declined');
    } catch (e) {
      debugPrint('Error rejecting request: $e');
    }
  }

  Future<void> _deleteAlert(NotificationItem notification) async {
    try {
      if (notification.alertId == null) return;
      await _firestore
          .collection('caretaker_alerts')
          .doc(notification.alertId)
          .delete();
      if (mounted) _showSnack('Alert dismissed');
    } catch (e) {
      debugPrint('Error deleting alert: $e');
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d, yyyy').format(timestamp);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF6F4),
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
            child: Column(
              children: [
                // ── Top bar ──────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color:
                                const Color(0xFFB07A6E).withOpacity(0.12),
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
                      // Unread badge
                      if (_notifications.any((n) => !n.isRead))
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE57373).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_notifications.where((n) => !n.isRead).length} new',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFE57373),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Page title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Inbox',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF3E2723),
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            'Notifications & requests',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF8D6E63),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Body ─────────────────────────────────────────
                Expanded(
                  child: _isLoading
                      ? const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF5A7A1A)),
                  )
                      : _notifications.isEmpty
                      ? _buildEmpty()
                      : FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: _buildList(),
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

  Widget _buildEmpty() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFB07A6E).withOpacity(0.10),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.inbox_outlined,
                size: 32,
                color: Color(0xFFD4A5A5),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'All caught up',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF3E2723),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'No notifications right now',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF8D6E63),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      itemCount: _notifications.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _buildCard(_notifications[i]),
    );
  }

  Widget _buildCard(NotificationItem notification) {
    final isRequest = notification.type == NotificationType.connectionRequest;
    final isMissed = notification.type == NotificationType.missedReminder;
    final isUnread = !notification.isRead;

    // Icon + color per type
    final IconData iconData = isMissed
        ? Icons.alarm_off_rounded
        : Icons.person_add_alt_1_rounded;
    final Color iconBg = isMissed
        ? const Color(0xFFFFEDED)
        : const Color(0xFFF4E4E1);
    final Color iconColor = isMissed
        ? const Color(0xFFE57373)
        : const Color(0xFFD4A5A5);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: isUnread
            ? Border.all(color: const Color(0xFF5A7A1A).withOpacity(0.25), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB07A6E).withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(iconData, color: iconColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF3E2723),
                              ),
                            ),
                          ),
                          if (isUnread)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF5A7A1A),
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notification.message,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF8D6E63),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatTimestamp(notification.timestamp),
                        style: TextStyle(
                          fontSize: 12,
                          color: const Color(0xFF8D6E63).withOpacity(0.6),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Accept / reject row
            if (isRequest) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: ElevatedButton(
                        onPressed: () => _acceptRequest(notification),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5A7A1A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: const Text('Accept',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: OutlinedButton(
                        onPressed: () => _rejectRequest(notification),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF8D6E63),
                          side: const BorderSide(
                              color: Color(0xFFEDE5E2), width: 1.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Decline',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // Dismiss row for missed reminders
            if (isMissed) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => _deleteAlert(notification),
                  child: Text(
                    'Dismiss',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF8D6E63).withOpacity(0.7),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}