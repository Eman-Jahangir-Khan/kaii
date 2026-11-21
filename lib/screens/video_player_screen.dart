import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../theme.dart';

/// Full screen video player (chat aur group chat dono yehi use karte hain).
class VideoPlayerScreen extends StatefulWidget {
  final String url;
  const VideoPlayerScreen({super.key, required this.url});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final VideoPlayerController _c;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _c.addListener(() {
      if (mounted) setState(() {}); // progress bar / play icon refresh
    });
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _c.play();
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _toggle() {
    _c.value.isPlaying ? _c.pause() : _c.play();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _c.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: _failed
            ? const Text(
          'Video could not be played',
          style: TextStyle(color: Colors.white),
        )
            : !ready
            ? const CircularProgressIndicator(color: AppColors.gold400)
            : GestureDetector(
          onTap: _toggle,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AspectRatio(
                aspectRatio: _c.value.aspectRatio,
                child: VideoPlayer(_c),
              ),
              if (!_c.value.isPlaying)
                const CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.black54,
                  child: Icon(Icons.play_arrow,
                      color: Colors.white, size: 40),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: ready
          ? SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: VideoProgressIndicator(
            _c,
            allowScrubbing: true,
            colors: const VideoProgressColors(
              playedColor: AppColors.gold400,
              bufferedColor: Colors.white24,
              backgroundColor: Colors.white10,
            ),
          ),
        ),
      )
          : null,
    );
  }
}