// lib/pages/automation/automation.dart
import 'dart:async';
import 'dart:math';
import 'dart:math' as math show pi;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter/services.dart';

import 'package:nice_rice/header.dart';
import 'package:nice_rice/theme_controller.dart'; // ThemeScope + context.brand
import 'package:nice_rice/data/operation_history.dart';

class AutomationPage extends StatefulWidget {
  const AutomationPage({super.key});

  /// Exposed notifiers (read by HomePage to mirror Drying Chamber progress)
  static final ValueNotifier<bool> isActive = ValueNotifier<bool>(false);
  static final ValueNotifier<double> progress = ValueNotifier<double>(0.0);

  @override
  State<AutomationPage> createState() => _AutomationPageState();
}

enum InitialBracket {
  ideal, // 20-25% (ideal harvest)
  late,  // 15-19% (late harvest - too dry)
  early, // 26-30% (early harvest - too wet)
}

extension on InitialBracket {
  String get title {
    switch (this) {
      case InitialBracket.ideal:
        return "20–25%";
      case InitialBracket.late:
        return "15–19%";
      case InitialBracket.early:
        return "26–30%";
    }
  }

  String get description {
    switch (this) {
      case InitialBracket.ideal:
        return "ideal harvest";
      case InitialBracket.late:
        return "late harvest (too dry)";
      case InitialBracket.early:
        return "early harvest (too wet)";
    }
  }

  /// Midpoint used for ETA computation
  double get midpoint {
    switch (this) {
      case InitialBracket.ideal:
        return (20 + 25) / 2.0; // 22.5
      case InitialBracket.late:
        return (15 + 19) / 2.0; // 17.0
      case InitialBracket.early:
        return (26 + 30) / 2.0; // 28.0
    }
  }
}

class _AutomationPageState extends State<AutomationPage>
    with AutomaticKeepAliveClientMixin {
  static final MethodChannel _bleChannel =
      const MethodChannel('app.bluetooth/controls');

  @override
  bool get wantKeepAlive => true;

  // ---------------------- Session State (Countdown Timer) ----------------------
  Timer? _ticker; // 1s heartbeat for countdown
  Duration _sessionDuration = Duration.zero; // fixed duration computed at start
  Duration _remaining = Duration.zero;
  bool _isPaused = false;
  bool _isRunning = false;
  String? _currentOpId;

  // ---------------------- Sensors ----------------------
  Timer? _sensorTimer;
  final Random _rand = Random();
  double _humidity = 0.0;     // display label: Humidity
  double _temperature = 27.0; // °C

  // ---------------------- Target / Inputs ----------------------
  // Slider: 9% to 14% in 0.5 steps
  double _targetMc = 14.0;
  InitialBracket? _selectedBracket;

  // Calculation tuning (can be changed after testing)
  static const double _rateMcPerMin = 0.5; // % lost per minute

  // Persist the initial used for this session (midpoint of chosen bracket)
  double? _initialMcForSession;

  // Single color for progress ring / dot (requested)
  static const Color _ringSingleColor = Color.fromARGB(255, 63, 252, 88); // clean blue

  @override
  void initState() {
    super.initState();

    // Register method call handler
    _bleChannel.setMethodCallHandler(_handleBluetoothData);

    // Poll environment sensor every 3s
    _sensorTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      _sendCommand("GET_DHT");
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _sensorTimer?.cancel();

    AutomationPage.isActive.value = false;
    AutomationPage.progress.value = 0.0;

    // Best-effort finalize the operation (no await in dispose)
    if (_currentOpId != null) {
      final id = _currentOpId!;
      _currentOpId = null;
      OperationHistory.instance.logReading(id, _humidity);
      // ignore: discarded_futures
      OperationHistory.instance.endOperation(id);
      _sendAllOff();
    }

    super.dispose();
  }

  // ---------------------- Helpers ----------------------
  double _scaleForWidth(double width) => (width / 375).clamp(0.85, 1.25);

  String _fmtDuration(Duration d) {
    if (d.isNegative) return "00:00";
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    String two(int n) => n.toString().padLeft(2, "0");
    return h > 0 ? "$h:${two(m)}:${two(s)}" : "${two(m)}:${two(s)}";
  }

  // Progress for ring: 1 - (remaining / duration)
  double get _progress {
    if (_sessionDuration.inSeconds <= 0) return 0.0;
    final done =
        (_sessionDuration.inSeconds - _remaining.inSeconds).clamp(0, _sessionDuration.inSeconds);
    return (done / _sessionDuration.inSeconds).clamp(0.0, 1.0);
  }

  // --------------- BLE Parsing ---------------
  void _parseDhtResponse(String rawData) {
    final lines = rawData.split(RegExp(r'[\r\n]+'));
    for (final line in lines) {
      final data = line.trim();
      if (data.isEmpty) continue;

      if (data.startsWith("DHT:")) {
        final payload = data.replaceFirst("DHT:", "");
        final parts = payload.split(',');
        double? h, t;

        for (final part in parts) {
          final kv = part.split('=');
          if (kv.length == 2) {
            final key = kv[0].trim();
            final val = double.tryParse(kv[1].trim());
            if (key == 'H') h = val;
            if (key == 'T') t = val;
          }
        }

        if (h != null && t != null) {
          setState(() {
            _humidity = h!;
            _temperature = t!;
          });
        }
      }
    }
  }

  Future<void> _handleBluetoothData(MethodCall call) async {
    if (call.method == "onDataReceived") {
      final String data = call.arguments.toString().trim();
      _parseDhtResponse(data);
    }
  }

  Future<void> _sendCommand(String command) async {
    try {
      final response =
          await _bleChannel.invokeMethod<String>('sendData', {'data': command});
      if (response != null) {
        _parseDhtResponse(response);
      }
    } catch (e) {
      Fluttertoast.showToast(msg: "Bluetooth error: $e");
    }
  }

  void _sendAllOn() {
    _sendCommand("ON1");
    _sendCommand("ON2");
    _sendCommand("ON3");
    _sendCommand("ON4");
  }

  void _sendAllOff() {
    _sendCommand("OFF1");
    _sendCommand("OFF2");
    _sendCommand("OFF3");
    _sendCommand("OFF4");
  }

  // --------------- ETA Computation ---------------
  /// Returns ETA in minutes (double). If not computable, returns null.
  double? _computeEtaMinutes() {
    if (_selectedBracket == null) return null;
    final initialMid = _selectedBracket!.midpoint;
    final delta = (initialMid - _targetMc);
    if (delta <= 0) return 0.0;
    if (_rateMcPerMin <= 0) return null;
    return delta / _rateMcPerMin;
  }

  // --------------- Session Controls ---------------
  bool get _inputsComplete =>
      _selectedBracket != null && _targetMc >= 9.0 && _targetMc <= 14.0;

  void _commenceSession() {
      if (_isRunning) {
    Fluttertoast.showToast(msg: "A session is already running.");
    return;
    }
    if (!_inputsComplete) return;

    final etaMin = _computeEtaMinutes();
    if (etaMin == null) {
      Fluttertoast.showToast(msg: "Unable to compute estimated time.");
      return;
    }

    final totalSeconds = (etaMin * 60).ceil();
    setState(() {
      _isRunning = true;
      _isPaused = false;
      _initialMcForSession = _selectedBracket!.midpoint;
      _sessionDuration = Duration(seconds: totalSeconds);
      _remaining = _sessionDuration;
    });

    AutomationPage.isActive.value = true;
    AutomationPage.progress.value = _progress;

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_isPaused) return;

      setState(() {
        _remaining -= const Duration(seconds: 1);
        if (_remaining.isNegative) _remaining = Duration.zero;
      });

      AutomationPage.progress.value = _progress;

      if (_remaining == Duration.zero) {
        // Auto stop when done
        _finishSession(auto: true);
      }
    });

    // Start hardware
    _currentOpId = OperationHistory.instance.startOperation();
    // Log first reading (humidity)
    OperationHistory.instance.logReading(_currentOpId!, _humidity);
    _sendAllOn();

    Fluttertoast.showToast(msg: "Session commenced");
  }

  Future<void> _finishSession({bool auto = false}) async {
    _ticker?.cancel();
    setState(() {
      _isPaused = false;
      _isRunning = false;
      _sessionDuration = Duration.zero;
      _remaining = Duration.zero;
    });
    AutomationPage.isActive.value = false;
    AutomationPage.progress.value = 0.0;

    if (_currentOpId != null) {
      final id = _currentOpId!;
      _currentOpId = null;

      OperationHistory.instance.logReading(id, _humidity);
      await OperationHistory.instance.endOperation(id);
      _sendAllOff();
    }

    if (auto) {
      Fluttertoast.showToast(msg: "Target reached • Session ended");
    }
  }

  void _pause() {
    if (!_isRunning || _isPaused) return;
    setState(() {
      _isPaused = true;
    });
  }

  void _resume() {
    if (!_isRunning || !_isPaused) return;
    setState(() {
      _isPaused = false;
    });
  }

  // ---------------------- Build ----------------------
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final themeScope = ThemeScope.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: PageHeader(
        isDarkMode: themeScope.isDark,
        onThemeChanged: themeScope.setDark,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxW = constraints.maxWidth;
            final bool isTablet = maxW >= 700;
            final double scale = _scaleForWidth(maxW);

            // Content max width on wide screens
            final double contentMaxWidth = isTablet ? 860.0 : 600.0;

            // Scaled sizes
            final double cardPad   = (16 * scale).clamp(12, 22).toDouble();
            final double tileMinH  = (140 * scale).clamp(120, 180).toDouble();
            final double timerSide = (maxW * (isTablet ? 0.55 : 0.75)).clamp(240, 520).toDouble();
            final double ringTrack = (8 * scale).clamp(6, 12).toDouble();
            final double ringStroke= (12 * scale).clamp(10, 16).toDouble();
            final double dotSize   = (18 * scale).clamp(14, 24).toDouble();
            final double bigText   = (48 * scale).clamp(36, 64).toDouble();

            // Typo helper
            TextStyle t(double sz, {FontWeight? w, Color? c}) =>
                GoogleFonts.poppins(fontSize: sz, fontWeight: w, color: c ?? cs.onSurface);

            // Buttons
            final ButtonStyle commenceStyle = ElevatedButton.styleFrom(
              backgroundColor: context.brand,
              foregroundColor: cs.onPrimary,
              disabledBackgroundColor: context.brand.withOpacity(0.4),
              disabledForegroundColor: cs.onPrimary.withOpacity(0.7),
              elevation: 0,
              padding: EdgeInsets.symmetric(
                horizontal: (22 * scale).clamp(16, 28).toDouble(),
                vertical: (14 * scale).clamp(10, 18).toDouble(),
              ),
              minimumSize: Size(0, (44 * scale).clamp(40, 52).toDouble()),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
            );

            final ButtonStyle pauseStyle = ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade700, // yellow
              foregroundColor: Colors.white,
              elevation: 0,
              padding: EdgeInsets.symmetric(
                horizontal: (22 * scale).clamp(16, 28).toDouble(),
                vertical: (14 * scale).clamp(10, 18).toDouble()),
              minimumSize: Size(0, (44 * scale).clamp(40, 52).toDouble()),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
            );

            final ButtonStyle playStyle = ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32), // green
              foregroundColor: Colors.white,
              elevation: 0,
              padding: EdgeInsets.symmetric(
                horizontal: (22 * scale).clamp(16, 28).toDouble(),
                vertical: (14 * scale).clamp(10, 18).toDouble()),
              minimumSize: Size(0, (44 * scale).clamp(40, 52).toDouble()),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
            );

            final ButtonStyle stopStyle = ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC62828), // red
              foregroundColor: Colors.white,
              elevation: 0,
              padding: EdgeInsets.symmetric(
                horizontal: (22 * scale).clamp(16, 28).toDouble(),
                vertical: (14 * scale).clamp(10, 18).toDouble()),
              minimumSize: Size(0, (44 * scale).clamp(40, 52).toDouble()),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
            );

            Widget metricRow() {
              return Row(
                children: [
                  Expanded(
                    child: _metricCard(
                      minHeight: tileMinH,
                      pad: cardPad,
                      icon: Icons.water_drop_outlined,
                      label: "Humidity",
                      value: "${_humidity.toStringAsFixed(1)}%",
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _metricCard(
                      minHeight: tileMinH,
                      pad: cardPad,
                      icon: Icons.thermostat_outlined,
                      label: "Temperature",
                      value: "${_temperature.toStringAsFixed(1)}°C",
                    ),
                  ),
                ],
              );
            }

            Widget targetSlider() {
              String tip;
              if (_targetMc <= 10.0) {
                tip = "9–10% • good for long-term seed preservation";
              } else if (_targetMc >= 13.0) {
                tip = "13–14% • 2–3 months storage (recommended for milling)";
              } else if (_targetMc >= 12.0 && _targetMc <= 12.5) {
                tip = "12–12.5% • storage beyond 3 months";
              } else {
                tip = "Select a target moisture content (9–14%)";
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Target Moisture Content", style: t(16, w: FontWeight.w700, c: context.brand)),
                  SizedBox(height: (10 * scale).clamp(6, 12).toDouble()),
                  Row(
                    children: [
                      Text("9%", style: t(12, w: FontWeight.w700, c: cs.onSurface.withOpacity(0.7))),
                      Expanded(
                        child: Slider(
                          value: _targetMc,
                          min: 9.0,
                          max: 14.0,
                          divisions: 10, // 0.5% steps
                          label: "${_targetMc.toStringAsFixed(1)}%",
                          onChanged: (v) {
                            setState(() => _targetMc = double.parse(v.toStringAsFixed(1)));
                          },
                        ),
                      ),
                      Text("14%", style: t(12, w: FontWeight.w700, c: cs.onSurface.withOpacity(0.7))),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(tip, style: t(13, w: FontWeight.w600, c: cs.onSurface.withOpacity(0.85))),
                ],
              );
            }

            Widget initialSelector() {
              Widget buildBtn(InitialBracket b) {
                final sel = _selectedBracket == b;
                final bg = sel ? cs.primaryContainer : cs.surfaceVariant;
                final fg = sel ? cs.onPrimaryContainer : cs.onSurface;
                return Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _selectedBracket = b),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: EdgeInsets.all((12 * scale).clamp(10, 18).toDouble()),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cs.outline.withOpacity(sel ? 0.0 : 1.0)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            b.title,
                            textAlign: TextAlign.center,
                            style: t((18 * scale).clamp(16, 24).toDouble(),
                                w: FontWeight.w800, c: fg),
                          ),
                          SizedBox(height: 6),
                          Text(
                            b.description,
                            textAlign: TextAlign.center,
                            style: t((12 * scale).clamp(11, 15).toDouble(),
                                w: FontWeight.w600, c: fg.withOpacity(0.9)),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Initial Moisture Content", style: t(16, w: FontWeight.w700, c: context.brand)),
                  SizedBox(height: (10 * scale).clamp(6, 12).toDouble()),
                  Row(
                    children: [
                      buildBtn(InitialBracket.ideal),
                      const SizedBox(width: 10),
                      buildBtn(InitialBracket.late),
                      const SizedBox(width: 10),
                      buildBtn(InitialBracket.early),
                    ],
                  ),
                ],
              );
            }

            Widget etaBadge() {
              final eta = _computeEtaMinutes();
              String txt;
              if (!_inputsComplete) {
                txt = "Complete inputs to estimate time";
              } else if (eta == null) {
                txt = "Estimating…";
              } else if (eta <= 0) {
                txt = "At/Below target";
              } else if (eta < 60) {
                txt = "~${eta.ceil()} min";
              } else {
                final h = (eta / 60).floor();
                final m = (eta % 60).ceil();
                txt = "~${h}h ${m}m";
              }

              return Container(
                padding: EdgeInsets.symmetric(
                  horizontal: (10 * scale).clamp(8, 14).toDouble(),
                  vertical: (6 * scale).clamp(4, 10).toDouble(),
                ),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  "Estimated time: $txt",
                  style: t((12 * scale).clamp(11, 15).toDouble(),
                      w: FontWeight.w700, c: cs.onSecondaryContainer),
                ),
              );
            }

            final ringProgress = _progress;
            // Use single fixed color for ring & dot
            final dotColor = _ringSingleColor;

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentMaxWidth),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // ───────── Input Card (pre-session fields) ─────────
                      Card(
                        child: Padding(
                          padding: EdgeInsets.all(cardPad),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text("Session Plan",
                                  style: t((16 * scale).clamp(14, 20).toDouble(),
                                      w: FontWeight.w700, c: context.brand)),
                              const SizedBox(height: 10),
                              targetSlider(),
                              const SizedBox(height: 14),
                              initialSelector(),
                              const SizedBox(height: 14),
                              etaBadge(),
                              const SizedBox(height: 14),
                              ElevatedButton(
                                style: commenceStyle,
                                onPressed: (_inputsComplete && !_isRunning) ? _commenceSession : null,
                                child: Text("Commence Session",
                                    style: t(14, w: FontWeight.w700, c: cs.onPrimary)),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // ───────── Session Tracker Card (countdown + metrics below) ─────────
                      Card(
                        child: Padding(
                          padding: EdgeInsets.all(cardPad),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Session Timer",
                                    style: t((16 * scale).clamp(14, 20).toDouble(),
                                        w: FontWeight.w700, c: context.brand),
                                  ),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: (10 * scale).clamp(8, 14).toDouble(),
                                      vertical: (6 * scale).clamp(4, 10).toDouble(),
                                    ),
                                    decoration: BoxDecoration(
                                      color: _isRunning
                                          ? (_isPaused ? Colors.amber.shade100 : cs.secondaryContainer)
                                          : cs.surfaceVariant,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      _isRunning
                                          ? (_isPaused ? "Paused" : "Running")
                                          : "Idle",
                                      style: t((12 * scale).clamp(11, 15).toDouble(),
                                          w: FontWeight.w700,
                                          c: _isRunning
                                              ? (_isPaused
                                                  ? Colors.amber.shade900
                                                  : cs.onSecondaryContainer)
                                              : cs.onSurface.withOpacity(0.8)),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Circular progress based on countdown
                              LayoutBuilder(builder: (_, __) {
                                final double side = timerSide;
                                return SizedBox(
                                  width: side,
                                  height: side,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      CustomPaint(
                                        size: Size.square(side),
                                        painter: _TargetRingPainter(
                                          context: context,
                                          progress: ringProgress,
                                          track: ringTrack,
                                          stroke: ringStroke,
                                          color: _ringSingleColor, // single color ring
                                        ),
                                      ),
                                      // Moving dot at the tip of the arc
                                      Transform.rotate(
                                        angle: 2 * math.pi * ringProgress,
                                        child: Align(
                                          alignment: Alignment.topCenter,
                                          child: Container(
                                            width: dotSize,
                                            height: dotSize,
                                            decoration: BoxDecoration(
                                              color: dotColor,
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: dotColor.withOpacity(0.45),
                                                  blurRadius:
                                                      (10 * scale).clamp(6, 14).toDouble(),
                                                  spreadRadius:
                                                      (2 * scale).clamp(1, 3).toDouble(),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Center readout (remaining time + target info)
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _fmtDuration(_remaining),
                                            style: t(bigText, w: FontWeight.w800),
                                          ),
                                          SizedBox(height: (6 * scale).clamp(4, 10).toDouble()),
                                          Text(
                                            "to ${_targetMc.toStringAsFixed(1)}% MC",
                                            style: t(
                                                (14 * scale).clamp(12, 18).toDouble(),
                                                w: FontWeight.w600,
                                                c: cs.onSurface.withOpacity(0.8)),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              }),

                             

                              SizedBox(height: (16 * scale).clamp(12, 22).toDouble()),
                              // Controls: only Pause/Play and Stop while running
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      style: _isPaused ? playStyle : pauseStyle,
                                      onPressed: _isRunning
                                          ? () {
                                              if (_isPaused) {
                                                _resume();
                                              } else {
                                                _pause();
                                              }
                                            }
                                          : null,
                                      child: Text(
                                        _isPaused ? "Play" : "Pause",
                                        style: t(14, w: FontWeight.w700, c: Colors.white),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton(
                                      style: stopStyle,
                                      onPressed: _isRunning || _isPaused
                                          ? () async {
                                              final cs = Theme.of(context).colorScheme;
                                              await showDialog(
                                                context: context,
                                                builder: (ctx) => AlertDialog(
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(16),
                                                  ),
                                                  title: Text("Stop Session",
                                                      style: GoogleFonts.poppins(
                                                          fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface)),
                                                  content: Text(
                                                      "You are about to stop the current session.",
                                                      style: GoogleFonts.poppins(
                                                          fontSize: 14, color: cs.onSurface.withOpacity(0.85))),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () => Navigator.pop(ctx),
                                                      child: Text("Cancel",
                                                          style: GoogleFonts.poppins(
                                                              fontSize: 14,
                                                              fontWeight: FontWeight.w600,
                                                              color: context.brand)),
                                                    ),
                                                    ElevatedButton(
                                                      onPressed: () {
                                                        Navigator.pop(ctx);
                                                        _finishSession();
                                                      },
                                                      child: Text("Confirm",
                                                          style: GoogleFonts.poppins(
                                                              fontSize: 14,
                                                              fontWeight: FontWeight.w700,
                                                              color: cs.onPrimary)),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }
                                          : null,
                                      child: Text(
                                        "Stop",
                                        style: t(14, w: FontWeight.w700, c: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: (16 * scale).clamp(12, 22).toDouble()),
                              metricRow(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }


  // ------- Metric card wrapper -------
  Widget _metricCard({
    required double minHeight,
    required double pad,
    required IconData icon,
    required String label,
    required String value,
  }) {
    final cs = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: _MetricBox(
        label: label,
        value: value,
        bg: cs.surfaceVariant,
        border: cs.outline,
        icon: icon,
        textBuilder: ({
          double? size,
          FontWeight? weight,
          Color color = const Color(0x00000000), // sentinel; use onSurface if transparent
          double? height,
          TextDecoration? deco,
        }) {
          final effective = color == const Color(0x00000000) ? cs.onSurface : color;
          return GoogleFonts.poppins(
            fontSize: size,
            fontWeight: weight,
            color: effective,
            height: height,
            decoration: deco,
          );
        },
      ),
    );
  }
}

/// Metric tile (theme-aware)
class _MetricBox extends StatelessWidget {
  final String label;
  final String value;
  final Color bg;
  final Color border;
  final IconData icon;
  final TextStyle Function({
    double? size,
    FontWeight? weight,
    Color color,
    double? height,
    TextDecoration? deco,
  }) textBuilder;

  const _MetricBox({
    required this.label,
    required this.value,
    required this.bg,
    required this.border,
    required this.textBuilder,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final w = MediaQuery.of(context).size.width;
    final scale = (w / 375).clamp(0.85, 1.25).toDouble();

    return Container(
      padding: EdgeInsets.all((14 * scale).clamp(10, 18).toDouble()),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cs.primary, size: (18 * scale).clamp(16, 22).toDouble()),
          SizedBox(height: (6 * scale).clamp(4, 10).toDouble()),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              softWrap: false,
              style: textBuilder(
                size: (28 * scale).clamp(22, 34).toDouble(),
                weight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
          ),
          SizedBox(height: (2 * scale).clamp(2, 6).toDouble()),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textBuilder(
              size: (13 * scale).clamp(11, 16).toDouble(),
              weight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Painter (progress to target) ─────────────────────────────
class _TargetRingPainter extends CustomPainter {
  final BuildContext context;
  final double progress; // 0.0 → 1.0
  final double track;
  final double stroke;
  final Color color;

  _TargetRingPainter({
    required this.context,
    required this.progress,
    required this.color,
    this.track = 8,
    this.stroke = 12,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cs = Theme.of(context).colorScheme;
    final center = size.center(Offset.zero);
    final radius = size.width / 2;

    final base = Paint()
      ..color = cs.onSurface.withOpacity(0.18)
      ..strokeWidth = track
      ..style = PaintingStyle.stroke;

    final progressPaint = Paint()
      ..color = color // single, fixed color
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Base ring
    canvas.drawCircle(center, radius, base);

    // Progress arc
    final sweep = 2 * math.pi * progress;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final startAngle = -math.pi / 2; // start at top
    if (sweep > 0) {
      canvas.drawArc(rect, startAngle, sweep, false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TargetRingPainter old) =>
      old.progress != progress ||
      old.track != track ||
      old.stroke != stroke ||
      old.color != color;
}
