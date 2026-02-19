import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Handling background message: ${message.messageId}');
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  static Function(Map<String, dynamic>)? onNotificationTap;

  // Track shown notifications with composite keys: "reminderId:timestamp" or "reminderId:snooze:timestamp"
  // This ensures one notification per scheduled time, with snooze creating a new unique notification
  static final Map<String, DateTime> _shownNotifications = {};
  static bool _isInitialized = false;
  static bool _timezoneInitialized = false;

  static Future<void> initialize() async {
    if (_isInitialized) {
      print('NotificationService already initialized');
      return;
    }

    // Initialize timezone data ONCE
    if (!_timezoneInitialized) {
      try {
        tz_data.initializeTimeZones();
        tz.setLocalLocation(tz.getLocation('America/New_York')); // Change to your timezone
        _timezoneInitialized = true;
        print('Timezone initialized');
      } catch (e) {
        print('Error initializing timezone: $e');
      }
    }

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        print('Notification tapped: ${details.payload}');
        if (details.payload != null && onNotificationTap != null) {
          try {
            final data = json.decode(details.payload!);
            final reminderId = data['reminderId'] as String?;
            final timestampValue = data['timestamp'];

            if (reminderId != null) {
              DateTime? scheduledTime;
              if (timestampValue != null) {
                // Handle both int and string timestamp
                final timestampInt = timestampValue is int
                    ? timestampValue
                    : int.tryParse(timestampValue.toString());

                if (timestampInt != null) {
                  scheduledTime = DateTime.fromMillisecondsSinceEpoch(timestampInt);
                }
              }

              final isSnooze = data['isSnooze'] == true || data['isSnooze'] == 'true';
              final compositeKey = _createCompositeKey(reminderId, scheduledTime, isSnooze: isSnooze);

              // Mark as shown when tapped to prevent duplicate popups
              if (_shouldShowNotification(compositeKey)) {
                _markNotificationAsShown(compositeKey);
                onNotificationTap!(data);
              } else {
                print('Skipping duplicate notification tap for $compositeKey');
              }
            }
          } catch (e) {
            print('Error handling notification tap: $e');
          }
        }
      },
    );

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'reminder_channel',
      'Reminder Notifications',
      description: 'Notifications for medication and task reminders',
      importance: Importance.high,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Clean up old notification tracking entries every minute
    _scheduleCleanup();

    // ONLY show notifications when app is in FOREGROUND
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _handleForegroundMessage(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('App opened from notification: ${message.messageId}');
      if (onNotificationTap != null && message.data.isNotEmpty) {
        try {
          final data = Map<String, dynamic>.from(message.data);
          DateTime? scheduledTime;

          if (data['timestamp'] != null) {
            // Handle both int and string timestamp
            final timestampValue = data['timestamp'];
            final timestampInt = timestampValue is int
                ? timestampValue
                : int.tryParse(timestampValue.toString());

            if (timestampInt != null) {
              // Convert UTC timestamp directly to Eastern Time
              final easternTime = tz.getLocation('America/New_York');
              final tzScheduledTime = tz.TZDateTime.fromMillisecondsSinceEpoch(easternTime, timestampInt);
              scheduledTime = tzScheduledTime;

              data['time'] = DateFormat('h:mm a').format(tzScheduledTime);
            }
          }

          final reminderId = data['reminderId'] as String?;

          if (reminderId != null) {
            final isSnooze = data['isSnooze'] == true || data['isSnooze'] == 'true';
            final compositeKey = _createCompositeKey(reminderId, scheduledTime, isSnooze: isSnooze);

            // Prevent showing duplicate dialogs when notification is tapped
            if (_shouldShowNotification(compositeKey)) {
              _markNotificationAsShown(compositeKey);
              onNotificationTap!(data);
            } else {
              print('Skipping duplicate notification from opened app for $compositeKey');
            }
          }
        } catch (e) {
          print('Error handling opened notification: $e');
        }
      }
    });

    _isInitialized = true;
    print('NotificationService initialized successfully');
  }

  // Create composite key from reminder ID and scheduled time
  static String _createCompositeKey(String reminderId, DateTime? scheduledTime, {bool isSnooze = false}) {
    if (scheduledTime != null) {
      final timeKey = scheduledTime.millisecondsSinceEpoch;
      if (isSnooze) {
        return '$reminderId:snooze:$timeKey';
      }
      return '$reminderId:$timeKey';
    }
    // Fallback to just reminder ID if no time provided
    return reminderId;
  }

  static bool _shouldShowNotification(String compositeKey) {
    if (_shownNotifications.containsKey(compositeKey)) {
      print('Skipping duplicate notification $compositeKey - already shown');
      return false;
    }
    return true;
  }

  static void _markNotificationAsShown(String compositeKey) {
    _shownNotifications[compositeKey] = DateTime.now();
    print('Marked notification $compositeKey as shown');
  }

  // Clear a specific notification from tracking (useful when marking as complete)
  static void clearNotificationTracking(String reminderId, DateTime? scheduledTime, {bool isSnooze = false}) {
    final compositeKey = _createCompositeKey(reminderId, scheduledTime, isSnooze: isSnooze);
    _shownNotifications.remove(compositeKey);
    print('Cleared tracking for $compositeKey');
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null) {
      final data = Map<String, dynamic>.from(message.data);
      final reminderId = data['reminderId'] as String? ?? notification.hashCode.toString();
      DateTime? scheduledTime;

      String formattedBody = notification.body ?? '';

      // Check if this is a snoozed notification
      final isSnooze = data['isSnooze'] == true || data['isSnooze'] == 'true';

      // Check if there's a stored body text (for snoozed reminders)
      if (isSnooze && data['originalBodyText'] != null) {
        // Use the stored body text and add (Snoozed) suffix
        formattedBody = '${data['originalBodyText']} (Snoozed)';
      } else {
        // Format the body text from timestamp (for regular reminders)
        final timestampToDisplay = isSnooze && data['originalTimestamp'] != null
            ? data['originalTimestamp']
            : data['timestamp'];

        if (timestampToDisplay != null) {
          try {
            // Handle both int and string timestamp
            final timestampValue = timestampToDisplay;
            final timestampInt = timestampValue is int
                ? timestampValue
                : int.tryParse(timestampValue.toString());

            if (timestampInt != null) {
              // Convert UTC timestamp directly to Eastern Time
              final easternTime = tz.getLocation('America/New_York');
              final tzScheduledTime = tz.TZDateTime.fromMillisecondsSinceEpoch(easternTime, timestampInt);
              scheduledTime = tzScheduledTime;

              final timeStr = DateFormat('h:mm a').format(tzScheduledTime);

              data['time'] = timeStr;
              final description = data['description'] ?? '';

              // Add (Snoozed) suffix if it's a snoozed notification
              final snoozeSuffix = isSnooze ? ' (Snoozed)' : '';
              formattedBody = 'Scheduled for $timeStr$snoozeSuffix${description.isNotEmpty ? ':\n$description' : ''}';
            }
          } catch (e) {
            print('Error formatting notification body: $e');
          }
        }
      }

      final compositeKey = _createCompositeKey(reminderId, scheduledTime, isSnooze: isSnooze);

      // Check if we should show this notification
      if (!_shouldShowNotification(compositeKey)) {
        return;
      }

      _markNotificationAsShown(compositeKey);

      final payload = json.encode(data);

      flutterLocalNotificationsPlugin.show(
        id: notification.hashCode,
        title: notification.title,
        body: formattedBody,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'reminder_channel',
            'Reminder Notifications',
            channelDescription: 'Notifications for medication and task reminders',
            importance: Importance.high,
            priority: Priority.high,
            onlyAlertOnce: true,
            playSound: true,
            enableVibration: true,
          ),
        ),
        payload: payload,
      );
    }
  }

  static void _scheduleCleanup() {
    Future.delayed(const Duration(minutes: 1), () {
      _cleanupOldNotifications();
      _scheduleCleanup(); // Schedule next cleanup
    });
  }

  static void _cleanupOldNotifications() {
    final now = DateTime.now();
    _shownNotifications.removeWhere((key, time) =>
    now.difference(time).inMinutes > 10
    );
  }

  static Future<void> saveFCMToken() async {
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && fcmToken != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'fcmToken': fcmToken});
        print('FCM token saved: $fcmToken');
      }
    } catch (e) {
      print('Error saving FCM token: $e');
    }
  }

  static Future<void> scheduleLocalNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    Map<String, dynamic>? payload,
  }) async {
    try {
      // Make sure timezone is initialized
      if (!_timezoneInitialized) {
        tz_data.initializeTimeZones();
        tz.setLocalLocation(tz.getLocation('America/New_York'));
        _timezoneInitialized = true;
      }

      final String? encodedPayload = payload != null ? json.encode(payload) : null;

      // Convert to TZDateTime
      final tz.TZDateTime scheduledDate = tz.TZDateTime.from(scheduledTime, tz.local);

      print('Scheduling local notification #$id: "$title" for $scheduledDate');
      print('Payload: $encodedPayload');

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'reminder_channel',
            'Reminder Notifications',
            channelDescription: 'Notifications for medication and task reminders',
            importance: Importance.high,
            priority: Priority.high,
            onlyAlertOnce: false, // Allow alert for scheduled notifications
            playSound: true,
            enableVibration: true,
            enableLights: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: encodedPayload,
      );

      print('Successfully scheduled local notification: $title at $scheduledTime');
    } catch (e) {
      print('Error scheduling notification: $e');
      rethrow;
    }
  }

  // Schedule a snooze notification 5 minutes from now
  static Future<void> scheduleSnoozeNotification({
    required int id,
    required String title,
    required String body,
    required String reminderId,
    required DateTime originalScheduledTime,
    Map<String, dynamic>? additionalPayload,
  }) async {
    try {
      final snoozeTime = tz.TZDateTime.now(tz.local)
          .add(const Duration(minutes: 5));

      // Create payload with BOTH times
      final payload = {
        'reminderId': reminderId,
        'timestamp': snoozeTime.millisecondsSinceEpoch,  // When to fire the notification
        'originalTimestamp': originalScheduledTime.millisecondsSinceEpoch,  // Original scheduled time to DISPLAY
        'isSnooze': true,
        ...?additionalPayload,
      };

      print('Scheduling snooze notification #$id for $snoozeTime (5 minutes from now)');
      print('Original time was: $originalScheduledTime');

      await scheduleLocalNotification(
        id: id,
        title: title,
        body: body,
        scheduledTime: snoozeTime,
        payload: payload,
      );

      print('Successfully scheduled snooze notification for $reminderId');
    } catch (e) {
      print('Error scheduling snooze notification: $e');
      rethrow;
    }
  }

  static Future<void> cancelNotification(int id) async {
    try {
      await flutterLocalNotificationsPlugin.cancel(id: id);
      print('Cancelled notification #$id');
    } catch (e) {
      print('Error cancelling notification: $e');
    }
  }

  static Future<void> cancelAllNotifications() async {
    try {
      await flutterLocalNotificationsPlugin.cancelAll();
      _shownNotifications.clear();
      print('Cancelled all notifications');
    } catch (e) {
      print('Error cancelling all notifications: $e');
    }
  }

  // Get list of pending notifications for debugging
  static Future<void> printPendingNotifications() async {
    try {
      final List<PendingNotificationRequest> pendingNotifications =
      await flutterLocalNotificationsPlugin.pendingNotificationRequests();
      print('Pending notifications: ${pendingNotifications.length}');
      for (var notification in pendingNotifications) {
        print('  - ID: ${notification.id}, Title: ${notification.title}, Body: ${notification.body}');
      }
    } catch (e) {
      print('Error getting pending notifications: $e');
    }
  }
}