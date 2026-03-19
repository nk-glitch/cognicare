import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'dart:ui' show Color;
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

  static final Map<String, DateTime> _shownNotifications = {};
  static bool _isInitialized = false;
  static bool _timezoneInitialized = false;

  static Future<void> initialize() async {
    if (_isInitialized) {
      print('NotificationService already initialized');
      return;
    }

    if (!_timezoneInitialized) {
      try {
        tz_data.initializeTimeZones();
        tz.setLocalLocation(tz.getLocation('America/New_York'));
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

    const InitializationSettings initializationSettings =
    InitializationSettings(android: initializationSettingsAndroid);

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
                final timestampInt = timestampValue is int
                    ? timestampValue
                    : int.tryParse(timestampValue.toString());
                if (timestampInt != null) {
                  scheduledTime =
                      DateTime.fromMillisecondsSinceEpoch(timestampInt);
                }
              }
              final isSnooze =
                  data['isSnooze'] == true || data['isSnooze'] == 'true';
              final compositeKey = _createCompositeKey(reminderId, scheduledTime,
                  isSnooze: isSnooze);
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

    // ── Channels ──────────────────────────────────────────────────────────
    const AndroidNotificationChannel reminderChannel =
    AndroidNotificationChannel(
      'reminder_channel',
      'Reminder Notifications',
      description: 'Notifications for medication and task reminders',
      importance: Importance.high,
    );

    const AndroidNotificationChannel geofenceChannel =
    AndroidNotificationChannel(
      'geofence_channel',
      'Safe Zone Alerts',
      description: 'Alerts when a patient leaves their designated safe zone',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    );

    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(reminderChannel);
    await androidPlugin?.createNotificationChannel(geofenceChannel);

    _scheduleCleanup();

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
            final timestampValue = data['timestamp'];
            final timestampInt = timestampValue is int
                ? timestampValue
                : int.tryParse(timestampValue.toString());
            if (timestampInt != null) {
              final easternTime = tz.getLocation('America/New_York');
              final tzScheduledTime =
              tz.TZDateTime.fromMillisecondsSinceEpoch(easternTime, timestampInt);
              scheduledTime = tzScheduledTime;
              data['time'] = DateFormat('h:mm a').format(tzScheduledTime);
            }
          }

          final reminderId = data['reminderId'] as String?;
          if (reminderId != null) {
            final isSnooze =
                data['isSnooze'] == true || data['isSnooze'] == 'true';
            final compositeKey = _createCompositeKey(reminderId, scheduledTime,
                isSnooze: isSnooze);
            if (_shouldShowNotification(compositeKey)) {
              _markNotificationAsShown(compositeKey);
              onNotificationTap!(data);
            } else {
              print(
                  'Skipping duplicate notification from opened app for $compositeKey');
            }
          }
        } catch (e) {
          print('Error handling opened notification: $e');
        }
      }
    });

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({'fcmToken': newToken});
          print('FCM token refreshed and saved');
        }
      } catch (e) {
        print('Error saving refreshed FCM token: $e');
      }
    });

    _isInitialized = true;
    print('NotificationService initialized successfully');
  }

  static String _createCompositeKey(String reminderId, DateTime? scheduledTime,
      {bool isSnooze = false}) {
    if (scheduledTime != null) {
      final timeKey = scheduledTime.millisecondsSinceEpoch;
      if (isSnooze) return '$reminderId:snooze:$timeKey';
      return '$reminderId:$timeKey';
    }
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

  static void clearNotificationTracking(String reminderId,
      DateTime? scheduledTime,
      {bool isSnooze = false}) {
    final compositeKey =
    _createCompositeKey(reminderId, scheduledTime, isSnooze: isSnooze);
    _shownNotifications.remove(compositeKey);
    print('Cleared tracking for $compositeKey');
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    RemoteNotification? notification = message.notification;
    final data = Map<String, dynamic>.from(message.data);

    // ── Geofence breach alert ──────────────────────────────────────────────
    if (data['type'] == 'geofence_alert') {
      final patientId =
          data['patientId'] as String? ?? message.messageId ?? 'geo';
      final compositeKey =
          'geofence_alert:$patientId:${DateTime.now().millisecondsSinceEpoch ~/ 60000}';

      if (!_shouldShowNotification(compositeKey)) return;
      _markNotificationAsShown(compositeKey);

      final title = notification?.title ?? '⚠️ Safe zone alert';
      final body = notification?.body ??
          '${data['patientName'] ?? 'Patient'} has left the safe zone';

      flutterLocalNotificationsPlugin.show(
        id: patientId.hashCode ^ 0x1F2A3B,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'geofence_channel',
            'Safe Zone Alerts',
            channelDescription:
            'Alerts when a patient leaves their designated safe zone',
            importance: Importance.max,
            priority: Priority.max,
            onlyAlertOnce: false,
            playSound: true,
            enableVibration: true,
            enableLights: true,
            color: Color(0xFFF57C00),
          ),
        ),
        payload: json.encode(data),
      );
      return;
    }

    // ── Caretaker missed-reminder alert ────────────────────────────────────
    if (data['type'] == 'caretaker_alert') {
      final reminderId =
          data['reminderId'] as String? ?? message.messageId ?? 'alert';
      final compositeKey = 'caretaker_alert:$reminderId';

      if (!_shouldShowNotification(compositeKey)) return;
      _markNotificationAsShown(compositeKey);

      flutterLocalNotificationsPlugin.show(
        id: reminderId.hashCode,
        title: notification?.title ?? 'Missed Reminder Alert',
        body: notification?.body ?? data['alertMessage'] as String? ?? 'A patient missed a reminder',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'reminder_channel',
            'Reminder Notifications',
            channelDescription:
            'Notifications for medication and task reminders',
            importance: Importance.high,
            priority: Priority.high,
            onlyAlertOnce: true,
            playSound: true,
            enableVibration: true,
          ),
        ),
        payload: json.encode(data),
      );
      return;
    }

    // ── Standard reminder notification ─────────────────────────────────────
    if (notification == null) return;

    final reminderId =
        data['reminderId'] as String? ?? message.messageId ?? 'unknown';
    final isSnooze = data['isSnooze'] == true || data['isSnooze'] == 'true';

    DateTime? scheduledTime;
    String? formattedBody;

    if (isSnooze && data['originalBodyText'] != null) {
      formattedBody = '${data['originalBodyText']} (Snoozed)';
    } else {
      final timestampToDisplay = isSnooze && data['originalTimestamp'] != null
          ? data['originalTimestamp']
          : data['timestamp'];

      if (timestampToDisplay != null) {
        try {
          final timestampValue = timestampToDisplay;
          final timestampInt = timestampValue is int
              ? timestampValue
              : int.tryParse(timestampValue.toString());

          if (timestampInt != null) {
            final easternTime = tz.getLocation('America/New_York');
            final tzScheduledTime =
            tz.TZDateTime.fromMillisecondsSinceEpoch(easternTime, timestampInt);
            scheduledTime = tzScheduledTime;
            final timeStr = DateFormat('h:mm a').format(tzScheduledTime);
            data['time'] = timeStr;
            final description = data['description'] ?? '';
            final snoozeSuffix = isSnooze ? ' (Snoozed)' : '';
            formattedBody =
            'Scheduled for $timeStr$snoozeSuffix${description.isNotEmpty ? ':\n$description' : ''}';
          }
        } catch (e) {
          print('Error formatting notification body: $e');
        }
      }
    }

    final compositeKey =
    _createCompositeKey(reminderId, scheduledTime, isSnooze: isSnooze);
    if (!_shouldShowNotification(compositeKey)) return;
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

  static void _scheduleCleanup() {
    Future.delayed(const Duration(minutes: 1), () {
      _cleanupOldNotifications();
      _scheduleCleanup();
    });
  }

  static void _cleanupOldNotifications() {
    final now = DateTime.now();
    _shownNotifications
        .removeWhere((key, time) => now.difference(time).inMinutes > 10);
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
      if (!_timezoneInitialized) {
        tz_data.initializeTimeZones();
        tz.setLocalLocation(tz.getLocation('America/New_York'));
        _timezoneInitialized = true;
      }

      final String? encodedPayload =
      payload != null ? json.encode(payload) : null;
      final tz.TZDateTime scheduledDate =
      tz.TZDateTime.from(scheduledTime, tz.local);

      print('Scheduling local notification #$id: "$title" for $scheduledDate');

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
            onlyAlertOnce: false,
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

  static Future<void> scheduleSnoozeNotification({
    required int id,
    required String title,
    required String body,
    required String reminderId,
    required DateTime originalScheduledTime,
    Map<String, dynamic>? additionalPayload,
  }) async {
    try {
      final snoozeTime =
      tz.TZDateTime.now(tz.local).add(const Duration(minutes: 5));
      final payload = {
        'reminderId': reminderId,
        'timestamp': snoozeTime.millisecondsSinceEpoch,
        'originalTimestamp': originalScheduledTime.millisecondsSinceEpoch,
        'isSnooze': true,
        ...?additionalPayload,
      };

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

  static Future<void> printPendingNotifications() async {
    try {
      final List<PendingNotificationRequest> pendingNotifications =
      await flutterLocalNotificationsPlugin.pendingNotificationRequests();
      print('Pending notifications: ${pendingNotifications.length}');
      for (var notification in pendingNotifications) {
        print(
            '  - ID: ${notification.id}, Title: ${notification.title}, Body: ${notification.body}');
      }
    } catch (e) {
      print('Error getting pending notifications: $e');
    }
  }
}