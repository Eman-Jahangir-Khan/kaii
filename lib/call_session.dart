import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'agora_config.dart';
import 'app_keys.dart';
import 'call_repository.dart';

/// Poori app mein chalne wali ek hi call ka "session".
/// Call screen band / minimize ho jaye tab bhi call yahan chalti rehti hai.
final CallSession callSession = CallSession();

class CallSession extends ChangeNotifier {
  static const _terminal = ['declined', 'cancelled', 'missed', 'ended'];

  String? callId;
  String otherName = '';
  String otherPhoto = '';
  bool video = false;
  bool isCaller = false;

  RtcEngine? engine;
  int? remoteUid;
  bool muted = false;
  bool camOff = false;
  bool speaker = false;
  bool accepted = false;
  int seconds = 0;

  int _screens = 0; // abhi kitni CallScreen khuli hain
  StreamSubscription? _callSub;
  Timer? _timer;
  Timer? _ringTimeout;
  Timer? _tokenTimeout;
  String? _token;
  bool _engineReady = false;
  bool _joinStarted = false;
  bool _ending = false;
  bool _remoteTerminal = false;

  /// Call chal rahi hai (ringing / connecting / connected)
  bool get active => callId != null && !_ending;

  /// Call screen is waqt nazar aa rahi hai?
  bool get screenVisible => _screens > 0;

  String get statusText {
    if (remoteUid != null) {
      final m = (seconds ~/ 60).toString().padLeft(2, '0');
      final s = (seconds % 60).toString().padLeft(2, '0');
      return '$m:$s';
    }
    if (isCaller && !accepted) return 'Calling...';
    return 'Connecting...';
  }

  // ---- screen ki khulne / band hone ki ginti ----

  void screenOpened() {
    _screens++;
    _notifyLater();
  }

  void screenClosed() {
    if (_screens > 0) _screens--;
    _notifyLater();
  }

  // build ke dauran notify na ho, isliye frame ke baad
  void _notifyLater() {
    WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  // ---- shuru ----

  /// Naya session shuru karo. Isi call ka session pehle se chal raha ho
  /// (minimize ke baad wapas screen kholi) to wahi use hota hai.
  /// false wapis aaye to koi aur call chal rahi hai.
  bool start({
    required String id,
    required String name,
    String photo = '',
    required bool isVideo,
    required bool caller,
  }) {
    if (callId == id && !_ending) return true;
    if (active) return false;

    callId = id;
    otherName = name;
    otherPhoto = photo;
    video = isVideo;
    isCaller = caller;

    engine = null;
    remoteUid = null;
    muted = false;
    camOff = false;
    speaker = isVideo; // video call mein speaker default on
    accepted = !caller; // callee ne pehle hi utha li hai
    seconds = 0;
    _token = null;
    _engineReady = false;
    _joinStarted = false;
    _ending = false;
    _remoteTerminal = false;

    callRepo.activeCallId = id;
    _init(id);
    return true;
  }

  bool _stale(String id) => callId != id || _ending;

  Future<void> _init(String id) async {
    final perms = await [
      Permission.microphone,
      if (video) Permission.camera,
    ].request();
    if (_stale(id)) return;
    final micOk = perms[Permission.microphone]?.isGranted ?? false;
    final camOk = !video || (perms[Permission.camera]?.isGranted ?? false);
    if (!micOk || !camOk) {
      await hangUp(message: 'Microphone / camera permission is required');
      return;
    }

    // 1) Pehle engine tayyar karo (abhi join nahi)
    final e = createAgoraRtcEngine();
    engine = e;
    try {
      await e.initialize(
        const RtcEngineContext(
          appId: agoraAppId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );

      e.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection conn, int elapsed) {
            debugPrint('AGORA joined: ${conn.channelId}');
            e.setEnableSpeakerphone(speaker);
          },
          onUserJoined: (RtcConnection conn, int uid, int elapsed) {
            if (_stale(id)) return;
            remoteUid = uid;
            _startTimer();
            notifyListeners();
          },
          onUserOffline:
              (RtcConnection conn, int uid, UserOfflineReasonType reason) {
            if (_stale(id)) return;
            hangUp();
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

      await e.enableAudio();
      if (video) {
        await e.enableVideo();
        await e.startPreview();
      }
      _engineReady = true;
    } catch (err) {
      debugPrint('AGORA ERROR: $err');
      await hangUp(message: 'Could not connect the call');
      return;
    }

    if (_stale(id)) {
      // Engine banne ke dauran call khatam ho gayi
      try {
        await e.leaveChannel();
        await e.release();
      } catch (_) {}
      if (engine == e) engine = null;
      return;
    }

    // 2) Call ki halat + token sunte raho
    _callSub = callRepo.callStream(id).listen((doc) {
      final data = doc.data();
      final s = data?['status'] as String?;
      if (_stale(id) || s == null) return;

      if (s == 'accepted' && !accepted) {
        accepted = true;
        _ringTimeout?.cancel();
        notifyListeners();
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
        _maybeJoin(id);
      }
    }, onError: (err) => debugPrint('CALL stream error: $err'));

    // Token 15 second mein na aaye (server band hai) to call band
    _tokenTimeout = Timer(const Duration(seconds: 15), () {
      if (!_joinStarted && !_stale(id)) {
        hangUp(message: 'Call server is not reachable');
      }
    });

    // Caller: 40 second mein koi na uthaye to missed
    if (isCaller) {
      _ringTimeout = Timer(const Duration(seconds: 40), () {
        if (!accepted && !_stale(id)) {
          callRepo.markMissed(id).catchError((_) {});
        }
      });
    }
  }

  Future<void> _maybeJoin(String id) async {
    final e = engine;
    final token = _token;
    if (_joinStarted || !_engineReady || e == null || token == null) return;
    _joinStarted = true;
    _tokenTimeout?.cancel();
    try {
      await e.joinChannel(
        token: token,
        channelId: id,
        uid: 0,
        options: ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
          publishMicrophoneTrack: true,
          publishCameraTrack: video,
          autoSubscribeAudio: true,
          autoSubscribeVideo: video,
        ),
      );
      notifyListeners();
    } catch (err) {
      debugPrint('AGORA join error: $err');
      await hangUp(message: 'Could not connect the call');
    }
  }

  void _startTimer() {
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      seconds++;
      notifyListeners();
    });
  }

  // ---- band karna ----

  /// Mere cut karne par: Firestore mein halat likho, phir session band
  Future<void> hangUp({String? message}) async {
    final id = callId;
    if (id == null || _ending) return;
    if (!_remoteTerminal) {
      try {
        if (isCaller && !accepted) {
          await callRepo.cancel(id);
        } else {
          await callRepo.end(id);
        }
      } catch (_) {}
    }
    await _finish(message: message);
  }

  Future<void> _finish({String? message}) async {
    if (_ending || callId == null) return;
    _ending = true;
    // Caller ki taraf se chat mein call ka log likho (WhatsApp jaisa)
    final logId = callId;
    if (isCaller && logId != null) {
      callRepo.logToChat(logId, seconds: seconds).catchError((_) {});
    }
    _timer?.cancel();
    _timer = null;
    _ringTimeout?.cancel();
    _tokenTimeout?.cancel();
    _callSub?.cancel();
    callRepo.activeCallId = null;

    if (message != null) {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null) {
        ScaffoldMessenger.maybeOf(ctx)
            ?.showSnackBar(SnackBar(content: Text(message)));
      }
    }

    final e = engine;
    engine = null;
    remoteUid = null;
    callId = null; // screens / banner ko pata chal jaye ke call khatam
    notifyListeners();

    if (e != null) {
      try {
        await e.leaveChannel();
        await e.release();
      } catch (_) {}
    }
  }

  // ---- controls ----

  void toggleMute() {
    muted = !muted;
    engine?.muteLocalAudioStream(muted);
    notifyListeners();
  }

  void toggleSpeaker() {
    speaker = !speaker;
    engine?.setEnableSpeakerphone(speaker);
    notifyListeners();
  }

  void toggleCamera() {
    camOff = !camOff;
    engine?.muteLocalVideoStream(camOff);
    engine?.enableLocalVideo(!camOff);
    notifyListeners();
  }

  void switchCamera() => engine?.switchCamera();
}