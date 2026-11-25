import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../call_repository.dart';
import '../../chat_repository.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'call_screen.dart';

/// Samne wale ki call aane par ye screen khulti hai
class IncomingCallScreen extends StatefulWidget {
  final String callId;
  final Map<String, dynamic> data;

  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.data,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  bool _accepted = false;
  bool _closing = false;

  Map<String, dynamic>? _user; // caller ka profile (nickname / photo ke liye)

  String get _callerId => (widget.data['callerId'] as String?) ?? '';

  /// Naam ki tarteeb: mera save kiya naam > caller ka apna naam > username
  String get _name => chatRepo.displayName(
    _callerId,
    _user ?? chatRepo.cachedUser(_callerId),
    fallback: (widget.data['callerName'] as String?) ?? '',
  );

  String get _photo {
    final live =
        ((_user ?? chatRepo.cachedUser(_callerId))?['photoUrl'] as String?) ??
            '';
    return live.isNotEmpty
        ? live
        : (widget.data['callerPhoto'] as String?) ?? '';
  }

  bool get _video => widget.data['type'] == 'video';

  void _onNames() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    callRepo.activeCallId = widget.callId;
    chatRepo.contactNames.addListener(_onNames);
    if (_callerId.isNotEmpty) {
      chatRepo.getUser(_callerId).then((u) {
        if (mounted) setState(() => _user = u);
      }).catchError((_) {});
    }
    // Caller ne cut kar di ya time out ho gaya to screen band
    _sub = callRepo.callStream(widget.callId).listen((doc) {
      final s = doc.data()?['status'];
      if (s != 'ringing' && !_accepted) _close();
    });
  }

  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    final route = ModalRoute.of(context);
    if (route == null) return;
    if (route.isCurrent) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).removeRoute(route);
    }
  }

  Future<void> _accept() async {
    if (_accepted) return;
    _accepted = true;
    final nav = Navigator.of(context);
    try {
      await callRepo.accept(widget.callId);
    } catch (_) {
      _accepted = false;
      return;
    }
    nav.pushReplacement(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          callId: widget.callId,
          otherName: _name,
          otherPhoto: _photo,
          video: _video,
          isCaller: false,
        ),
      ),
    );
  }

  Future<void> _decline() async {
    if (_accepted) return;
    _closing = true;
    try {
      await callRepo.decline(widget.callId);
    } catch (_) {}
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    chatRepo.contactNames.removeListener(_onNames);
    _sub?.cancel();
    if (!_accepted) callRepo.activeCallId = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _closing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _decline();
      },
      child: Scaffold(
        backgroundColor: AppColors.brown900,
        body: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.brown900, AppColors.brown700, AppColors.gold700],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),
                UserAvatar(username: _name, photoUrl: _photo, size: 120),
                const SizedBox(height: 20),
                Text(
                  _name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _video ? 'Incoming video call...' : 'Incoming voice call...',
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const Spacer(flex: 3),
                Padding(
                  padding: const EdgeInsets.fromLTRB(40, 0, 40, 48),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _roundButton(Icons.call_end, Colors.red, _decline),
                      _roundButton(
                        _video ? Icons.videocam : Icons.call,
                        Colors.green,
                        _accept,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _roundButton(IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Icon(icon, color: Colors.white, size: 32),
        ),
      ),
    );
  }
}