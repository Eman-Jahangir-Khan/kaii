import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../agora_config.dart';
import '../call_repository.dart';
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
  if (callRepo.activeCallId != null) return; // pehle se call chal rahi hai
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
  static const _terminal = ['declined', 'cancelled', 'missed', 'ended'];

  RtcEngine? _engine;
  StreamSubscription? _callSub;
  Timer? _timer;
  Timer? _ringTimeout;

  int? _remoteUid;
  bool _muted = false;
  bool _camOff = false;
  late bool _speaker = widget.video; // video call mein speaker default on
  late bool _accepted = !widget.isCaller; // callee ne pehle hi utha li hai
  bool _ending = false;
  bool _remoteTerminal = false;
  int _seconds = 0;

  // Token server ne jo token Firestore mein likha wo yahan aata hai
  String? _token;
  bool _engineReady = false;
  bool _joinStarted = false;
  Timer? _tokenTimeout;

  @override
  void initState() {
    super.initState();
    callRepo.activeCallId = widget.callId;
    _init();
  }

  Future<void> _init() async {
    final perms = await [
      Permission.microphone,
      if (widget.video) Permission.camera,
    ].request();
    final micOk = perms[Permission.microphone]?.isGranted ?? false;
    final camOk = !widget.video || (perms[Permission.camera]?.isGranted ?? false);
    if (!micOk || !camOk) {
      await _hangUp(message: 'Microphone / camera permission is required');
      return;
    }

    // 1) Pehle engine tayyar karo (abhi join nahi)
    try {
      final engine = createAgoraRtcEngine();
      _engine = engine;
      await engine.initialize(
        const RtcEngineContext(
          appId: agoraAppId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );

      engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection conn, int elapsed) {
            debugPrint('AGORA joined: ${conn.channelId}');
            engine.setEnableSpeakerphone(_speaker);
          },
          onUserJoined: (RtcConnection conn, int uid, int elapsed) {
            if (!mounted) return;
            setState(() => _remoteUid = uid);
            _startTimer();
          },
          onUserOffline: (RtcConnection conn, int uid,
              UserOfflineReasonType reason) {
            if (!mounted) return;
            _hangUp();
          },
          onError: (ErrorCodeType err, String msg) {
            debugPrint('AGORA ERROR: $err $msg');
          },
          onConnectionStateChanged: (RtcConnection conn,
              ConnectionStateType state, ConnectionChangedReasonType reason) {
            debugPrint('AGORA conn: $state $reason');
          },
        ),
      );

      await engine.enableAudio();
      if (widget.video) {
        await engine.enableVideo();
        await engine.startPreview();
      }
      _engineReady = true;
    } catch (e) {
      debugPrint('AGORA ERROR: $e');
      await _hangUp(message: 'Could not connect the call');
      return;
    }

    // 2) Call ki halat + token sunte raho
    _callSub = callRepo.callStream(widget.callId).listen((doc) {
      final data = doc.data();
      final s = data?['status'] as String?;
      if (!mounted || s == null) return;

      if (s == 'accepted' && !_accepted) {
        setState(() => _accepted = true);
        _ringTimeout?.cancel();
      }
      if (_terminal.contains(s)) {
        _remoteTerminal = true;
        _finish(
          message: s == 'declined'
              ? 'Call declined'
              : s == 'missed'
              ? 'No answer'
              : null,
        );
        return;
      }

      // Server ne token likh diya to channel join karo
      final tk = data?['token'];
      if (tk is String && tk.isNotEmpty) {
        _token = tk;
        _maybeJoin();
      }
    });

    // Token 15 second mein na aaye (server band hai) to call band
    _tokenTimeout = Timer(const Duration(seconds: 15), () {
      if (!_joinStarted && !_ending) {
        _hangUp(message: 'Call server is not reachable');
      }
    });

    // Caller: 40 second mein koi na uthaye to missed
    if (widget.isCaller) {
      _ringTimeout = Timer(const Duration(seconds: 40), () {
        if (!_accepted && !_ending) {
          callRepo.markMissed(widget.callId).catchError((_) {});
        }
      });
    }
  }

  Future<void> _maybeJoin() async {
    final engine = _engine;
    final token = _token;
    if (_joinStarted || !_engineReady || engine == null || token == null) {
      return;
    }
    _joinStarted = true;
    _tokenTimeout?.cancel();
    try {
      await engine.joinChannel(
        token: token,
        channelId: widget.callId,
        uid: 0,
        options: ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
          publishMicrophoneTrack: true,
          publishCameraTrack: widget.video,
          autoSubscribeAudio: true,
          autoSubscribeVideo: widget.video,
        ),
      );
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('AGORA join error: $e');
      await _hangUp(message: 'Could not connect the call');
    }
  }

  void _startTimer() {
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  /// Mere cut karne par: Firestore mein halat likho, phir screen band
  Future<void> _hangUp({String? message}) async {
    if (_ending) return;
    if (!_remoteTerminal) {
      try {
        if (widget.isCaller && !_accepted) {
          await callRepo.cancel(widget.callId);
        } else {
          await callRepo.end(widget.callId);
        }
      } catch (_) {}
    }
    await _finish(message: message);
  }

  Future<void> _finish({String? message}) async {
    if (_ending) return;
    _ending = true;
    _timer?.cancel();
    _ringTimeout?.cancel();
    _tokenTimeout?.cancel();
    _callSub?.cancel();
    callRepo.activeCallId = null;

    final messenger = mounted ? ScaffoldMessenger.maybeOf(context) : null;
    final nav = mounted ? Navigator.of(context) : null;

    final e = _engine;
    _engine = null;
    if (e != null) {
      try {
        await e.leaveChannel();
        await e.release();
      } catch (_) {}
    }

    if (message != null) {
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
    if (mounted && nav != null && nav.canPop()) nav.pop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ringTimeout?.cancel();
    _tokenTimeout?.cancel();
    _callSub?.cancel();
    if (!_ending) {
      // Kisi aur tareeqe se screen band hui to bhi engine saaf karo
      callRepo.activeCallId = null;
      final e = _engine;
      _engine = null;
      e?.leaveChannel().then((_) => e.release()).catchError((_) {});
    }
    super.dispose();
  }

  // ---- controls ----

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _engine?.muteLocalAudioStream(_muted);
  }

  void _toggleSpeaker() {
    setState(() => _speaker = !_speaker);
    _engine?.setEnableSpeakerphone(_speaker);
  }

  void _toggleCamera() {
    setState(() => _camOff = !_camOff);
    _engine?.muteLocalVideoStream(_camOff);
    _engine?.enableLocalVideo(!_camOff);
  }

  void _switchCamera() => _engine?.switchCamera();

  // ---- UI ----

  String get _statusText {
    if (_remoteUid != null) {
      final m = (_seconds ~/ 60).toString().padLeft(2, '0');
      final s = (_seconds % 60).toString().padLeft(2, '0');
      return '$m:$s';
    }
    if (widget.isCaller && !_accepted) return 'Calling...';
    return 'Connecting...';
  }

  @override
  Widget build(BuildContext context) {
    final engine = _engine;
    final remoteVideo =
        widget.video && engine != null && _remoteUid != null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _hangUp();
      },
      child: Scaffold(
        backgroundColor: AppColors.brown900,
        body: Stack(
          children: [
            // Peeche: samne wale ki video, warna naam + photo
            Positioned.fill(
              child: remoteVideo
                  ? AgoraVideoView(
                controller: VideoViewController.remote(
                  rtcEngine: engine,
                  canvas: VideoCanvas(uid: _remoteUid),
                  connection: RtcConnection(channelId: widget.callId),
                ),
              )
                  : _infoView(),
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
                          _statusText,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Apni chhoti video
            if (widget.video && engine != null && !_camOff)
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
                        icon: _muted ? Icons.mic_off : Icons.mic,
                        active: _muted,
                        onTap: _toggleMute,
                      ),
                      _CallButton(
                        icon: _speaker ? Icons.volume_up : Icons.volume_down,
                        active: _speaker,
                        onTap: _toggleSpeaker,
                      ),
                      if (widget.video) ...[
                        _CallButton(
                          icon: _camOff ? Icons.videocam_off : Icons.videocam,
                          active: _camOff,
                          onTap: _toggleCamera,
                        ),
                        _CallButton(
                          icon: Icons.cameraswitch,
                          onTap: _switchCamera,
                        ),
                      ],
                      _CallButton(
                        icon: Icons.call_end,
                        color: Colors.red,
                        onTap: _hangUp,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoView() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.brown900, AppColors.brown700],
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
              _statusText,
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