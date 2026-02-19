import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';

class ProfilePage extends StatefulWidget {
  final bool isCaretaker;

  const ProfilePage({
    super.key,
    required this.isCaretaker,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String userName = "Loading...";
  String? phone;
  String? address;
  List<NotificationItem> notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = _authService.currentUser;
      if (user != null) {
        final userData = await _authService.getUserData(user.uid);
        if (userData != null) {
          setState(() {
            userName = '${userData['firstName']} ${userData['lastName']}';
            phone = userData['phone'];
          });
        }

        // Load patient-specific data
        if (!widget.isCaretaker) {
          final patientData = await _authService.getPatientData(user.uid);
          if (patientData != null) {
            setState(() {
              address = patientData['address'];
            });
          }
        }

        // Load notifications (connection requests)
        await _loadNotifications(user.uid);
      }
    } catch (e) {
      print('Error loading user data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadNotifications(String userId) async {
    try {
      // Only patients receive connection requests (caretakers send them; patients accept)
      if (widget.isCaretaker) {
        setState(() => notifications = []);
        return;
      }

      final snapshot = await _firestore
          .collection('patient_caretaker_relationships')
          .where('patientId', isEqualTo: userId)
          .where('status', isEqualTo: 'pending')
          .get();

      List<NotificationItem> newNotifications = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final caretakerId = data['caretakerId'];

        final otherUserData = await _authService.getUserData(caretakerId);
        if (otherUserData != null) {
          final otherUserName = '${otherUserData['firstName']} ${otherUserData['lastName']}';

          newNotifications.add(NotificationItem.connectionRequest(
            fromName: otherUserName,
            isCaretaker: false,
            requestId: doc.id,
            fromUserId: caretakerId,
            timestamp: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          ));
        }
      }

      setState(() {
        notifications = newNotifications;
      });
    } catch (e) {
      print('Error loading notifications: $e');
    }
  }

  Future<void> _acceptRequest(NotificationItem notification) async {
    try {
      // Update relationship status
      await _firestore
          .collection('patient_caretaker_relationships')
          .doc(notification.requestId)
          .update({
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
      });

      // If patient is accepting, add caretaker to their caretakers array
      if (!widget.isCaretaker) {
        // Update patient's document with caretaker reference (optional)
      }

      // Reload notifications
      await _loadUserData();

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
          SnackBar(
            content: Text('Failed to accept request: $e'),
            backgroundColor: Colors.red,
          ),
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

      await _loadUserData();

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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5E6E8),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5E6E8),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildProfileCard(),
                    const SizedBox(height: 20),
                    _buildInfoCard(),
                    const SizedBox(height: 20),
                    _buildInboxCard(),
                  ],
                ),
              ),
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
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Color(0xFF3D2C31)),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.5),
              padding: const EdgeInsets.all(8),
            ),
          ),
          const Text(
            'Profile Page',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF5A4046),
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            DateFormat('MMM dd, yyyy').format(DateTime.now()),
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF5A4046),
              fontWeight: FontWeight.w500,
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.favorite,
              color: Color(0xFFD47A8A),
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFE8C4C8),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              userName,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFF3D2C31),
              ),
            ),
          ),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.person,
              size: 45,
              color: Color(0xFF8FA9C9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFE8C4C8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFC09499),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'My Info:',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF3D2C31),
            ),
          ),
          const SizedBox(height: 20),
          _buildInfoRow('name:', userName),
          const SizedBox(height: 12),
          _buildInfoRow('phone:', phone ?? 'Not provided'),
          if (!widget.isCaretaker) ...[
            const SizedBox(height: 12),
            _buildInfoRow('address:', address ?? 'Not provided'),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF3D2C31),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            color: Color(0xFF5A4046),
          ),
        ),
      ],
    );
  }

  Widget _buildInboxCard() {
    final unreadCount = notifications.where((n) => !n.isRead).length;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFD4ADB1),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Inbox:',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF3D2C31),
                ),
              ),
              if (unreadCount > 0) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF4757),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$unreadCount',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (notifications.isEmpty)
          _buildEmptyInbox()
        else
          _buildNotificationsList(),
      ],
    );
  }

  Widget _buildEmptyInbox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFE8C4C8),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.inbox,
            size: 64,
            color: const Color(0xFF8FA9C9).withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'No notifications',
            style: TextStyle(
              fontSize: 18,
              color: Color(0xFF7A6A70),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsList() {
    return Column(
      children: notifications.map((notification) {
        return _buildNotificationItem(notification);
      }).toList(),
    );
  }

  Widget _buildNotificationItem(NotificationItem notification) {
    final isRequest = notification.type == NotificationType.connectionRequest;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: notification.isRead ? Colors.white : const Color(0xFFFFF9E6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: notification.isRead
              ? const Color(0xFFE8C4C8)
              : const Color(0xFFFFD700),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
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
                    color: const Color(0xFF8FA9C9).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.person_add,
                    color: Color(0xFF8FA9C9),
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
                                fontWeight: notification.isRead
                                    ? FontWeight.w600
                                    : FontWeight.bold,
                                color: const Color(0xFF3D2C31),
                              ),
                            ),
                          ),
                          if (!notification.isRead)
                            Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: Color(0xFFFF4757),
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        notification.message,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF5A4046),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatTimestamp(notification.timestamp),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF7A6A70),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (isRequest && !notification.isRead) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _acceptRequest(notification),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8FA9C9),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Accept'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _rejectRequest(notification),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF3D2C31),
                        side: const BorderSide(color: Color(0xFF3D2C31)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Reject'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('MMM dd, yyyy').format(timestamp);
    }
  }
}

// Notification Models
enum NotificationType {
  connectionRequest,
  scheduleUpdate,
}

class NotificationItem {
  final String title;
  final String message;
  final NotificationType type;
  final DateTime timestamp;
  final String? requestId;
  final String? fromUserId;
  bool isRead;

  NotificationItem({
    required this.title,
    required this.message,
    required this.type,
    required this.timestamp,
    this.requestId,
    this.fromUserId,
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
}