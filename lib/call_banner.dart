import 'package:flutter/material.dart';

import 'app_keys.dart';
import 'call_session.dart';
import 'screens/call_screen.dart';

/// Call minimize ho to sab screens ke upar hari patti dikhati hai
/// (WhatsApp jaisi). Patti par tap se call screen wapis khulti hai.
/// MaterialApp(builder: (context, child) => CallBanner(child: child)) mein lagao.
class CallBanner extends StatelessWidget {
  final Widget? child;
  const CallBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: callSession,
      builder: (context, _) {
        final show = callSession.active && !callSession.screenVisible;
        // Structure hamesha ek jaisa rakha hai taake app ki navigation state na tute
        return Column(
          children: [
            show ? _bar(context) : const SizedBox.shrink(),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: show,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _bar(BuildContext context) {
    final s = callSession;
    return Material(
      color: const Color(0xFF2E7D32),
      child: SafeArea(
        bottom: false,
        child: InkWell(
          onTap: _openCall,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  s.video ? Icons.videocam : Icons.call,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${s.otherName}  ·  ${s.statusText}  ·  Tap to return',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => callSession.hangUp(),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.call_end,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openCall() {
    final s = callSession;
    final id = s.callId;
    if (id == null) return;
    rootNavigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          callId: id,
          otherName: s.otherName,
          otherPhoto: s.otherPhoto,
          video: s.video,
          isCaller: s.isCaller,
        ),
      ),
    );
  }
}