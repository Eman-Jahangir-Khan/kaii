import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'call_push_service.dart';

// Background/terminated mein FCM khud notification dikha deta hai,
// bas ye top-level handler zaroori hai.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Call ka push aaya to poori screen wali ring dikhao
  await handleCallPush(message.data);
}

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _fcm = FirebaseMessaging.instance;
  final _local = FlutterLocalNotificationsPlugin();
  bool _inited = false;
  String? _uid;

  static const _channel = AndroidNotificationChannel(
    'high_importance_channel',
    'Messages',
    description: 'Chat, group and request notifications',
    importance: Importance.high,
  );

  /// Login ke baad call karo
  Future<void> init(String uid) async {
    _uid = uid;
    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    if (!_inited) {
      _inited = true;

      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (resp) {
          // Step 5: yahan tap par navigation hogi (resp.payload)
        },
      );

      await _local
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      await _fcm.setForegroundNotificationPresentationOptions(
        alert: true, badge: true, sound: true,
      );

      FirebaseMessaging.onMessage.listen(_onForeground);
      _fcm.onTokenRefresh.listen(_saveToken);
    }

    final token = await _fcm.getToken();
    if (token != null) await _saveToken(token);
  }

  // App khula ho (foreground) to Android khud nahi dikhata, isliye local notification
  void _onForeground(RemoteMessage m) {
    final n = m.notification;
    if (n == null) return;
    _local.show(
      id: n.hashCode,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_notification',
        ),
      ),
      payload: jsonEncode(m.data),
    );
  }

  Future<void> _saveToken(String token) async {
    if (_uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(_uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));
  }

  /// Logout se PEHLE call karo
  Future<void> removeToken() async {
    final uid = _uid;
    if (uid == null) return;
    final token = await _fcm.getToken();
    if (token != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'fcmTokens': FieldValue.arrayRemove([token]),
      }, SetOptions(merge: true));
    }
    await _fcm.deleteToken();
    _uid = null;
  }
}