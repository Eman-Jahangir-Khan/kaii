import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import 'app_keys.dart';
import 'call_repository.dart';
import 'call_session.dart';
import 'screens/call_screen.dart';

export 'app_keys.dart' show rootNavigatorKey;

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

    // 1) Pehle listener lagao, taake Accept / Decline ka event miss na ho
    _sub = FlutterCallkitIncoming.onEvent.listen((CallEvent? event) {
      if (event is CallEventActionCallAccept) {
        debugPrint('CALLKIT event: accept');
        _onAccept(event.callKitParams);
      } else if (event is CallEventActionCallDecline) {
        debugPrint('CALLKIT event: decline');
        final id = _callIdOf(event.callKitParams);
        if (id.isNotEmpty) callRepo.decline(id).catchError((_) {});
      }
    });

    // 2) App band thi aur Accept dabane se khuli: event miss ho gaya ho to yahan se pakdo
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      debugPrint('CALLKIT activeCalls: ${calls.length}');
      for (final c in calls) {
        if (c.isAccepted) _onAccept(c);
      }
    } catch (e) {
      debugPrint('CALLKIT activeCalls error: $e');
    }

    // 3) Permissions sab se baad mein, call ke raste mein na aayein
    _askPermissionsLater();
  }

  Future<void> _askPermissionsLater() async {
    await Future.delayed(const Duration(seconds: 4));
    if (callRepo.activeCallId != null || callSession.active) return;
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
  }

  /// Ye call callkit ne pehle hi sambhal li hai (ring ya Accept)?
  /// To in-app incoming screen dobara na khole.
  Future<bool> isHandledByCallkit(String id) async {
    if (_handled.contains(id)) return true;
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      return calls.any((c) => _callIdOf(c) == id);
    } catch (_) {
      return false;
    }
  }

  String _callIdOf(CallKitParams p) =>
      (p.extra?['callId'] ?? p.id).toString();

  Future<void> _onAccept(CallKitParams p) async {
    final id = _callIdOf(p);
    final extra = p.extra ?? <String, dynamic>{};
    if (id.isEmpty || _handled.contains(id)) return;
    _handled.add(id);
    debugPrint('CALLKIT accept: $id');

    // Home screen ka listener dobara incoming screen na khole
    callRepo.activeCallId = id;

    // Cold start: login (auth) restore hone ka intezar
    final user = await FirebaseAuth.instance.authStateChanges().first;
    if (user == null) {
      debugPrint('CALLKIT accept: user logged in nahi');
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

    // Navigator tayyar hone ka intezar (max 15 second)
    for (var i = 0; i < 75 && rootNavigatorKey.currentState == null; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    final nav = rootNavigatorKey.currentState;
    if (nav == null) {
      debugPrint('CALLKIT accept: navigator nahi mila');
      callRepo.activeCallId = null;
      return;
    }

    debugPrint('CALLKIT accept: call screen khol raha hu');
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