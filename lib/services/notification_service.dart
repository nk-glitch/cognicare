import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:intl/intl.dart';

// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Handling background message: ${message.messageId}');
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  // Callback for notification taps
  static Function(Map<String, dynamic>)? onNotificationTap;

  static Future<void> initialize() async {
    // Request permission
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Initialize local notifications
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        // Handle notification tap
        if (details.payload != null && onNotificationTap != null) {
          final data = json.decode(details.payload!);
          onNotificationTap!(data);
        }
      },
    );

    // Create notification channel
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'reminder_channel',
      'Reminder Notifications',
      description: 'Notifications for medication and task reminders',
      importance: Importance.high,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      if (notification != null && android != null) {
        // Get reminder data from message and format time
        final data = Map<String, dynamic>.from(message.data);
        String formattedBody = notification.body ?? '';

        if (data['timestamp'] != null) {
          final timestamp = int.parse(data['timestamp']);
          final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
          final timeStr = DateFormat('h:mm a').format(dateTime);
          data['time'] = timeStr;

          // Format body with time
          final description = data['description'] ?? '';
          formattedBody = 'Scheduled for $timeStr:\n${description.isNotEmpty ? description : ''}';
        }

        final payload = json.encode(data);

        flutterLocalNotificationsPlugin.show(
          id: notification.hashCode,
          title: notification.title,
          body: formattedBody,
          payload: payload,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'reminder_channel',
              'Reminder Notifications',
              channelDescription: 'Notifications for medication and task reminders',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
        );
      }
    });

    // Handle notification tap when app is in background/terminated
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('Notification tapped: ${message.notification?.title}');
      if (onNotificationTap != null && message.data.isNotEmpty) {
        // Format time in local timezone
        final data = Map<String, dynamic>.from(message.data);
        if (data['timestamp'] != null) {
          final timestamp = int.parse(data['timestamp']);
          final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
          data['time'] = DateFormat('h:mm a').format(dateTime);
        }
        onNotificationTap!(data);
      }
    });

    // Check if app was opened from a terminated state
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null && onNotificationTap != null && initialMessage.data.isNotEmpty) {
      // Format time in local timezone
      final data = Map<String, dynamic>.from(initialMessage.data);
      if (data['timestamp'] != null) {
        final timestamp = int.parse(data['timestamp']);
        final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        data['time'] = DateFormat('h:mm a').format(dateTime);
      }
      onNotificationTap!(data);
    }
  }

  static Future<void> saveFCMToken() async {
    final fcmToken = await FirebaseMessaging.instance.getToken();
    final user = FirebaseAuth.instance.currentUser;

    if (user != null && fcmToken != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'fcmToken': fcmToken});
      print('FCM Token saved: $fcmToken');
    }
  }
}