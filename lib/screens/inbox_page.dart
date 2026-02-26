import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../services/auth_service.dart';

// ─── Models ──────────────────────────────────────────────────────────────────

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

class _InboxPageState extends State<InboxPage> {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<NotificationItem> _notifications = [];
  bool _isLoading = true;
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _startListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
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

      // Mark unread as read BEFORE setState to prevent flicker
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
          timestamp: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          isRead: true,
        );
      }).toList();

      setState(() {
        _notifications = items;
        _isLoading = false;
      });

      if (writeFutures.isNotEmpty) {
        try {
          await Future.wait(writeFutures);
        } catch (e) {
          print('Warning: could not mark alerts as read: $e');
        }
      }
    }, onError: (e) {
      print('Error listening for caretaker alerts: $e');
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
            fromName: '${otherUserData['firstName']} ${otherUserData['lastName']}',
            isCaretaker: false,
            requestId: doc.id,
            fromUserId: caretakerId,
            timestamp: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          ));
        }
      }

      items.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      if (mounted) {
        setState(() {
          _notifications = items;
          _isLoading = false;
        });
      }
    }, onError: (e) {
      print('Error listening for connection requests: $e');
      setState(() => _isLoading = false);
    });
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connection request accepted!'),
            backgroundColor: Color(0xFF8FA9C9),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      print('Error accepting request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to accept: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _rejectRequest(NotificationItem notification) async {
    try {
      await _firestore
          .collection('patient_caretaker_relationships')
          .doc(notification.requestId)
          .delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connection request rejected'),
            backgroundColor: Colors.grey,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      print('Error rejecting request: $e');
    }
  }

  Future<void> _deleteAlert(NotificationItem notification) async {
    try {
      if (notification.alertId == null) return;
      await _firestore.collection('caretaker_alerts').doc(notification.alertId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alert dismissed'), backgroundColor: Colors.grey, behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      print('Error deleting alert: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5E6E8),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _notifications.isEmpty
                  ? _buildEmpty()
                  : _buildList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8C4C8),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Color(0xFF3D2C31)),
            style: IconButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.5), padding: const EdgeInsets.all(8)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Inbox', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF3D2C31))),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.5), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.inbox, color: Color(0xFFD47A8A), size: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox, size: 80, color: const Color(0xFF8FA9C9).withOpacity(0.5)),
          const SizedBox(height: 16),
          const Text('All caught up!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Color(0xFF5A4046))),
          const SizedBox(height: 8),
          const Text('No notifications right now', style: TextStyle(fontSize: 14, color: Color(0xFF7A6A70))),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: _notifications.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildNotificationItem(_notifications[index]),
    );
  }

  Widget _buildNotificationItem(NotificationItem notification) {
    final isRequest = notification.type == NotificationType.connectionRequest;
    final isMissedReminder = notification.type == NotificationType.missedReminder;

    return Container(
      decoration: BoxDecoration(
        color: notification.isRead ? Colors.white : const Color(0xFFFFF9E6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: notification.isRead ? const Color(0xFFE8C4C8) : const Color(0xFFFFD700),
          width: 2,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isMissedReminder ? const Color(0xFFFFE0E0) : const Color(0xFF8FA9C9).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isMissedReminder ? Icons.warning_amber_rounded : Icons.person_add,
                    color: isMissedReminder ? const Color(0xFFD47A8A) : const Color(0xFF8FA9C9),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: notification.isRead ? FontWeight.w600 : FontWeight.bold,
                                color: const Color(0xFF3D2C31),
                              ),
                            ),
                          ),
                          if (!notification.isRead)
                            Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFFF4757), shape: BoxShape.circle)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(notification.message, style: const TextStyle(fontSize: 14, color: Color(0xFF5A4046))),
                      const SizedBox(height: 8),
                      Text(_formatTimestamp(notification.timestamp), style: const TextStyle(fontSize: 12, color: Color(0xFF7A6A70), fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
              ],
            ),
            if (isRequest) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _acceptRequest(notification),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8FA9C9), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: const Text('Accept'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _rejectRequest(notification),
                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF3D2C31), side: const BorderSide(color: Color(0xFF3D2C31)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: const Text('Reject'),
                    ),
                  ),
                ],
              ),
            ],
            if (isMissedReminder) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _deleteAlert(notification),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Dismiss'),
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF7A6A70)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM dd, yyyy').format(timestamp);
  }
}