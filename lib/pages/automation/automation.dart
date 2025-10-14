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

  /// 👉 NEW: HomePage publishes the **real** BT connection to these.
  static final ValueNotifier<bool> btConnected = ValueNotifier<bool>(false);
  static final ValueNotifier<String?> btDeviceName = ValueNotifier<String?>(null);

  @override
  State<AutomationPage> createState() => _AutomationPageState();
}

enum InitialBracket {
  ideal,  // 20-25% (ideal harvest)
  late,   // 15-19% (late harvest - too dry)
  early,  // 26-30% (early harvest - too wet)
}

extension on InitialBracket {
  String get title {
    switch (this) {
      case InitialBracket.ideal: return "20–25%";
      case InitialBracket.late:  return "15–19%";
      case InitialBracket.early: return "26–30%";
    }
  }

  String get description {
    switch (this) {
      case InitialBracket.ideal: return "ideal harvest";
      case InitialBracket.late:  return "late harvest (too dry)";
      case InitialBracket.early: return "early harvest (too wet)";
    }
  }

  double get midpoint {
    switch (this) {
      case InitialBracket.ideal: return (20 + 25) / 2.0;
      case InitialBracket.late:  return (15 + 19) / 2.0;
      case InitialBracket.early: return (26 + 30) / 2.0;
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
  Timer? _ticker;
  Duration _sessionDuration = Duration.zero;
  Duration _remaining = Duration.zero;
  bool _isPaused = false;
  bool _isRunning = false;
  String? _currentOpId;

  // ---------------------- Sensors ----------------------
  Timer? _sensorTimer;
  final Random _rand = Random();
  double _humidity = 0.0;
  double _temperature = 0.0;

  final ValueNotifier<int> _sensorSeq = ValueNotifier<int>(0);

  // ---------------------- Target / Inputs ----------------------
  double _targetMc = 14.0;
  InitialBracket? _selectedBracket;

  // Remember previous settings for “start same” dialog
  double? _prevTargetMc;
  InitialBracket? _prevBracket;

  static const double _rateMcPerMin = 0.5; // % lost per minute
  double? _initialMcForSession;

  static const Color _ringSingleColor = Color.fromARGB(255, 63, 252, 88);

  // ---------------------- Preheat / Init Gate ----------------------
  static const double _preheatTempMin = 25.0;
  static const double _preheatTempMax = 70.0;

  bool _waitingForPreheat = false;
  bool _preheatReady = false;

  // ---------------------- Bluetooth helpers ----------------------
  // If native method is missing/slow, we won't crash.
  bool _assumeBtOnIfUnknown = true;

  // Unified safe invoker with timeout and broad error handling.
  Future<T?> _invokeBle<T>(String method, [dynamic args]) async {
    try {
      final res = await _bleChannel
          .invokeMethod<T>(method, args)
          .timeout(const Duration(seconds: 2));
      return res;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  void _goToHome() {
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/main',
      (route) => false,
      arguments: 0,
    );
  }

  Future<void> _showBluetoothRequiredDialog() async {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          "Connect to NiceRice on Home",
          style: GoogleFonts.poppins(fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Before starting, please enable Bluetooth and connect to your NiceRice device from the Home page.",
              style: GoogleFonts.poppins(),
            ),
            const SizedBox(height: 8),
            Text(
              "Bago magsimula, buksan ang Bluetooth at ikonekta ang NiceRice device sa Home page.",
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: cs.onSurface.withOpacity(0.75),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text("Cancel", style: GoogleFonts.poppins(color: cs.primary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _goToHome();
            },
            child: Text("Go to Home",
                style: GoogleFonts.poppins(color: cs.onPrimary)),
          ),
        ],
      ),
    );
  }

  /// 👉 UPDATED: No dependency on non-existent native "isConnected".
  /// 1) Ensure BT is ON using `ensureBluetoothOn` (native will prompt/enable)
  /// 2) Check `AutomationPage.btConnected` that HomePage updates.
  Future<bool> _ensureBluetoothReadyOrExplain() async {
    final on = await _invokeBle<bool>('ensureBluetoothOn');
    final btOn = on ?? _assumeBtOnIfUnknown;

    final connected = AutomationPage.btConnected.value;
    if (!btOn || !connected) {
      await _showBluetoothRequiredDialog();
      return false;
    }
    return true;
  }

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

    if (_currentOpId != null) {
      final id = _currentOpId!;
      _currentOpId = null;
      OperationHistory.instance.logReading(id, _humidity);
      // ignore: discarded_futures
      OperationHistory.instance.endOperation(id);
      // ignore: discarded_futures
      _safeAllStop();
    } else {
      // ignore: discarded_futures
      _safeAllStop();
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

  double get _progress {
    if (_sessionDuration.inSeconds <= 0) return 0.0;
    final done = (_sessionDuration.inSeconds - _remaining.inSeconds)
        .clamp(0, _sessionDuration.inSeconds);
    return (done / _sessionDuration.inSeconds).clamp(0.0, 1.0);
  }

  // ---------------------- Power helpers ----------------------
  Future<void> _auxOn() async {
    await _sendCommand("ON2");
    await _sendCommand("ON3");
    await _sendCommand("ON4");
  }

  Future<void> _auxOff() async {
    await _sendCommand("OFF2");
    await _sendCommand("OFF3");
    await _sendCommand("OFF4");
  }

  Future<void> _safeAllStop() async {
    await _sendCommand("THERMO:OFF");
    await _sendCommand("OFF1");
    await _auxOff();
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
          _sensorSeq.value++;
          _maybeMarkPreheatReady();
        }
      }
    }
  }

  Future<void> _handleBluetoothData(MethodCall call) async {
    if (call.method == "onDataReceived") {
      final String data = call.arguments.toString().trim();
      _parseDhtResponse(data);

      for (final line in data.split(RegExp(r'[\r\n]+'))) {
        final msg = line.trim();
        if (msg.isEmpty) continue;

        if (msg == "EVENT:COUNTDOWN_START") {
          if (_waitingForPreheat) {
            setState(() => _waitingForPreheat = false);
          }
        } else if (msg == "EVENT:COUNTDOWN_DONE") {
          if (_isRunning) _finishSession(auto: true);
        } else if (msg == "EVENT:SAFETY_STOP") {
          Fluttertoast.showToast(msg: "Safety stop triggered by device");
          if (_isRunning) _finishSession();
        }
      }
    }
  }

  Future<void> _sendCommand(String command) async {
    final response = await _invokeBle<String>('sendData', {'data': command});
    if (response != null) {
      _parseDhtResponse(response);
    }
  }

  Future<void> _sendInitToDevice() async {
    if (_selectedBracket == null) return;

    switch (_selectedBracket!) {
      case InitialBracket.ideal:
        await _sendCommand("MODE:IDEAL");
        break;
      case InitialBracket.late:
        await _sendCommand("MODE:LATE");
        break;
      case InitialBracket.early:
        await _sendCommand("MODE:EARLY");
        break;
    }

    await _sendCommand("SET:TARGET_MC=${_targetMc.toStringAsFixed(1)}");

    final etaMin = _computeEtaMinutes();
    if (etaMin != null) {
      final etaRounded = etaMin.clamp(0, 9999).toStringAsFixed(1);
      await _sendCommand("SET:ETA_MIN=$etaRounded");
    }

    await _sendCommand("THERMO:ON");
  }

  // --------------- ETA Computation ---------------
  double? _computeEtaMinutes() {
    if (_selectedBracket == null) return null;
    final initialMid = _selectedBracket!.midpoint;
    final delta = (initialMid - _targetMc);
    if (delta <= 0) return 0.0;
    if (_rateMcPerMin <= 0) return null;
    return delta / _rateMcPerMin;
  }

  // ---------------------- Target Tip Mapping ----------------------
  String _tipForTargetMc(double mc) {
    if (mc >= 9.0 && mc <= 9.5) {
      return "9–9.5% • good for long-term seed preservation";
    } else if (mc > 9.5 && mc <= 11.5) {
      return "10–11.5% • good for short-term seed preservation";
    } else if (mc > 11.5 && mc <= 12.5) {
      return "12–12.5% • for storage beyond 3 months";
    } else if (mc > 12.5 && mc <= 14.0) {
      return "13–14% • for storage within 2–3 months (recommended for milling)";
    }
    return "Select a target moisture content (9–14%)";
  }

  // ---------------------- Preheat / Init Flow ----------------------
  bool _meetsPreheatThresholds() {
    return _temperature >= _preheatTempMin && _temperature < _preheatTempMax;
    }

  void _maybeMarkPreheatReady() {
    if (!_waitingForPreheat || _preheatReady) return;
    if (_meetsPreheatThresholds()) {
      setState(() => _preheatReady = true);
      SystemSound.play(SystemSoundType.alert);
    }
  }

  Future<void> _startPreheatDialog() async {
    if (_isRunning) {
      Fluttertoast.showToast(msg: "A session is already running.");
      return;
    }
    if (!_inputsComplete) return;

    _waitingForPreheat = true;
    _preheatReady = _meetsPreheatThresholds();
    await _auxOn();

    final readyNotifier = ValueNotifier<bool>(_preheatReady);

    final syncTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted || !_waitingForPreheat) return;
      readyNotifier.value = _preheatReady;
    });

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        TextStyle t(double sz, {FontWeight? w, Color? c}) =>
            GoogleFonts.poppins(
                fontSize: sz, fontWeight: w, color: c ?? cs.onSurface);

        return ValueListenableBuilder<bool>(
          valueListenable: readyNotifier,
          builder: (ctx, isReady, _) {
            return Dialog(
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (!isReady) ...[
                      const SizedBox(height: 8),
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text("Initializing...", style: t(18, w: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text(
                        "Please wait for chamber to reach 45–70°C",
                        textAlign: TextAlign.center,
                        style: t(13,
                            w: FontWeight.w600,
                            c: cs.onSurface.withOpacity(0.8)),
                      ),
                      const SizedBox(height: 12),

                      ValueListenableBuilder<int>(
                        valueListenable: _sensorSeq,
                        builder: (_, __, ___) => Row(
                          children: [
                            Expanded(
                              child: _metricCard(
                                minHeight: 88,
                                pad: 10,
                                icon: Icons.water_drop_outlined,
                                label: "Humidity",
                                value: "${_humidity.toStringAsFixed(1)}%",
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _metricCard(
                                minHeight: 88,
                                pad: 10,
                                icon: Icons.thermostat_outlined,
                                label: "Temperature",
                                value: "${_temperature.toStringAsFixed(1)}°C",
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Target: temperature between 45°C and 70°C",
                        style: t(12,
                            w: FontWeight.w600,
                            c: cs.onSurface.withOpacity(0.7)),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                _waitingForPreheat = false;
                                _preheatReady = false;
                                _safeAllStop();
                                Navigator.pop(ctx);
                              },
                              child: Text("Cancel",
                                  style: t(14,
                                      w: FontWeight.w700,
                                      c: Theme.of(ctx).colorScheme.primary)),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      const Icon(Icons.check_circle,
                          size: 44, color: Colors.green),
                      const SizedBox(height: 16),
                      Text("You may now put your grains",
                          style: t(18, w: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text(
                        "Chamber is ready.",
                        textAlign: TextAlign.center,
                        style: t(13,
                            w: FontWeight.w600,
                            c: cs.onSurface.withOpacity(0.8)),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                _waitingForPreheat = false;
                                _preheatReady = false;
                                _safeAllStop();
                                Navigator.pop(ctx);
                              },
                              child: Text("Cancel",
                                  style: t(14,
                                      w: FontWeight.w700,
                                      c: Theme.of(ctx).colorScheme.primary)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                _waitingForPreheat = false;
                                Navigator.pop(ctx);
                                await _sendCommand("ARM:COUNTDOWN");
                                if (!_isRunning) _beginDrying();
                              },
                              child: Text("Start Drying",
                                  style: t(14,
                                      w: FontWeight.w700, c: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    syncTimer.cancel();
  }

  // ---------------------- Session Controls ----------------------
  bool get _inputsComplete =>
      _selectedBracket != null && _targetMc >= 9.0 && _targetMc <= 14.0;

  String get _prevSettingText {
    if (_prevBracket == null || _prevTargetMc == null) return "";
    final b = _prevBracket!;
    final m = _prevTargetMc!;
    return "${b.title} • ${b.description} • ${m.toStringAsFixed(1)}% target";
  }

  void _beginDrying() {
    if (_isRunning) {
      Fluttertoast.showToast(msg: "A session is already running.");
      return;
    }
    final etaMin = _computeEtaMinutes();
    if (etaMin == null) {
      Fluttertoast.showToast(msg: "Unable to compute estimated time.");
      return;
    }

    // remember settings for next time
    _prevBracket = _selectedBracket;
    _prevTargetMc = _targetMc;

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
        _finishSession(auto: true);
      }
    });

    _currentOpId = OperationHistory.instance.startOperation();
    OperationHistory.instance.logReading(_currentOpId!, _humidity);
    _auxOn();

    Fluttertoast.showToast(msg: "Drying started");
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
      await _safeAllStop();
    } else {
      await _safeAllStop();
    }

    if (auto) {
      Fluttertoast.showToast(msg: "Target reached • Session ended");
    }
  }

  void _pause() {
    if (!_isRunning || _isPaused) return;
    setState(() => _isPaused = true);
  }

  void _resume() {
    if (!_isRunning || !_isPaused) return;
    setState(() => _isPaused = false);
  }

  Future<void> _showStartWithPreviousDialog() async {
    if (_prevBracket == null || _prevTargetMc == null) {
      Fluttertoast.showToast(msg: "No previous settings found.");
      return;
    }
    final cs = Theme.of(context).colorScheme;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          "Start New Session",
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Start a new session using the previous settings?",
              style: GoogleFonts.poppins(
                  fontSize: 14, color: cs.onSurface.withOpacity(0.85)),
            ),
            const SizedBox(height: 8),
            Text(
              _prevSettingText,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: cs.onSurface.withOpacity(0.8),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              "Cancel",
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.brand,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() {
                _selectedBracket = _prevBracket;
                _targetMc = _prevTargetMc ?? _targetMc;
              });

              final ok = await _ensureBluetoothReadyOrExplain();
              if (!ok) return;

              await _sendInitToDevice();
              await _startPreheatDialog();
            },
            child: Text(
              "Confirm",
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: cs.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
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

            final double contentMaxWidth = isTablet ? 860.0 : 600.0;

            final double cardPad = (16 * scale).clamp(12, 22).toDouble();
            final double tileMinH = (140 * scale).clamp(120, 180).toDouble();
            final double timerSide =
                (maxW * (isTablet ? 0.55 : 0.75)).clamp(240, 520).toDouble();
            final double ringTrack = (8 * scale).clamp(6, 12).toDouble();
            final double ringStroke = (12 * scale).clamp(10, 16).toDouble();
            final double dotSize = (18 * scale).clamp(14, 24).toDouble();
            final double bigText = (48 * scale).clamp(36, 64).toDouble();

            TextStyle t(double sz, {FontWeight? w, Color? c}) =>
                GoogleFonts.poppins(
                    fontSize: sz, fontWeight: w, color: c ?? cs.onSurface);

            final ButtonStyle startStyle = ElevatedButton.styleFrom(
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(100)),
            );

            final ButtonStyle pauseStyle = ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade700,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: EdgeInsets.symmetric(
                  horizontal: (22 * scale).clamp(16, 28).toDouble(),
                  vertical: (14 * scale).clamp(10, 18).toDouble()),
              minimumSize: Size(0, (44 * scale).clamp(40, 52).toDouble()),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(100)),
            );

            final ButtonStyle playStyle = ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: EdgeInsets.symmetric(
                  horizontal: (22 * scale).clamp(16, 28).toDouble(),
                  vertical: (14 * scale).clamp(10, 18).toDouble()),
              minimumSize: Size(0, (44 * scale).clamp(40, 52).toDouble()),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(100)),
            );

            final ButtonStyle stopStyle = ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: EdgeInsets.symmetric(
                  horizontal: (22 * scale).clamp(16, 28).toDouble(),
                  vertical: (14 * scale).clamp(10, 18).toDouble()),
              minimumSize: Size(0, (44 * scale).clamp(40, 52).toDouble()),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(100)),
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
              final tip = _tipForTargetMc(_targetMc);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Target Moisture Content",
                      style: t(16, w: FontWeight.w700, c: context.brand)),
                  SizedBox(height: (10 * scale).clamp(6, 12).toDouble()),
                  Row(
                    children: [
                      Text("9%",
                          style: t(12,
                              w: FontWeight.w700,
                              c: cs.onSurface.withOpacity(0.7))),
                      Expanded(
                        child: Slider(
                          value: _targetMc,
                          min: 9.0,
                          max: 14.0,
                          divisions: 10,
                          label: "${_targetMc.toStringAsFixed(1)}%",
                          onChanged: (v) {
                            setState(() =>
                                _targetMc = double.parse(v.toStringAsFixed(1)));
                          },
                        ),
                      ),
                      Text("14%",
                          style: t(12,
                              w: FontWeight.w700,
                              c: cs.onSurface.withOpacity(0.7))),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tip,
                    style: t(13,
                        w: FontWeight.w600,
                        c: cs.onSurface.withOpacity(0.85)),
                  ),
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
                      padding:
                          EdgeInsets.all((12 * scale).clamp(10, 18).toDouble()),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: cs.outline.withOpacity(sel ? 0.0 : 1.0)),
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
                          const SizedBox(height: 6),
                          Text(
                            b.description,
                            textAlign: TextAlign.center,
                            style: t((12 * scale).clamp(11, 15).toDouble(),
                                w: FontWeight.w600,
                                c: fg.withOpacity(0.9)),
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
                  Text("Initial Moisture Content",
                      style: t(16, w: FontWeight.w700, c: context.brand)),
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
            final dotColor = _ringSingleColor;

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentMaxWidth),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // ───────── Optional inline banner to restart with previous ─────────
                      if (_prevBracket != null &&
                          _prevTargetMc != null &&
                          !_isRunning &&
                          !_waitingForPreheat) ...[
                        Card(
                          child: Padding(
                            padding: EdgeInsets.all(cardPad),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text("Start New Session",
                                          style: t(
                                              (16 * scale)
                                                  .clamp(14, 20)
                                                  .toDouble(),
                                              w: FontWeight.w700,
                                              c: context.brand)),
                                      const SizedBox(height: 6),
                                      Text(
                                        "Use previous settings:\n$_prevSettingText",
                                        style: t(12,
                                            w: FontWeight.w600,
                                            c: cs.onSurface.withOpacity(0.8)),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton(
                                  style: startStyle,
                                  onPressed: _showStartWithPreviousDialog,
                                  child: Text(
                                    "Start same",
                                    style: t(14,
                                        w: FontWeight.w700, c: cs.onPrimary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // ───────── Input Card ─────────
                      Card(
                        child: Padding(
                          padding: EdgeInsets.all(cardPad),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text("Session Plan",
                                  style: t(
                                      (16 * scale).clamp(14, 20).toDouble(),
                                      w: FontWeight.w700,
                                      c: context.brand)),
                              const SizedBox(height: 10),
                              targetSlider(),
                              const SizedBox(height: 14),
                              initialSelector(),
                              const SizedBox(height: 14),
                              etaBadge(),
                              const SizedBox(height: 14),
                              ElevatedButton(
                                style: startStyle,
                                onPressed: (_inputsComplete &&
                                        !_isRunning &&
                                        !_waitingForPreheat)
                                    ? () async {
                                        final ok = await _ensureBluetoothReadyOrExplain();
                                        if (!ok) return;

                                        await _sendInitToDevice();
                                        await _startPreheatDialog();
                                      }
                                    : null,
                                child: Text("Start",
                                    style: t(14,
                                        w: FontWeight.w700,
                                        c: cs.onPrimary)),
                              ),
                            ],
                          ),
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
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Session Timer",
                                    style: t(
                                        (16 * scale).clamp(14, 20).toDouble(),
                                        w: FontWeight.w700,
                                        c: context.brand),
                                  ),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: (10 * scale)
                                          .clamp(8, 14)
                                          .toDouble(),
                                      vertical:
                                          (6 * scale).clamp(4, 10).toDouble(),
                                    ),
                                    decoration: BoxDecoration(
                                      color: _isRunning
                                          ? (_isPaused
                                              ? Colors.amber.shade100
                                              : cs.secondaryContainer)
                                          : cs.surfaceVariant,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      _isRunning
                                          ? (_isPaused ? "Paused" : "Running")
                                          : (_waitingForPreheat
                                              ? "Initializing"
                                              : "Idle"),
                                      style: t(
                                          (12 * scale)
                                              .clamp(11, 15)
                                              .toDouble(),
                                          w: FontWeight.w700,
                                          c: _isRunning
                                              ? (_isPaused
                                                  ? Colors.amber.shade900
                                                  : cs.onSecondaryContainer)
                                              : cs.onSurface
                                                  .withOpacity(0.8)),
                                    ),
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
                                          color: _ringSingleColor,
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
                                                  color: dotColor
                                                      .withOpacity(0.45),
                                                  blurRadius:
                                                      (10 * scale).clamp(6, 14)
                                                          .toDouble(),
                                                  spreadRadius:
                                                      (2 * scale).clamp(1, 3)
                                                          .toDouble(),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _fmtDuration(_remaining),
                                            style:
                                                t(bigText, w: FontWeight.w800),
                                          ),
                                          SizedBox(
                                              height: (6 * scale)
                                                  .clamp(4, 10)
                                                  .toDouble()),
                                          Text(
                                            "to ${_targetMc.toStringAsFixed(1)}% MC",
                                            style: t(
                                                (14 * scale)
                                                    .clamp(12, 18)
                                                    .toDouble(),
                                                w: FontWeight.w600,
                                                c: cs.onSurface
                                                    .withOpacity(0.8)),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              }),

                              SizedBox(
                                  height:
                                      (16 * scale).clamp(12, 22).toDouble()),
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
                                        style: t(14,
                                            w: FontWeight.w700,
                                            c: Colors.white),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton(
                                      style: stopStyle,
                                      onPressed: _isRunning ||
                                              _waitingForPreheat ||
                                              _isPaused
                                          ? () async {
                                              final cs =
                                                  Theme.of(context).colorScheme;
                                              await showDialog(
                                                context: context,
                                                builder: (ctx) => AlertDialog(
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            16),
                                                  ),
                                                  title: Text("Stop Session",
                                                      style:
                                                          GoogleFonts.poppins(
                                                              fontSize: 18,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              color: cs
                                                                  .onSurface)),
                                                  content: Text(
                                                      "You are about to stop the current session.",
                                                      style:
                                                          GoogleFonts.poppins(
                                                              fontSize: 14,
                                                              color: cs
                                                                  .onSurface
                                                                  .withOpacity(
                                                                      0.85))),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(ctx),
                                                      child: Text("Cancel",
                                                          style: GoogleFonts
                                                              .poppins(
                                                                  fontSize: 14,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  color: context
                                                                      .brand)),
                                                    ),
                                                    ElevatedButton(
                                                      onPressed: () {
                                                        Navigator.pop(ctx);
                                                        if (_waitingForPreheat) {
                                                          _waitingForPreheat =
                                                              false;
                                                          _preheatReady = false;
                                                          _safeAllStop();
                                                        }
                                                        _finishSession();
                                                      },
                                                      child: Text("Confirm",
                                                          style: GoogleFonts
                                                              .poppins(
                                                                  fontSize: 14,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                  color: cs
                                                                      .onPrimary)),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }
                                          : null,
                                      child: Text(
                                        "Stop",
                                        style: t(14,
                                            w: FontWeight.w700,
                                            c: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(
                                  height:
                                      (16 * scale).clamp(12, 22).toDouble()),
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
          Color color = const Color(0x00000000),
          double? height,
          TextDecoration? deco,
        }) {
          final effective =
              color == const Color(0x00000000) ? cs.onSurface : color;
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

// ───────────────────────────── Painter ─────────────────────────────
class _TargetRingPainter extends CustomPainter {
  final BuildContext context;
  final double progress;
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

    canvas.drawCircle(center, radius, base);

    final sweep = 2 * math.pi * progress;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final startAngle = -math.pi / 2;
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
