import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:video_player/video_player.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../services/launch_prefs.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  VideoPlayerController? _controller;
  bool _initTried = false;
  bool _initSucceeded = false;
  Timer? _skipTimer;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // If intro already seen, skip video and route immediately.
    final seen = await LaunchPrefs.hasSeenIntro;
    if (seen) {
      _routeAfterIntro();
      return;
    }
    // First launch -> play the splash video once.
    _warmUpThenInit();
  }

  // ---------------- First-launch video flow ----------------
  Future<void> _warmUpThenInit() async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initVideo();
    });

    // Hard timeout so we still route if video can’t init fast enough.
    _skipTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!_initSucceeded) _finishIntroAndRoute();
    });
  }

  Future<void> _initVideo() async {
    if (_initTried) return;
    _initTried = true;

    try {
      // Ensure asset exists
      await rootBundle.load('assets/videos/splash.mp4');

      _controller = VideoPlayerController.asset(
        'assets/videos/splash.mp4',
        videoPlayerOptions: VideoPlayerOptions(),
      );

      await _controller!.initialize();
      if (!mounted) return;

      _controller!.setLooping(false);
      await _controller!.setVolume(0.0);
      await _controller!.play();

      _controller!.addListener(_onVideoTick);

      setState(() {
        _initSucceeded = true;
      });
    } catch (e) {
      debugPrint('Splash init failed: $e');
      if (mounted) _finishIntroAndRoute();
    }
  }

  void _onVideoTick() {
    final v = _controller!.value;
    if (v.isInitialized && !v.isPlaying && v.position >= v.duration) {
      _finishIntroAndRoute();
    }
    if (v.hasError) {
      debugPrint('Video error: ${v.errorDescription}');
      _finishIntroAndRoute();
    }
  }

  Future<void> _finishIntroAndRoute() async {
    await LaunchPrefs.setHasSeenIntro(); // never show again
    if (!mounted) return;
    _routeAfterIntro();
  }

  // ---------------- Common routing after intro decision ----------------
  Future<void> _routeAfterIntro() async {
    // small delay so warm starts don’t feel like a flicker
    await Future.delayed(const Duration(milliseconds: 150));

    final isSignedIn = FirebaseAuth.instance.currentUser != null;
    if (isSignedIn) {
      final last = await LaunchPrefs.getLastRoute();
      // Avoid landing/login/splash as a restore target
      final blocked = {'/landing', '/login', '/splash'};
      final target = (last == null || blocked.contains(last)) ? '/main' : last;
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(target, (r) => false);
    } else {
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
    }
  }

  @override
  void dispose() {
    _skipTimer?.cancel();
    if (_initSucceeded && _controller != null) {
      _controller!.removeListener(_onVideoTick);
      _controller!.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // If we’re not playing video (seen intro already), show a tiny placeholder
    final playing = _initSucceeded && _controller != null && _controller!.value.isInitialized;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Center(
        child: playing
            ? SizedBox(
                width: MediaQuery.of(context).size.width * 0.7,
                child: AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: VideoPlayer(_controller!),
                ),
              )
            : const _InstantSplashPoster(),
      ),
    );
  }
}

class _InstantSplashPoster extends StatelessWidget {
  const _InstantSplashPoster();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.7,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Image.asset(
          'assets/images/splash_poster.png',
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
