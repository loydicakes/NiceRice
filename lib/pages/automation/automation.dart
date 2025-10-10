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

class _AutomationPageState extends State<AutomationPage>
    with AutomaticKeepAliveClientMixin {
    static final MethodChannel _bleChannel = MethodChannel('app.bluetooth/controls');

  @override
  bool get wantKeepAlive => true;
  // ---------------------- Stopwatch / State ----------------------
  Timer? _ticker;                    // 1s heartbeat
  Duration _elapsed = Duration.zero; // UI stopwatch
  bool _isPaused = false;
  bool _isRunning = false;
  String? _currentOpId;

  // ---------------------- Sensors (simulated) ----------------------
  Timer? _sensorTimer;
  final Random _rand = Random();
  double _moisture = 0.0;
  double _temperature = 27.0;

  // ---------------------- Drying target / estimator ----------------------
  static const double _targetMc = 14.0;      // target MC(% wet basis)
  double? _initialMc;                        // captured at session start
  final List<_McSample> _mcHistory = [];     // rolling window for slope/ETA
  static const int _historyMax = 120;        // ~4 minutes @ 2s interval (tune)

  @override
  void initState() {
    super.initState();

    // Register method call handler
    _bleChannel.setMethodCallHandler(_handleBluetoothData);

    // Poll moisture sensor every 3s
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
      OperationHistory.instance.logReading(id, _moisture);
      // endOperation() persists internally (Firestore/local). Fire-and-forget.
      // ignore: discarded_futures
      OperationHistory.instance.endOperation(id);
    }

    super.dispose();
  }


    // ---------------------- Helpers ----------------------
  double _scaleForWidth(double width) => (width / 375).clamp(0.85, 1.25);

  String _fmtTime(Duration d) {
    String two(int n) => n.toString().padLeft(2, "0");
    if (d.inHours > 0) {
      return "${d.inHours}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}";
    }
    return "${two(d.inMinutes)}:${two(d.inSeconds.remainder(60))}";
  }

  // Color from dark yellow → light yellow
  Color _ringColor(double p) {
    return Color.lerp(
      const Color(0xFFB58900), // dark yellow
      const Color(0xFFFFFF8D), // light yellow
      p.clamp(0.0, 1.0),
    )!;
  }

  void _pushMcSample(double mc) {
    _mcHistory.add(_McSample(DateTime.now(), mc));
    if (_mcHistory.length > _historyMax) {
      _mcHistory.removeAt(0);
    }
  }
  void _parseDhtResponse(String rawData) {
      final lines = rawData.split(RegExp(r'[\r\n]+'));
      for (final line in lines) {
        final data = line.trim();
        if (data.isEmpty) continue;

        print("📨 Processing line: $data");

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
              _moisture = h!;
              _temperature = t!;
            });
            print("🟢 Humidity: $_moisture%, Temp: $_temperature°C");
          } else {
            print("⚠️ Failed to parse humidity/temp");
          }
        } else {
          print("⚠️ Unrecognized data: $data");
        }
      }
    }




    /// Estimate drying slope (Δ%MC per minute, negative when drying).
  /// Uses simple linear regression over the last N samples for robustness.
  double? _estimateSlopePerMin({int minPoints = 10}) {
    final n = _mcHistory.length;
    if (n < minPoints) return null;

    // Convert to minutes since first sample to avoid large x-values
    final t0 = _mcHistory.first.ts;
    final xs = <double>[];
    final ys = <double>[];
    for (final s in _mcHistory) {
      xs.add(s.ts.difference(t0).inMilliseconds / 60000.0); // minutes
      ys.add(s.mc);
    }

    // Linear regression y = a + b*x
    final meanX = xs.reduce((a, b) => a + b) / xs.length;
    final meanY = ys.reduce((a, b) => a + b) / ys.length;

    double num = 0.0, den = 0.0;
    for (var i = 0; i < xs.length; i++) {
      final dx = xs[i] - meanX;
      num += dx * (ys[i] - meanY);
      den += dx * dx;
    }
    if (den == 0) return null;

    final b = num / den; // slope in %MC per minute (should be negative)
    // Smooth a bit with last computed slope if you want (omitted here for clarity)
    return b;
  }

  /// Progress toward 14% based on initial MC and current MC.
  double get _targetProgress {
    if (_initialMc == null) return 0.0;
    final span = (_initialMc! - _targetMc);
    if (span <= 0) return 1.0; // edge case: already <= target at start
    final done = (_initialMc! - _moisture);
    return (done / span).clamp(0.0, 1.0);
  }

  /// ETA (minutes) to reach 14% based on current slope.
  double? get _etaMinutes {
    final slope = _estimateSlopePerMin();
    if (slope == null || slope >= -1e-6) return null; // need negative slope
    final delta = (_moisture - _targetMc);
    if (delta <= 0) return 0.0;
    return delta / (-slope);
  }

  Future<void> _confirm({
    required String title,
    required String message,
    required VoidCallback onConfirm,
  }) async {
    final cs = Theme.of(context).colorScheme;
    TextStyle t(double sz, {FontWeight? w, Color? c}) =>
        GoogleFonts.poppins(fontSize: sz, fontWeight: w, color: c ?? cs.onSurface);

    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: t(18, w: FontWeight.w700)),
        content: Text(message, style: t(14, c: cs.onSurface.withOpacity(0.85))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Cancel", style: t(14, w: FontWeight.w600, c: context.brand)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: Text("Confirm", style: t(14, w: FontWeight.w700, c: cs.onPrimary)),
          ),
        ],
      ),
    );
  }
    Future<void> _handleBluetoothData(MethodCall call) async {
        if (call.method == "onDataReceived") {
          final String data = call.arguments.toString().trim();
          print("📩 Native pushed: $data");
          _parseDhtResponse(data);
        }
      }
    Future<void> _sendCommand(String command) async {
      try {
        final response = await _bleChannel.invokeMethod<String>('sendData', {'data': command});
        if (response == null) {
          Fluttertoast.showToast(msg: "No response from ESP32");
        } else {
          print("📨 Got response: $response");
          _parseDhtResponse(response);
        }
      } catch (e) {
        Fluttertoast.showToast(msg: "Bluetooth error: $e");
      }
    }
    // ---------------------- Controls ----------------------
    void _startStopwatch() {
      setState(() {
        _isRunning = true;
        _isPaused = false;
        _elapsed = Duration.zero;
        _initialMc = _moisture;  // capture starting MC for progress
        _mcHistory.clear();
        _pushMcSample(_moisture);
      });

      AutomationPage.isActive.value = true;
      AutomationPage.progress.value = _targetProgress;

      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() {
          _elapsed += const Duration(seconds: 1);
        });
        AutomationPage.progress.value = _targetProgress;
      });

      _currentOpId = OperationHistory.instance.startOperation();
      OperationHistory.instance.logReading(_currentOpId!, _moisture);

      _sendCommand("ON1");
      _sendCommand("ON2");
      _sendCommand("ON3");
      _sendCommand("ON4");
    }


  void _pauseStopwatch() {
    _ticker?.cancel();
    setState(() {
      _isPaused = true;
      _isRunning = false;
    });
    AutomationPage.isActive.value = true; // still “active” but paused
    AutomationPage.progress.value = _targetProgress;
  }

  void _resumeStopwatch() {
    setState(() {
      _isPaused = false;
      _isRunning = true;
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _elapsed += const Duration(seconds: 1);
      });
      AutomationPage.progress.value = _targetProgress;
    });
  }

// automation.dart
  Future<void> _stopStopwatch() async {          // <-- async
    _ticker?.cancel();
    setState(() {
      _elapsed = Duration.zero;
      _isPaused = false;
      _isRunning = false;
    });
    AutomationPage.isActive.value = false;
    AutomationPage.progress.value = 0.0;
    if (_currentOpId != null) {
      final id = _currentOpId!;
      _currentOpId = null;

      OperationHistory.instance.logReading(id, _moisture);
      await OperationHistory.instance.endOperation(id); // persists internally

      _sendCommand("OFF1");
      _sendCommand("OFF2");
      _sendCommand("OFF3");
      _sendCommand("OFF4");
    }
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
            final double timerText = (48 * scale).clamp(36, 64).toDouble();

            // Buttons
            final ButtonStyle startStyle = ElevatedButton.styleFrom(
              backgroundColor: context.brand,
              foregroundColor: cs.onPrimary,
              elevation: 0,
              padding: EdgeInsets.symmetric(
                horizontal: (22 * scale).clamp(16, 28).toDouble(),
                vertical: (14 * scale).clamp(10, 18).toDouble(),
              ),
              minimumSize: Size(0, (44 * scale).clamp(40, 52).toDouble()),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
            );

            final ButtonStyle pauseResumeStyle = ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade700,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: EdgeInsets.symmetric(
                horizontal: (22 * scale).clamp(16, 28).toDouble(),
                vertical: (14 * scale).clamp(10, 18).toDouble(),
              ),
              minimumSize: Size(0, (44 * scale).clamp(40, 52).toDouble()),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
            );

            final ButtonStyle stopStyle = ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: EdgeInsets.symmetric(
                horizontal: (22 * scale).clamp(16, 28).toDouble(),
                vertical: (14 * scale).clamp(10, 18).toDouble(),
              ),
              minimumSize: Size(0, (44 * scale).clamp(40, 52).toDouble()),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
            );

            // Typo helper
            TextStyle t(double sz, {FontWeight? w, Color? c}) =>
                GoogleFonts.poppins(fontSize: sz, fontWeight: w, color: c ?? cs.onSurface);

            Widget metricRow() {
              return Row(
                children: [
                  Expanded(
                    child: _metricCard(
                      minHeight: tileMinH,
                      pad: cardPad,
                      icon: Icons.water_drop_outlined,
                      label: "Humidity",
                      value: "${_moisture.toStringAsFixed(1)}%",
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

            Widget etaBadge() {
              final eta = _etaMinutes;
              String txt;
              if (eta == null) {
                txt = "Estimating…";
              } else if (eta <= 0) {
                txt = "At/Below 14%";
              } else if (eta < 60) {
                txt = "~${eta.ceil()} min remaining";
              } else {
                final h = (eta / 60).floor();
                final m = (eta % 60).ceil();
                txt = "~${h}h ${m}m remaining";
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
                  txt,
                  style: t((12 * scale).clamp(11, 15).toDouble(),
                      w: FontWeight.w700, c: cs.onSecondaryContainer),
                ),
              );
            }

            final ringProgress = _targetProgress;       // drives arc completion
            final colorProgress = ringProgress;         // drives color dark→light
            final dotColor = _ringColor(colorProgress); // dot color

            // ------------------ Layout ------------------
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentMaxWidth),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // ───────── Metrics Card ─────────
                      Card(
                        child: Padding(
                          padding: EdgeInsets.all(cardPad),
                          child: metricRow(),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // ───────── Session Tracker Card ─────────
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
                                    "Session Tracker",
                                    style: t((16 * scale).clamp(14, 20).toDouble(),
                                        w: FontWeight.w700, c: context.brand),
                                  ),
                                  etaBadge(),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Circular progress based on target progress
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
                                          color: _ringColor(colorProgress),
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
                                                  blurRadius: (10 * scale).clamp(6, 14).toDouble(),
                                                  spreadRadius: (2 * scale).clamp(1, 3).toDouble(),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Center readout
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _fmtTime(_elapsed),
                                            style: t(timerText, w: FontWeight.w800),
                                          ),
                                          SizedBox(height: (6 * scale).clamp(4, 10).toDouble()),
                                          Text(
                                            _initialMc == null
                                                ? "— / ${_targetMc.toStringAsFixed(0)}% MC"
                                                : "${_moisture.toStringAsFixed(1)}% RH",
                                            style: t((14 * scale).clamp(12, 18).toDouble(),
                                                w: FontWeight.w600, c: cs.onSurface.withOpacity(0.8)),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              }),

                              SizedBox(height: (16 * scale).clamp(12, 22).toDouble()),
                              _controlsRow(startStyle, pauseResumeStyle, stopStyle, t),
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

  Future<void> _readMoistureSensor() async {
      try {
        final response = await _bleChannel.invokeMethod<String>('sendData', {'data': 'GET_MOISTURE'});
        if (response != null && response.startsWith("MOISTURE:")) {
          final raw = response.replaceFirst("MOISTURE:", "").trim();
          final value = double.tryParse(raw);
          if (value != null) {
            // Convert to percent (if needed); depends on your calibration
            final percent = 100 - (value / 4095.0 * 100);
            setState(() {
              _moisture = percent.clamp(0, 100);
            });
          }
        }
      } catch (e) {
        Fluttertoast.showToast(msg: "Failed to read moisture: $e");
      }
    }

    // ------- Controls Row -------
  Widget _controlsRow(
      ButtonStyle startStyle,
      ButtonStyle pauseResumeStyle,
      ButtonStyle stopStyle,
      TextStyle Function(double, {FontWeight? w, Color? c}) t,
      ) {
    Widget label(String text) => FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: t(14, w: FontWeight.w700, c: Colors.white),
      ),
    );

    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            style: stopStyle,
            onPressed: () {
              if (!(_isRunning || _isPaused)) return;
              _confirm(
                title: "Stop Session",
                message: "You are about to stop the current session.",
                onConfirm: _stopStopwatch,
              );
            },
            child: label("Stop"),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            style: pauseResumeStyle,
            onPressed: () {
              if (_ticker != null && _isRunning) {
                _pauseStopwatch();
              } else if (_isPaused) {
                _resumeStopwatch();
              }
            },
            child: label(_isPaused ? "Resume" : "Pause"),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            style: startStyle,
            onPressed: () {
              if (_isRunning) {
                Fluttertoast.showToast(msg: "Session is ongoing, stop first to restart");
                return;
              }
              _confirm(
                title: "Start Session",
                message: "Start a new drying session?",
                onConfirm: () {
                  Fluttertoast.showToast(msg: "Session started");
                  _startStopwatch();
                },
              );
            },
            child: label("Start"),
          ),
        ),
      ],
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

// ───────────────────────────────── Painter (progress to target) ────────────────────────────────
class _TargetRingPainter extends CustomPainter {
  final BuildContext context;
  final double progress; // 0.0 → 1.0 (toward target MC)
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
      ..color = color
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Base ring
    canvas.drawCircle(center, radius, base);

    // Progress arc
    final sweep = 2 * math.pi * progress;
    final rect = Rect.fromCircle(center: center, radius: radius);

  }

  @override
  bool shouldRepaint(covariant _TargetRingPainter old) =>
      old.progress != progress ||
          old.track != track ||
          old.stroke != stroke ||
          old.color != color;
}

// Simple container for moisture history
class _McSample {
  final DateTime ts;
  final double mc;
  _McSample(this.ts, this.mc);
}