// lib/pages/automation/automation.dart
import 'dart:async';
import 'dart:math';
import 'dart:math' as math show pi;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter/services.dart';
import 'package:nice_rice/data/operation_persistence.dart';

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
  Timer? _ticker; // 1s heartbeat
  Duration _elapsed = Duration.zero; // UI stopwatch
  bool _isPaused = false;
  bool _isRunning = false;
  String? _currentOpId;

  // ---------------------- Sensors ----------------------
  Timer? _sensorTimer;
  double _moisture = 0.0; // current RH (%)
  double _temperature = 27.0;

  // ---------------------- Drying planner ----------------------
  // Target MC input (validated 9–14)
  double _targetMc = 14.0;

  // Estimated initial MC chosen from preset
  // 0 = none, 1 = 20–25, 2 = 26–30, 3 = 15–19
  int _initialPreset = 0;

  // Captured at session start (for logs/display)
  double? _initialMc;

  // INTERNAL drying rate (hidden from UI). Change here when you recalibrate.
  static const double _kRatePctPerMin = 0.5; // e.g., 0.5 %MC / min

  // Planned duration for the timer (computed at Commence)
  Duration? _plannedDuration;

  // History kept for your future slope-based estimator (kept for later)
  final List<_McSample> _mcHistory = [];
  static const int _historyMax = 120;

  @override
  void initState() {
    super.initState();

    _bleChannel.setMethodCallHandler(_handleBluetoothData);

    // Poll sensor every 3s
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
      OperationHistory.instance.logReading(_currentOpId!, _moisture);
      final op = OperationHistory.instance.endOperation(_currentOpId!);
      if (op != null) {
        OperationPersistence.save(op);
      }
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

  Color _ringColor(double p) {
    return Color.lerp(const Color(0xFFB58900), const Color(0xFFFFFF8D), p.clamp(0.0, 1.0))!;
  }

  void _pushMcSample(double mc) {
    _mcHistory.add(_McSample(DateTime.now(), mc));
    if (_mcHistory.length > _historyMax) _mcHistory.removeAt(0);
  }

  // ------- BLE parsing -------
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
            _moisture = h!;
            _temperature = t!;
          });
        }
      }
    }
  }

  // Kept for future slope-based estimator (not used by timer now)
  double? _estimateSlopePerMin({int minPoints = 10}) => null;

  // ───────── Time-based progress for the ring ─────────
  double get _timeProgress {
    if (_plannedDuration == null || _plannedDuration!.inSeconds <= 0) return 0;
    return (_elapsed.inMilliseconds / _plannedDuration!.inMilliseconds).clamp(0.0, 1.0);
  }

  String get _etaLabel {
    if (!(_isRunning || _isPaused) || _plannedDuration == null) return "";
    final remaining = _plannedDuration! - _elapsed < Duration.zero ? Duration.zero : _plannedDuration! - _elapsed;
    if (remaining.inMinutes < 60) {
      final m = remaining.inMinutes;
      final s = remaining.inSeconds.remainder(60);
      return m > 0 ? "~${m}m ${s}s remaining" : "~${s}s remaining";
    } else {
      final h = remaining.inHours;
      final m = remaining.inMinutes.remainder(60);
      return "~${h}h ${m}m remaining";
    }
  }

  // ───────── Inputs / validation ─────────
  void _setTargetMc(double v) {
    setState(() => _targetMc = v.clamp(9.0, 14.0));
  }

  String _targetTip(double v) {
    if (v <= 9.5) return "9% MC → for long-term seed preservation.";
    if (v >= 13.0) return "13–14% MC → 2–3 months storage; recommended for milling.";
    if (v >= 12.0 && v <= 12.5) return "12–12.5% MC → storage beyond 3 months.";
    return "Pick 9–14% based on purpose.";
  }

  void _pickPreset(int idx) => setState(() => _initialPreset = idx);

  /// Returns the (low, high) initial MC range and its midpoint.
  ({double low, double high, double mid})? _presetRange(int idx) {
    switch (idx) {
      case 1:
        return (low: 20.0, high: 25.0, mid: 22.5);
      case 2:
        return (low: 26.0, high: 30.0, mid: 28.0);
      case 3:
        return (low: 15.0, high: 19.0, mid: 17.0);
      default:
        return null;
    }
  }

  /// Compute planned duration using loss range → average loss → time.
  /// Adds a small buffer (10%) to account for ramp/overheads; clamp to >= 1 min.
  Duration? _computePlanDuration() {
    final range = _presetRange(_initialPreset);
    if (range == null) return null;

    final lowLoss  = (range.low  - _targetMc).clamp(0, double.infinity);
    final highLoss = (range.high - _targetMc).clamp(0, double.infinity);

    // If both are zero, already at/below target.
    if (lowLoss == 0 && highLoss == 0) return Duration.zero;

    final avgLoss = (lowLoss + highLoss) / 2.0;

    // Time (minutes) = average loss / rate, then add buffer
    double minutes = avgLoss / _kRatePctPerMin;
    minutes *= 1.10; // +10% buffer

    // Round to nearest 30 seconds for friendlier display
    final seconds = (minutes * 60);
    final rounded = (seconds / 30).round() * 30;
    final result = Duration(seconds: rounded);

    // Minimum 1 minute if > 0
    if (result == Duration.zero && (avgLoss > 0)) {
      return const Duration(minutes: 1);
    }
    return result;
  }

  // ---------------------- Confirm dialog ----------------------
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

  // ---------------------- BLE helpers ----------------------
  Future<void> _handleBluetoothData(MethodCall call) async {
    if (call.method == "onDataReceived") {
      final String data = call.arguments.toString().trim();
      _parseDhtResponse(data);
    }
  }

  Future<void> _sendCommand(String command) async {
    try {
      final response = await _bleChannel.invokeMethod<String>('sendData', {'data': command});
      if (response != null) _parseDhtResponse(response);
    } catch (e) {
      Fluttertoast.showToast(msg: "Bluetooth error: $e");
    }
  }

  // ---------------------- Controls ----------------------
  void _startStopwatch() {
    // Validate inputs
    if (_initialPreset == 0) {
      Fluttertoast.showToast(msg: "Pick an initial MC preset first.");
      return;
    }
    if (_targetMc < 9 || _targetMc > 14) {
      Fluttertoast.showToast(msg: "Target MC must be between 9% and 14%.");
      return;
    }

    final plan = _computePlanDuration();
    if (plan == null) {
      Fluttertoast.showToast(msg: "Cannot compute time estimate.");
      return;
    }

    final preset = _presetRange(_initialPreset)!;
    setState(() {
      _isRunning = true;
      _isPaused = false;
      _elapsed = Duration.zero;
      _initialMc = preset.mid;       // midpoint for logging
      _plannedDuration = plan;
      _mcHistory.clear();
      _pushMcSample(_initialMc!);
    });

    AutomationPage.isActive.value = true;
    AutomationPage.progress.value = _timeProgress;

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isRunning) return;
      setState(() => _elapsed += const Duration(seconds: 1));
      AutomationPage.progress.value = _timeProgress;

      // Auto-complete when time is up
      if (_plannedDuration != null && _elapsed >= _plannedDuration! && _isRunning) {
        _stopStopwatch();
      }
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
    AutomationPage.isActive.value = true;
    AutomationPage.progress.value = _timeProgress;
  }

  void _resumeStopwatch() {
    setState(() {
      _isPaused = false;
      _isRunning = true;
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed += const Duration(seconds: 1));
      AutomationPage.progress.value = _timeProgress;

      if (_plannedDuration != null && _elapsed >= _plannedDuration! && _isRunning) {
        _stopStopwatch();
      }
    });
  }

  Future<void> _stopStopwatch() async {
    _ticker?.cancel();
    setState(() {
      _elapsed = Duration.zero;
      _isPaused = false;
      _isRunning = false;
    });
    AutomationPage.isActive.value = false;
    AutomationPage.progress.value = 0.0;

    if (_currentOpId != null) {
      OperationHistory.instance.logReading(_currentOpId!, _moisture);
      final op = OperationHistory.instance.endOperation(_currentOpId!);
      if (op != null) {
        try {
          await OperationPersistence.save(op);
          debugPrint('SAVE: success ${op.id}');
        } catch (e, st) {
          debugPrint('SAVE: failed $e\n$st');
        }
      }
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

    TextStyle t(double sz, {FontWeight? w, Color? c}) =>
        GoogleFonts.poppins(fontSize: sz, fontWeight: w, color: c ?? cs.onSurface);

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
            final double contentMaxWidth = isTablet ? 860.0 : 600.0;

            final double cardPad   = (16 * scale).clamp(12, 22).toDouble();
            final double tileMinH  = (140 * scale).clamp(120, 180).toDouble();
            final double timerSide = (maxW * (isTablet ? 0.55 : 0.75)).clamp(240, 520).toDouble();
            final double ringTrack = (8 * scale).clamp(6, 12).toDouble();
            final double ringStroke= (12 * scale).clamp(10, 16).toDouble();
            final double dotSize   = (18 * scale).clamp(14, 24).toDouble();
            final double timerText = (48 * scale).clamp(36, 64).toDouble();

            // Buttons
            final ButtonStyle commenceStyle = ElevatedButton.styleFrom(
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

            // ───────── Planner Card (target + horizontal preset buttons) ─────────
            Widget plannerCard() {
              return Card(
                child: Padding(
                  padding: EdgeInsets.all(cardPad),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text("Plan Drying Session",
                          style: t((16 * scale).clamp(14, 20).toDouble(),
                              w: FontWeight.w700, c: context.brand)),
                      const SizedBox(height: 12),

                      // Target MC
                      Text("Target moisture content", style: t(13, w: FontWeight.w600)),
                      Row(
                        children: [
                          Expanded(
                            child: Slider(
                              value: _targetMc,
                              min: 9,
                              max: 14,
                              divisions: 10,
                              label: "${_targetMc.toStringAsFixed(1)}%",
                              onChanged: (v) => _setTargetMc(v),
                            ),
                          ),
                          SizedBox(
                            width: 70,
                            child: Text("${_targetMc.toStringAsFixed(1)}%",
                                textAlign: TextAlign.end, style: t(14, w: FontWeight.w700)),
                          ),
                        ],
                      ),
                      Text(_targetTip(_targetMc),
                          style: t(12, c: cs.onSurface.withOpacity(0.75))),
                      const SizedBox(height: 12),

                      Text("Estimated initial moisture (choose one)",
                          style: t(13, w: FontWeight.w600)),
                      const SizedBox(height: 8),

                      // Three equal-width preset buttons in a single horizontal row
                      LayoutBuilder(builder: (ctx, c) {
                        return Row(
                          children: [
                            Expanded(child: _presetButton(
                              selected: _initialPreset == 1,
                              onTap: () => _pickPreset(1),
                              percent: "20–25%",
                              caption: "on-time, safely threshed",
                            )),
                            const SizedBox(width: 8),
                            Expanded(child: _presetButton(
                              selected: _initialPreset == 2,
                              onTap: () => _pickPreset(2),
                              percent: "26–30%",
                              caption: "early harvest (too wet)",
                            )),
                            const SizedBox(width: 8),
                            Expanded(child: _presetButton(
                              selected: _initialPreset == 3,
                              onTap: () => _pickPreset(3),
                              percent: "15–19%",
                              caption: "late harvest (too dry)",
                            )),
                          ],
                        );
                      }),

                      const SizedBox(height: 12),

                      // Planned duration preview (based on selection)
                      Builder(builder: (_) {
                        final d = _computePlanDuration();
                        String label;
                        if (d == null) {
                          label = "Pick a preset to preview the estimate.";
                        } else if (d == Duration.zero) {
                          label = "Initial MC is already at/below target — no time needed.";
                        } else {
                          final h = d.inHours;
                          final m = d.inMinutes.remainder(60);
                          final s = d.inSeconds.remainder(60);
                          label = "Estimated drying time: ${h > 0 ? "${h}h " : ""}${m}m ${s}s";
                        }
                        return Text(label, style: t(12, c: cs.onSurface.withOpacity(0.75)));
                      }),

                      const SizedBox(height: 14),

                      // Commence session button (the only Start button)
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              style: commenceStyle,
                              onPressed: () {
                                if (_isRunning) {
                                  Fluttertoast.showToast(
                                      msg: "Session is ongoing, stop first to restart");
                                  return;
                                }
                                _confirm(
                                  title: "Commence Session",
                                  message: "Begin drying using the estimated time?",
                                  onConfirm: () {
                                    Fluttertoast.showToast(msg: "Session started");
                                    _startStopwatch();
                                  },
                                );
                              },
                              child: Text("Commence session",
                                  style: t(14, w: FontWeight.w700, c: cs.onPrimary)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }

            // Metrics card
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

            final ringProgress = _timeProgress;
            final colorProgress = ringProgress;
            final dotColor = _ringColor(colorProgress);

            // ------------------ Layout ------------------
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentMaxWidth),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      plannerCard(),
                      const SizedBox(height: 14),

                      Card(
                        child: Padding(
                          padding: EdgeInsets.all(cardPad),
                          child: metricRow(),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Session Tracker Card — only shows timer once session started/paused
                      if (_isRunning || _isPaused) Card(
                        child: Padding(
                          padding: EdgeInsets.all(cardPad),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text("Session Tracker",
                                      style: t((16 * scale).clamp(14, 20).toDouble(),
                                          w: FontWeight.w700, c: context.brand)),
                                  if (_etaLabel.isNotEmpty)
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: (10 * scale).clamp(8, 14).toDouble(),
                                        vertical: (6 * scale).clamp(4, 10).toDouble(),
                                      ),
                                      decoration: BoxDecoration(
                                        color: cs.secondaryContainer,
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(_etaLabel,
                                          style: t((12 * scale).clamp(11, 15).toDouble(),
                                              w: FontWeight.w700,
                                              c: cs.onSecondaryContainer)),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),

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
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(_fmtTime(_elapsed),
                                              style: t(timerText, w: FontWeight.w800)),
                                          SizedBox(height: (6 * scale).clamp(4, 10).toDouble()),
                                          Text("Target ${_targetMc.toStringAsFixed(1)}% MC",
                                              style: t((14 * scale).clamp(12, 18).toDouble(),
                                                  w: FontWeight.w600,
                                                  c: cs.onSurface.withOpacity(0.8))),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              }),

                              SizedBox(height: (16 * scale).clamp(12, 22).toDouble()),
                              _controlsRow(pauseResumeStyle, stopStyle, t),
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

  // ------- Controls Row (no Commence here—only Pause/Resume + Stop) -------
  Widget _controlsRow(
    ButtonStyle pauseResumeStyle,
    ButtonStyle stopStyle,
    TextStyle Function(double, {FontWeight? w, Color? c}) t,
  ) {
    Widget label(String text) => FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, maxLines: 1, softWrap: false, style: t(14, w: FontWeight.w700, c: Colors.white)),
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
          Color color = const Color(0x00000000),
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

  // ------- Horizontal preset button -------
  Widget _presetButton({
    required bool selected,
    required VoidCallback onTap,
    required String percent,
    required String caption, // non-bold
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? cs.primary : cs.outline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              percent,
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: selected ? cs.onPrimary : cs.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              caption,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w400, // not bold
                color: selected ? cs.onPrimary.withOpacity(0.9) : cs.onSurface.withOpacity(0.8),
              ),
            ),
          ],
        ),
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

// ───────────────────── Painter (progress to target TIME) ─────────────────────
class _TargetRingPainter extends CustomPainter {
  final BuildContext context;
  final double progress; // 0.0 → 1.0 (time progress)
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
    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final startAngle = -math.pi / 2; // start at top
    canvas.drawArc(rect, startAngle, sweep, false, progressPaint);
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
