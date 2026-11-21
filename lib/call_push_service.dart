import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import 'call_repository.dart';
import 'screens/call_screen.dart';

/// MaterialApp mein navigatorKey: rootNavigatorKey lagana zaroori hai
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Server se aane wale call push ko handle karo.
/// Ye background isolate se bhi chalta hai (app band ho tab bhi).
Future<void> handleCallPush(Map<String, dynamic> data) async {
  final type = data['type'];
  if (type == 'call') {
    await _showIncoming(data);
  } else if (type == 'call_cancel') {
    final id = (data['callId'] ?? '').toString();
    if (id.isNotEmpty) await FlutterCallkitIncoming.endCall(id);
  }
}

Future<void> _showIncoming(Map<String, dynamic> d) async {
  final callId = (d['callId'] ?? '').toString();
  if (callId.isEmpty) return;
  final video = d['callType'] == 'video';
  final photo = (d['callerPhoto'] ?? '').toString();

  final params = CallKitParams(
    id: callId,
    nameCaller: (d['callerName'] ?? 'Kaii').toString(),
    appName: 'Kaii',
    avatar: photo.isEmpty ? null : photo,
    handle: video ? 'Video call' : 'Voice call',
    type: video ? 1 : 0,
    duration: 40000,
    extra: <String, dynamic>{
      'callId': callId,
      'callerName': (d['callerName'] ?? '').toString(),
      'callerPhoto': photo,
      'callType': video ? 'video' : 'voice',
    },
    android: const AndroidParams(
      isCustomNotification: true,
      isShowLogo: false,
      ringtonePath: 'system_ringtone_default',
      backgroundColor: '#3E2A1F',
      actionColor: '#4CAF50',
      textColor: '#ffffff',
      incomingCallNotificationChannelName: 'Incoming call',
      missedCallNotificationChannelName: 'Missed call',
    ),
  );
  await FlutterCallkitIncoming.showCallkitIncoming(params);
}

/// Foreground mein: callkit ke Accept / Decline dabane par kya karna hai
class CallPushService {
  CallPushService._();
  static final instance = CallPushService._();

  bool _started = false;
  final Set<String> _handled = {};
  StreamSubscription? _sub;

  Future<void> init() async {
    if (_started) return;
    _started = true;

    try {
      await FlutterCallkitIncoming.requestNotificationPermission({
        'title': 'Notification permission',
        'rationaleMessagePermission':
        'Notification permission is required to show incoming calls.',
        'postNotificationMessageRequired':
        'Please allow notifications from Settings to receive calls.',
      });
      await FlutterCallkitIncoming.requestFullIntentPermission();
    } catch (e) {
      debugPrint('CALLKIT permission error: $e');
    }

    _sub = FlutterCallkitIncoming.onEvent.listen((CallEvent? event) {
      if (event is CallEventActionCallAccept) {
        _onAccept(event.callKitParams);
      } else if (event is CallEventActionCallDecline) {
        final id = _callIdOf(event.callKitParams);
        if (id.isNotEmpty) callRepo.decline(id).catchError((_) {});
      }
    });

    // App band thi aur Accept dabane se khuli: event miss ho gaya ho to yahan se pakdo
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      for (final c in calls) {
        if (c.isAccepted) _onAccept(c);
      }
    } catch (e) {
      debugPrint('CALLKIT activeCalls error: $e');
    }
  }

  String _callIdOf(CallKitParams p) =>
      (p.extra?['callId'] ?? p.id).toString();

  Future<void> _onAccept(CallKitParams p) async {
    final id = _callIdOf(p);
    final extra = p.extra ?? <String, dynamic>{};
    if (id.isEmpty || _handled.contains(id)) return;
    _handled.add(id);

    // Home screen ka listener dobara incoming screen na khole
    callRepo.activeCallId = id;

    // Cold start: login (auth) restore hone ka intezar
    final user = await FirebaseAuth.instance.authStateChanges().first;
    if (user == null) {
      callRepo.activeCallId = null;
      return;
    }

    try {
      await callRepo.accept(id);
    } catch (e) {
      debugPrint('CALLKIT accept error: $e');
      callRepo.activeCallId = null;
      return;
    }

    // Navigator tayyar hone ka intezar (max 5 second)
    for (var i = 0; i < 25 && rootNavigatorKey.currentState == null; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    final nav = rootNavigatorKey.currentState;
    if (nav == null) {
      callRepo.activeCallId = null;
      return;
    }

    nav.push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          callId: id,
          otherName: (extra['callerName'] ?? '').toString(),
          otherPhoto: (extra['callerPhoto'] ?? '').toString(),
          video: extra['callType'] == 'video',
          isCaller: false,
        ),
      ),
    );

    // Plugin ka apna ring UI saaf karo
    FlutterCallkitIncoming.endCall(id);
  }

  void dispose() {
    _sub?.cancel();
    _started = false;
  }
}