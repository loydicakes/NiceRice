import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:video_player/video_player.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:nice_rice/pages/landingpage/landing_page.dart';
import 'package:nice_rice/tab.dart'; 

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late VideoPlayerController _controller;
  bool _initTried = false;
  bool _initSucceeded = false;
  Timer? _skipTimer;

  @override
  void initState() {
    super.initState();
    _warmUpThenInit();
  }

  Future<void> _warmUpThenInit() async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initVideo();
    });

    _skipTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!_initSucceeded) _decideNextPage();
    });
  }

  Future<void> _initVideo() async {
    if (_initTried) return;
    _initTried = true;

    try {
      await rootBundle.load('assets/videos/splash.mp4');

      _controller = VideoPlayerController.asset(
        'assets/videos/splash.mp4',
        videoPlayerOptions: VideoPlayerOptions(),
      );

      await _controller.initialize();
      if (!mounted) return;

      _controller.setLooping(false);
      await _controller.setVolume(0.0);
      await _controller.play();

      _controller.addListener(_onVideoTick);

      setState(() {
        _initSucceeded = true;
      });
    } catch (e) {
      debugPrint('Splash init failed: $e');
      if (mounted) _decideNextPage();
    }
  }

  void _onVideoTick() {
    final v = _controller.value;
    if (v.isInitialized && !v.isPlaying && v.position >= v.duration) {
      _decideNextPage();
    }
    if (v.hasError) {
      debugPrint('Video error: ${v.errorDescription}');
      _decideNextPage();
    }
  }

  Future<void> _decideNextPage() async {
    if (!mounted) return;
    _skipTimer?.cancel();

    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              AppShell(initialIndex: 0),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 800),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const LandingPage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 800),
        ),
      );
    }
  }

  @override
  void dispose() {
    _skipTimer?.cancel();
    if (_initSucceeded) {
      _controller.removeListener(_onVideoTick);
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isReady = _initSucceeded && _controller.value.isInitialized;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Center(
        child: isReady
            ? SizedBox(
                width: MediaQuery.of(context).size.width * 0.7,
                child: AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                ),
              )
            : _InstantSplashPoster(onTapToSkip: _decideNextPage),
      ),
    );
  }
}

class _InstantSplashPoster extends StatelessWidget {
  final VoidCallback onTapToSkip;
  const _InstantSplashPoster({required this.onTapToSkip});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTapToSkip,
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.7,
        child: AspectRatio(aspectRatio: 16 / 9),
      ),
    );
  }
}
