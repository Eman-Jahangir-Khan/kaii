import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';

import '../call_repository.dart';
import '../call_session.dart';
import '../theme.dart';
import '../widgets.dart';

/// Chat ya call history se call shuru karne ke liye ye function use karo
Future<void> placeCall(
    BuildContext context, {
      required String otherUid,
      required String otherName,
      String otherPhoto = '',
      required bool video,
    }) async {
  if (callRepo.activeCallId != null || callSession.active) return; // call chal rahi hai
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final id = await callRepo.startCall(
      otherUid: otherUid,
      otherName: otherName,
      otherPhoto: otherPhoto,
      video: video,
    );
    callRepo.activeCallId = id;
    await nav.push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          callId: id,
          otherName: otherName,
          otherPhoto: otherPhoto,
          video: video,
          isCaller: true,
        ),
      ),
    );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not start the call. Try again.')),
    );
  }
}

/// Call ki screen. Sirf dikhati hai, asli call CallSession mein chalti hai.
/// Back dabane ya neeche wale teer se screen minimize hoti hai, call chalti rehti hai.
class CallScreen extends StatefulWidget {
  final String callId;
  final String otherName;
  final String otherPhoto;
  final bool video;
  final bool isCaller;

  const CallScreen({
    super.key,
    required this.callId,
    required this.otherName,
    this.otherPhoto = '',
    required this.video,
    required this.isCaller,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    final ok = callSession.start(
      id: widget.callId,
      name: widget.otherName,
      photo: widget.otherPhoto,
      isVideo: widget.video,
      caller: widget.isCaller,
    );
    callSession.screenOpened();
    callSession.addListener(_onSession);
    if (!ok) {
      // Koi aur call chal rahi hai
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
    }
  }

  @override
  void dispose() {
    callSession.removeListener(_onSession);
    callSession.screenClosed();
    super.dispose();
  }

  // Call khatam ho gayi to screen khud band
  void _onSession() {
    if (!mounted) return;
    if (callSession.callId != widget.callId) _close();
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: callSession,
      builder: (context, _) {
        final s = callSession;
        final engine = s.engine;
        final video = widget.video;
        final remoteVideo = video && engine != null && s.remoteUid != null;

        return Scaffold(
          backgroundColor: AppColors.brown900,
          body: Stack(
            children: [
              // Peeche: samne wale ki video, warna naam + photo
              Positioned.fill(
                child: remoteVideo
                    ? AgoraVideoView(
                  controller: VideoViewController.remote(
                    rtcEngine: engine,
                    canvas: VideoCanvas(uid: s.remoteUid),
                    connection: RtcConnection(channelId: widget.callId),
                  ),
                )
                    : _infoView(s),
              ),

              // Upar: naam + timer (video chal rahi ho tab)
              if (remoteVideo)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(
                            widget.otherName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            s.statusText,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Upar bayen: minimize (call chalti rehti hai)
              Positioned(
                top: 0,
                left: 4,
                child: SafeArea(
                  child: IconButton(
                    tooltip: 'Minimize',
                    icon: const Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.white,
                      size: 32,
                    ),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),

              // Apni chhoti video
              if (video && engine != null && !s.camOff)
                Positioned(
                  top: 0,
                  right: 12,
                  child: SafeArea(
                    child: Padding(
                      padding: EdgeInsets.only(top: remoteVideo ? 70 : 12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox(
                          width: 100,
                          height: 140,
                          child: AgoraVideoView(
                            controller: VideoViewController(
                              rtcEngine: engine,
                              canvas: const VideoCanvas(uid: 0),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // Neeche: buttons
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _CallButton(
                          icon: s.muted ? Icons.mic_off : Icons.mic,
                          active: s.muted,
                          onTap: s.toggleMute,
                        ),
                        _CallButton(
                          icon: s.speaker ? Icons.volume_up : Icons.volume_down,
                          active: s.speaker,
                          onTap: s.toggleSpeaker,
                        ),
                        if (video) ...[
                          _CallButton(
                            icon: s.camOff ? Icons.videocam_off : Icons.videocam,
                            active: s.camOff,
                            onTap: s.toggleCamera,
                          ),
                          _CallButton(
                            icon: Icons.cameraswitch,
                            onTap: s.switchCamera,
                          ),
                        ],
                        _CallButton(
                          icon: Icons.call_end,
                          color: Colors.red,
                          onTap: () => s.hangUp(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _infoView(CallSession s) {
    return Container(
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            UserAvatar(
              username: widget.otherName,
              photoUrl: widget.otherPhoto,
              size: 120,
            ),
            const SizedBox(height: 20),
            Text(
              widget.otherName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.statusText,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final Color? color;

  const _CallButton({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ??
          (active ? Colors.white : Colors.white.withValues(alpha: 0.22)),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Icon(
            icon,
            size: 26,
            color: (active && color == null) ? AppColors.brown900 : Colors.white,
          ),
        ),
      ),
    );
  }
}