import 'dart:async';

import 'package:flutter/widgets.dart';

import 'chat_repository.dart';

/// Poori app mein yehi ek instance use hoga
final presenceService = PresenceService();

class PresenceService with WidgetsBindingObserver {
  Timer? _timer;
  bool _started = false;

  /// Login ke baad (home screen khulte hi) ek baar call karein
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _goOnline();
  }

  /// Logout se PEHLE call karein (signOut ke baad uid nahi milta)
  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    try {
      await chatRepo.setPresence(false);
    } catch (_) {}
  }

  void _beat() => chatRepo.setPresence(true).catchError((_) {});

  void _goOnline() {
    _beat();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _beat());
  }

  void _goOffline() {
    _timer?.cancel();
    chatRepo.setPresence(false).catchError((_) {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_started) return;
    if (state == AppLifecycleState.resumed) {
      _goOnline();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _goOffline();
    }
  }
}