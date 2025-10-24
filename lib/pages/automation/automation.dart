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

// ⬇️ Localizations
import 'package:nice_rice/l10n/app_localizations.dart';

class AutomationPage extends StatefulWidget {
  const AutomationPage({super.key});

  /// Exposed notifiers (read by HomePage to mirror Drying Chamber progress)
  static final ValueNotifier<bool> isActive = ValueNotifier<bool>(false);
  static final ValueNotifier<double> progress = ValueNotifier<double>(0.0);

  /// 👉 HomePage publishes the **real** BT connection to these.
  static final ValueNotifier<bool> btConnected = ValueNotifier<bool>(false);
  static final ValueNotifier<String?> btDeviceName = ValueNotifier<String?>(
    null,
  );

  @override
  State<AutomationPage> createState() => _AutomationPageState();
}

enum InitialBracket {
  ideal, // 20-25% (ideal harvest)
  late, // 15-19% (late harvest - too dry)
  early, // 26-30% (early harvest - too wet)
}

extension on InitialBracket {
  String title(AppLocalizations t) {
    switch (this) {
      case InitialBracket.ideal:
        return "20–25%";
      case InitialBracket.late:
        return "15–19%";
      case InitialBracket.early:
        return "26–30%";
    }
  }

  String description(AppLocalizations t) {
    switch (this) {
      case InitialBracket.ideal:
        return t.bracketIdeal;
      case InitialBracket.late:
        return t.bracketLate;
      case InitialBracket.early:
        return t.bracketEarly;
    }
  }

  double get midpoint {
    switch (this) {
      case InitialBracket.ideal:
        return (20 + 25) / 2.0;
      case InitialBracket.late:
        return (15 + 19) / 2.0;
      case InitialBracket.early:
        return (26 + 30) / 2.0;
    }
  }
}

class _AutomationPageState extends State<AutomationPage>
    with AutomaticKeepAliveClientMixin {
  static final MethodChannel _bleChannel = const MethodChannel(
    'app.bluetooth/controls',
  );

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
  static const double _preheatTempMin = 38.0;
  static const double _preheatTempMax = 50.0;

  bool _waitingForPreheat = false;
  bool _preheatReady = false;

  // ---------------------- Bluetooth helpers ----------------------
  bool _assumeBtOnIfUnknown = true;

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
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil('/main', (route) => false, arguments: 0);
  }

  Future<void> _showBluetoothRequiredDialog() async {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context)!;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          t.connectToHomeTitle,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.connectToHomeBody, style: GoogleFonts.poppins()),
            const SizedBox(height: 8),
            // 🔕 Removed per request: secondary translation line
            // Text(
            //   t.connectToHomeBodyAlt,
            //   style: GoogleFonts.poppins(
            //     fontSize: 12,
            //     color: cs.onSurface.withOpacity(0.75),
            //   ),
            // ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              t.cancel,
              style: GoogleFonts.poppins(color: cs.primary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _goToHome();
            },
            child: Text(
              t.goToHome,
              style: GoogleFonts.poppins(color: cs.onPrimary),
            ),
          ),
        ],
      ),
    );
  }

  /// 1) Ensure BT is ON  2) Check AutomationPage.btConnected
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

  // ---------- NEW: unified reaction when BT disconnects ----------
  void _handleSessionStopOnDisconnect() {
    // Stop any preheat & running timers, persist if needed, and notify.
    if (_waitingForPreheat) {
      _waitingForPreheat = false;
      _preheatReady = false;
    }
    if (_isRunning || _isPaused) {
      // This will cancel ticker, persist history, and show "Session saved"
      _finishSession(); // manual stop path
      final t = AppLocalizations.of(context)!;
      Fluttertoast.showToast(msg: t.deviceDisconnected);
    }
  }

  late final VoidCallback _btConnListener;

  @override
  void initState() {
    super.initState();

    // 🔔 Listen for BT connection state changes published by HomePage
    _btConnListener = () {
      if (!AutomationPage.btConnected.value) {
        _handleSessionStopOnDisconnect();
      }
    };
    AutomationPage.btConnected.addListener(_btConnListener);

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

    // remove BT listener
    AutomationPage.btConnected.removeListener(_btConnListener);

    AutomationPage.isActive.value = false;
    AutomationPage.progress.value = 0.0;

    if (_currentOpId != null) {
      final id = _currentOpId!;
      _currentOpId = null;
      OperationHistory.instance.logReading(id, _humidity);
      OperationHistory.instance.endOperation(id); // ignore: discarded_futures
      _safeAllStop(); // ignore: discarded_futures
    } else {
      _safeAllStop(); // ignore: discarded_futures
    }

    super.dispose();
  }

  // ---------------------- Helpers ----------------------
  double _scaleForWidth(double width) => (width / 375).clamp(0.85, 1.25);

  String _fmtDuration(Duration d) {
    final t = AppLocalizations.of(context)!;
    if (d.isNegative) return "00:00";
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    String two(int n) => n.toString().padLeft(2, "0");
    return h > 0 ? "$h:${two(m)}:${two(s)}" : "${two(m)}:${two(s)}";
  }

  double get _progress {
    if (_sessionDuration.inSeconds <= 0) return 0.0;
    final done = (_sessionDuration.inSeconds - _remaining.inSeconds).clamp(
      0,
      _sessionDuration.inSeconds,
    );
    return (done / _sessionDuration.inSeconds).clamp(0.0, 1.0);
  }

  // ---------------------- Power helpers ----------------------
  Future<void> _auxOn() async {
    await _sendCommand("ON2");
    await _sendCommand("ON3");
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
    final t = AppLocalizations.of(context)!;

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
          Fluttertoast.showToast(msg: t.safetyStop);
          if (_isRunning) _finishSession();
        }
      }
    }
    // NEW: handle explicit native disconnect callback (mirrors HomePage)
    else if (call.method == "onDisconnected") {
      _handleSessionStopOnDisconnect();
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
    final t = AppLocalizations.of(context)!;
    if (mc >= 9.0 && mc <= 9.5) {
      return t.tip_9_9_5;
    } else if (mc > 9.5 && mc <= 11.5) {
      return t.tip_10_11_5;
    } else if (mc > 11.5 && mc <= 12.5) {
      return t.tip_12_12_5;
    } else if (mc > 12.5 && mc <= 14.0) {
      return t.tip_13_14;
    }
    return t.tip_selectTarget;
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
    final t = AppLocalizations.of(context)!;

    if (_isRunning) {
      Fluttertoast.showToast(msg: t.sessionAlreadyRunning);
      return;
    }
    if (!_inputsComplete) return;

    _waitingForPreheat = true;
    _preheatReady = _meetsPreheatThresholds();
    await _auxOn();
    await _sendCommand("PULSE4");

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
        TextStyle tt(double sz, {FontWeight? w, Color? c}) =>
            GoogleFonts.poppins(
              fontSize: sz,
              fontWeight: w,
              color: c ?? cs.onSurface,
            );

        return ValueListenableBuilder<bool>(
          valueListenable: readyNotifier,
          builder: (ctx, isReady, _) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
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
                      Text(t.initializing, style: tt(18, w: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text(
                        t.waitForChamber,
                        textAlign: TextAlign.center,
                        style: tt(
                          13,
                          w: FontWeight.w600,
                          c: cs.onSurface.withOpacity(0.8),
                        ),
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
                                label: t.humidity,
                                value: "${_humidity.toStringAsFixed(1)}%",
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _metricCard(
                                minHeight: 88,
                                pad: 10,
                                icon: Icons.thermostat_outlined,
                                label: t.temperature,
                                value: "${_temperature.toStringAsFixed(1)}°C",
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t.targetTempRange,
                        style: tt(
                          12,
                          w: FontWeight.w600,
                          c: cs.onSurface.withOpacity(0.7),
                        ),
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
                              child: Text(
                                t.cancel,
                                style: tt(
                                  14,
                                  w: FontWeight.w700,
                                  c: Theme.of(ctx).colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      const Icon(
                        Icons.check_circle,
                        size: 44,
                        color: Colors.green,
                      ),
                      const SizedBox(height: 16),
                      Text(t.putGrainsNow, style: tt(18, w: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text(
                        t.chamberReady,
                        textAlign: TextAlign.center,
                        style: tt(
                          13,
                          w: FontWeight.w600,
                          c: cs.onSurface.withOpacity(0.8),
                        ),
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
                              child: Text(
                                t.cancel,
                                style: tt(
                                  14,
                                  w: FontWeight.w700,
                                  c: Theme.of(ctx).colorScheme.primary,
                                ),
                              ),
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
                              child: Text(
                                t.startDrying,
                                style: tt(
                                  14,
                                  w: FontWeight.w700,
                                  c: Colors.white,
                                ),
                              ),
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
    final t = AppLocalizations.of(context)!;
    if (_prevBracket == null || _prevTargetMc == null) return "";
    final b = _prevBracket!;
    final m = _prevTargetMc!;
    return "${b.title(t)} • ${b.description(t)} • ${m.toStringAsFixed(1)}% ${t.targetLower}";
  }

  void _beginDrying() {
    final t = AppLocalizations.of(context)!;

    if (_isRunning) {
      Fluttertoast.showToast(msg: t.sessionAlreadyRunning);
      return;
    }
    final etaMin = _computeEtaMinutes();
    if (etaMin == null) {
      Fluttertoast.showToast(msg: t.unableToComputeEta);
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

    Fluttertoast.showToast(msg: t.dryingStarted);
  }

  // NEW: tap-to-dismiss "Session saved" popup
  Future<void> _showSessionSavedPopup() async {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;

    await showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (ctx) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(ctx).pop(),
        child: Center(
          child: Card(
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.save_rounded, size: 48, color: Colors.green),
                  const SizedBox(height: 12),
                  Text(
                    "Session saved",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Tap anywhere to dismiss",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withOpacity(0.65),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _finishSession({bool auto = false}) async {
    final t = AppLocalizations.of(context)!;

    _ticker?.cancel();
    setState(() {
      _isPaused = false;
      _isRunning = false;
      _sessionDuration = Duration.zero;
      _remaining = Duration.zero;
    });
    AutomationPage.isActive.value = false;
    AutomationPage.progress.value = 0.0;

    // ✅ Always persist when a session ends (completed or stopped)
    if (_currentOpId != null) {
      final id = _currentOpId!;
      _currentOpId = null;

      OperationHistory.instance.logReading(id, _humidity);
      await OperationHistory.instance.endOperation(id);
      await _safeAllStop();
    } else {
      // Nothing to persist (e.g., stopped during preheat)
      await _safeAllStop();
    }

    // If it auto-completed to target, show the existing "Drying done" popup first.
    if (auto) {
      Fluttertoast.showToast(msg: t.targetReachedEnded);
      await _showDryingDonePopup();
    }

    // ✅ Then always show "Session saved" popup (tap-to-dismiss).
    await _showSessionSavedPopup();
  }

  // ⬇️ Tap-to-dismiss "Drying is done" popup
  Future<void> _showDryingDonePopup() async {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context)!;

    await showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (ctx) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(ctx).pop(),
        child: Center(
          child: Card(
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 48,
                    color: Colors.green,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t.targetReachedEnded, // localized success message
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t.startNewSessionBody, // small helper text (reuses existing string)
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withOpacity(0.75),
                    ),
                  ),
                  // Optional hint – remove if you don't have this key
                  // const SizedBox(height: 10),
                  // Text(
                  //   "(${t.tapToDismiss})",
                  //   textAlign: TextAlign.center,
                  //   style: GoogleFonts.poppins(
                  //     fontSize: 11,
                  //     fontWeight: FontWeight.w600,
                  //     color: cs.onSurface.withOpacity(0.6),
                  //   ),
                  // ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
    final t = AppLocalizations.of(context)!;

    if (_prevBracket == null || _prevTargetMc == null) {
      Fluttertoast.showToast(msg: t.noPreviousSettings);
      return;
    }
    final cs = Theme.of(context).colorScheme;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          t.startNewSession,
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
              t.startNewSessionBody,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: cs.onSurface.withOpacity(0.85),
              ),
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
              t.cancel,
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
              t.confirm,
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
    final t = AppLocalizations.of(context)!;

    // Lock inputs when session running or preheat in progress
    final bool inputsLocked = _isRunning || _waitingForPreheat;

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
            final double timerSide = (maxW * (isTablet ? 0.55 : 0.75))
                .clamp(240, 520)
                .toDouble();
            final double ringTrack = (8 * scale).clamp(6, 12).toDouble();
            final double ringStroke = (12 * scale).clamp(10, 16).toDouble();
            final double dotSize = (18 * scale).clamp(14, 24).toDouble();
            final double bigText = (48 * scale).clamp(36, 64).toDouble();

            TextStyle tx(double sz, {FontWeight? w, Color? c}) =>
                GoogleFonts.poppins(
                  fontSize: sz,
                  fontWeight: w,
                  color: c ?? cs.onSurface,
                );

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
                borderRadius: BorderRadius.circular(100),
              ),
            );

            final ButtonStyle pauseStyle = ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade700,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: EdgeInsets.symmetric(
                horizontal: (22 * scale).clamp(16, 28).toDouble(),
                vertical: (14 * scale).clamp(10, 18).toDouble(),
              ),
              minimumSize: Size(0, (44 * scale).clamp(40, 52).toDouble()),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(100),
              ),
            );

            final ButtonStyle playStyle = ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: EdgeInsets.symmetric(
                horizontal: (22 * scale).clamp(16, 28).toDouble(),
                vertical: (14 * scale).clamp(10, 18).toDouble(),
              ),
              minimumSize: Size(0, (44 * scale).clamp(40, 52).toDouble()),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(100),
              ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(100),
              ),
            );

            Widget metricRow() {
              return Row(
                children: [
                  Expanded(
                    child: _metricCard(
                      minHeight: tileMinH,
                      pad: cardPad,
                      icon: Icons.water_drop_outlined,
                      label: t.humidity,
                      value: "${_humidity.toStringAsFixed(1)}%",
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _metricCard(
                      minHeight: tileMinH,
                      pad: cardPad,
                      icon: Icons.thermostat_outlined,
                      label: t.temperature,
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
                  Text(
                    t.targetMoistureContent,
                    style: tx(16, w: FontWeight.w700, c: context.brand),
                  ),
                  SizedBox(height: (10 * scale).clamp(6, 12).toDouble()),
                  Row(
                    children: [
                      Text(
                        "9%",
                        style: tx(
                          12,
                          w: FontWeight.w700,
                          c: cs.onSurface.withOpacity(0.7),
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: _targetMc,
                          min: 9.0,
                          max: 14.0,
                          divisions: 10,
                          label: "${_targetMc.toStringAsFixed(1)}%",
                          // Disabled while running or preheating
                          onChanged: inputsLocked
                              ? null
                              : (v) {
                                  setState(
                                    () => _targetMc = double.parse(
                                      v.toStringAsFixed(1),
                                    ),
                                  );
                                },
                        ),
                      ),
                      Text(
                        "14%",
                        style: tx(
                          12,
                          w: FontWeight.w700,
                          c: cs.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tip,
                    style: tx(
                      13,
                      w: FontWeight.w600,
                      c: cs.onSurface.withOpacity(0.85),
                    ),
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
                    // Disable taps while running or preheating
                    onTap: inputsLocked
                        ? null
                        : () => setState(() => _selectedBracket = b),
                    borderRadius: BorderRadius.circular(16),
                    child: Opacity(
                      opacity: inputsLocked ? 0.6 : 1.0,
                      child: Container(
                        padding: EdgeInsets.all(
                          (12 * scale).clamp(10, 18).toDouble(),
                        ),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: cs.outline.withOpacity(sel ? 0.0 : 1.0),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              b.title(t),
                              textAlign: TextAlign.center,
                              style: tx(
                                (18 * scale).clamp(16, 24).toDouble(),
                                w: FontWeight.w800,
                                c: fg,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              b.description(t),
                              textAlign: TextAlign.center,
                              style: tx(
                                (12 * scale).clamp(11, 15).toDouble(),
                                w: FontWeight.w600,
                                c: fg.withOpacity(0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.initialMoistureContent,
                    style: tx(16, w: FontWeight.w700, c: context.brand),
                  ),
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
                txt = t.completeInputsToEstimate;
              } else if (eta == null) {
                txt = t.estimating;
              } else if (eta <= 0) {
                txt = t.atOrBelowTarget;
              } else if (eta < 60) {
                txt = "~${eta.ceil()} ${t.minutesShort}";
              } else {
                final h = (eta / 60).floor();
                final m = (eta % 60).ceil();
                txt = "~${h}${t.hoursShort} ${m}${t.minutesShort}";
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
                  "${t.estimatedTime}: $txt",
                  style: tx(
                    (12 * scale).clamp(11, 15).toDouble(),
                    w: FontWeight.w700,
                    c: cs.onSecondaryContainer,
                  ),
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
                      // ───────── Restart-with-previous banner ─────────
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
                                      Text(
                                        t.startNewSession,
                                        style: tx(
                                          (16 * scale).clamp(14, 20).toDouble(),
                                          w: FontWeight.w700,
                                          c: context.brand,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        "${t.usePreviousSettings}:\n$_prevSettingText",
                                        style: tx(
                                          12,
                                          w: FontWeight.w600,
                                          c: cs.onSurface.withOpacity(0.8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton(
                                  style: startStyle,
                                  onPressed: _showStartWithPreviousDialog,
                                  child: Text(
                                    t.startSame,
                                    style: tx(
                                      14,
                                      w: FontWeight.w700,
                                      c: cs.onPrimary,
                                    ),
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
                              Text(
                                t.sessionPlan,
                                style: tx(
                                  (16 * scale).clamp(14, 20).toDouble(),
                                  w: FontWeight.w700,
                                  c: context.brand,
                                ),
                              ),
                              const SizedBox(height: 10),

                              // Slider disabled while running/preheating
                              AnimatedOpacity(
                                duration: const Duration(milliseconds: 200),
                                opacity: inputsLocked ? 0.6 : 1.0,
                                child: targetSlider(),
                              ),
                              const SizedBox(height: 14),

                              // Bracket buttons disabled while running/preheating
                              AnimatedOpacity(
                                duration: const Duration(milliseconds: 200),
                                opacity: inputsLocked ? 0.6 : 1.0,
                                child: initialSelector(),
                              ),
                              const SizedBox(height: 14),

                              etaBadge(),
                              const SizedBox(height: 14),
                              ElevatedButton(
                                style: startStyle,
                                onPressed:
                                    (_inputsComplete &&
                                        !_isRunning &&
                                        !_waitingForPreheat)
                                    ? () async {
                                        final ok =
                                            await _ensureBluetoothReadyOrExplain();
                                        if (!ok) return;

                                        await _sendInitToDevice();
                                        await _startPreheatDialog();
                                      }
                                    : null,
                                child: Text(
                                  t.start,
                                  style: tx(
                                    14,
                                    w: FontWeight.w700,
                                    c: cs.onPrimary,
                                  ),
                                ),
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
                                    t.sessionTimer,
                                    style: tx(
                                      (16 * scale).clamp(14, 20).toDouble(),
                                      w: FontWeight.w700,
                                      c: context.brand,
                                    ),
                                  ),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: (10 * scale)
                                          .clamp(8, 14)
                                          .toDouble(),
                                      vertical: (6 * scale)
                                          .clamp(4, 10)
                                          .toDouble(),
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
                                          ? (_isPaused ? t.paused : t.running)
                                          : (_waitingForPreheat
                                                ? t.initializing
                                                : t.idle),
                                      style: tx(
                                        (12 * scale).clamp(11, 15).toDouble(),
                                        w: FontWeight.w700,
                                        c: _isRunning
                                            ? (_isPaused
                                                  ? Colors.amber.shade900
                                                  : cs.onSecondaryContainer)
                                            : cs.onSurface.withOpacity(0.8),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              LayoutBuilder(
                                builder: (_, __) {
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
                                                    color: dotColor.withOpacity(
                                                      0.45,
                                                    ),
                                                    blurRadius: (10 * scale)
                                                        .clamp(6, 14)
                                                        .toDouble(),
                                                    spreadRadius: (2 * scale)
                                                        .clamp(1, 3)
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
                                              style: tx(
                                                bigText,
                                                w: FontWeight.w800,
                                              ),
                                            ),
                                            SizedBox(
                                              height: (6 * scale)
                                                  .clamp(4, 10)
                                                  .toDouble(),
                                            ),
                                            Text(
                                              "${t.toTarget(_targetMc.toStringAsFixed(1))}",
                                              style: tx(
                                                (14 * scale)
                                                    .clamp(12, 18)
                                                    .toDouble(),
                                                w: FontWeight.w600,
                                                c: cs.onSurface.withOpacity(
                                                  0.8,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),

                              SizedBox(
                                height: (16 * scale).clamp(12, 22).toDouble(),
                              ),
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
                                        _isPaused ? t.play : t.pause,
                                        style: tx(
                                          14,
                                          w: FontWeight.w700,
                                          c: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton(
                                      style: stopStyle,
                                      onPressed:
                                          _isRunning ||
                                              _waitingForPreheat ||
                                              _isPaused
                                          ? () async {
                                              final cs = Theme.of(
                                                context,
                                              ).colorScheme;
                                              await showDialog(
                                                context: context,
                                                builder: (ctx) => AlertDialog(
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          16,
                                                        ),
                                                  ),
                                                  title: Text(
                                                    t.stopSession,
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: cs.onSurface,
                                                    ),
                                                  ),
                                                  content: Text(
                                                    t.stopSessionBody,
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 14,
                                                      color: cs.onSurface
                                                          .withOpacity(0.85),
                                                    ),
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(ctx),
                                                      child: Text(
                                                        t.cancel,
                                                        style:
                                                            GoogleFonts.poppins(
                                                              fontSize: 14,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color:
                                                                  context.brand,
                                                            ),
                                                      ),
                                                    ),
                                                    ElevatedButton(
                                                      onPressed: () {
                                                        Navigator.pop(ctx);
                                                        if (_waitingForPreheat) {
                                                          _waitingForPreheat =
                                                              false;
                                                          _preheatReady = false;
                                                        }
                                                        _sendCommand(
                                                          "MOVE_SERVOS_TO_STOP_POSITION",
                                                        );
                                                        _finishSession(); // manual stop saves + popup
                                                      },
                                                      child: Text(
                                                        t.confirm,
                                                        style:
                                                            GoogleFonts.poppins(
                                                              fontSize: 14,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              color:
                                                                  cs.onPrimary,
                                                            ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }
                                          : null,
                                      child: Text(
                                        t.stop,
                                        style: tx(
                                          14,
                                          w: FontWeight.w700,
                                          c: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(
                                height: (16 * scale).clamp(12, 22).toDouble(),
                              ),
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
        textBuilder:
            ({
              double? size,
              FontWeight? weight,
              Color color = const Color(0x00000000),
              double? height,
              TextDecoration? deco,
            }) {
              final effective = color == const Color(0x00000000)
                  ? cs.onSurface
                  : color;
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
  })
  textBuilder;

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
          Icon(
            icon,
            color: cs.primary,
            size: (18 * scale).clamp(16, 22).toDouble(),
          ),
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
