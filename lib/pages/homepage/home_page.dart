  // lib/pages/homepage/home_page.dart
  import 'dart:async';
  import 'dart:io';
  import 'package:flutter/material.dart';
  import 'package:flutter/services.dart';
  import 'package:google_fonts/google_fonts.dart';
  
  import 'package:nice_rice/header.dart';
  import 'package:nice_rice/theme_controller.dart';
  import 'package:nice_rice/pages/automation/automation.dart';
  
  // ⬇️ Use the generated localizations
  import 'package:nice_rice/l10n/app_localizations.dart';
  
  class HomePage extends StatefulWidget {
    const HomePage({super.key});
  
    @override
    State<HomePage> createState() => _HomePageState();
  }
  
  class _HomePageState extends State<HomePage> with AutomaticKeepAliveClientMixin {
    @override
    bool get wantKeepAlive => true;
  
    // Timers
    Timer? _sensorTimer;
    Timer? _clockTimer;
  
    // ✅ Connection watchdog (from previous step)
    Timer? _connWatchTimer;
    DateTime? _lastBleRxAt;
    static const Duration _disconnectGrace = Duration(seconds: 10);
    static const Duration _connWatchTick = Duration(seconds: 2);
  
    // Live sensor values (DHT)
    double _tempC = 0;
    double _humidity = 0;
  
    // Estimated Moisture Content (placeholder until we finalize EMC logic)
    double? _estMc; // null means "not computed yet"
  
    // Storage status
    String _storageStatus = ""; // intentionally blank for now
  
    // Battery percentage (placeholder for now)
    int _batteryPct = 76;
  
    // Platform channel (no plugins, no gradle changes)
    static const MethodChannel _bleChannel = MethodChannel('app.bluetooth/controls');
  
    bool _isConnecting = false;
  
    // NEW: track connection state so we can flip the button to "Disconnect"
    bool _isConnected = false;
    String? _connectedName;
    String? _connectedAddr;
  
    IconData _batteryIcon(int percent) {
      if (percent >= 80) return Icons.battery_full_rounded;
      if (percent >= 60) return Icons.battery_6_bar_rounded;
      if (percent >= 40) return Icons.battery_4_bar_rounded;
      if (percent >= 20) return Icons.battery_2_bar_rounded;
      return Icons.battery_alert_rounded;
    }
  
    @override
    void initState() {
      super.initState();
  
      // Register Bluetooth data handler
      _bleChannel.setMethodCallHandler(_handleBluetoothData);
  
      // Start watchdog
      _connWatchTimer = Timer.periodic(_connWatchTick, (_) {
        if (!_isConnected) return;
        final last = _lastBleRxAt;
        if (last == null) return;
        final silentFor = DateTime.now().difference(last);
        if (silentFor > _disconnectGrace) {
          _handleConnectionLost();
        }
      });
  
      // Poll environment sensor every 3s
      _sensorTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (!mounted) return;
        _sendCommand("GET_DHT2");
        _sendCommand("GET_STATUS");
        _sendCommand("GET_BAT");
        // TODO: compute _estMc when math is ready
      });
  
      // Tick clock (for the header date/time)
      _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  
    @override
    void dispose() {
      _sensorTimer?.cancel();
      _clockTimer?.cancel();
      _connWatchTimer?.cancel();
      super.dispose();
    }
  
    // Formatting helpers
    String _formatDate(DateTime dt) {
      const months = [
        'January','February','March','April','May','June',
        'July','August','September','October','November','December',
      ];
      return "${months[dt.month - 1]} ${dt.day}, ${dt.year}";
    }
  
    String _formatTime(DateTime dt) {
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? "PM" : "AM";
      return "$h:$m $ampm";
    }
  
    TextStyle _textStyle(
      BuildContext context, {
      double? size,
      FontWeight? weight,
      Color? color,
      double? height,
    }) =>
        GoogleFonts.poppins(
          fontSize: size,
          fontWeight: weight,
          color: color ?? Theme.of(context).colorScheme.onSurface,
          height: height,
        );
  
    double _scaleForWidth(double width) => (width / 375).clamp(0.85, 1.25).toDouble();
  
    // ─── BLE: send + parse ─────────────────────────────────────────────────────
    Future<void> _sendCommand(String command) async {
      try {
        final response = await _bleChannel.invokeMethod<String>('sendData', {'data': command});
        if (response != null) {
          _parseBleResponse(response);
        }
      } catch (e) {
        debugPrint("❌ Bluetooth error: $e");
      }
    }
  
    Future<void> _handleBluetoothData(MethodCall call) async {
      final t = AppLocalizations.of(context)!;
      if (call.method == "onDataReceived") {
        final String data = call.arguments.toString().trim();
        _parseBleResponse(data);
      } else if (call.method == "onDisconnected") {
        _handleConnectionLost();
        _toast(t.deviceDisconnected);
      }
    }
  
    void _handleConnectionLost() {
      if (!mounted) return;
      setState(() {
        _isConnected = false;
        _connectedName = null;
        _connectedAddr = null;
      });
      AutomationPage.btConnected.value = false;
      AutomationPage.btDeviceName.value = null;
      _toast("Bluetooth connection lost");
    }
  
    void _parseBleResponse(String rawData) {
      _lastBleRxAt = DateTime.now();
  
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
              _tempC = t!;
            });
          }
          continue;
        }
  
        if (data.startsWith("STATUS:")) {
          final txt = data.replaceFirst("STATUS:", "").trim();
          setState(() {
            _storageStatus = txt;
          });
          continue;
        }
  
        if (data.startsWith("BAT:")) {
          final v = int.tryParse(data.replaceFirst("BAT:", "").trim());
          if (v != null) {
            setState(() => _batteryPct = v.clamp(0, 100));
          }
          continue;
        }
      }
    }
  
    // ─── Connect + device picker (Android only) ────────────────────────────────
    Future<void> _onConnectPressed() async {
      final t = AppLocalizations.of(context)!;
  
      if (!Platform.isAndroid) {
        _toast(t.bluetoothAndroidOnly);
        return;
      }
      if (_isConnecting) return;
  
      setState(() => _isConnecting = true);
      try {
        final ok = await _bleChannel.invokeMethod<bool>('ensureBluetoothOn') ?? false;
        if (!ok) {
          _toast(t.bluetoothStillOff);
          return;
        }
  
        final bonded = await _bleChannel.invokeMethod<List<dynamic>>('listBondedDevices') ?? [];
        final discovered = await _bleChannel.invokeMethod<List<dynamic>>('discoverDevices') ?? [];
  
        final devices = _mergeDevices(bonded, discovered);
        if (devices.isEmpty) {
          _toast(t.noDevicesFound);
          return;
        }
        _showDevicePicker(devices);
      } on PlatformException catch (e) {
        _toast(t.bluetoothError(e.message ?? e.code));
      } catch (e) {
        _toast(t.unexpectedError(e.toString()));
      } finally {
        if (mounted) setState(() => _isConnecting = false);
      }
    }
  
    List<Map<String, String>> _mergeDevices(List<dynamic> a, List<dynamic> b) {
      final Map<String, Map<String, String>> byAddr = {};
      for (final src in [a, b]) {
        for (final it in src) {
          if (it is Map) {
            final addr = (it['address'] ?? '').toString();
            if (addr.isEmpty) continue;
            final name = (it['name'] ?? '').toString();
            byAddr.putIfAbsent(addr, () => {"name": name, "address": addr});
            if ((byAddr[addr]!["name"] ?? "").isEmpty && name.isNotEmpty) {
              byAddr[addr]!["name"] = name;
            }
          }
        }
      }
      final list = byAddr.values.toList();
      list.sort((x, y) {
        final xn = (x["name"] ?? "").isEmpty ? "zzzz" : x["name"]!;
        final yn = (y["name"] ?? "").isEmpty ? "zzzz" : y["name"]!;
        return xn.toLowerCase().compareTo(yn.toLowerCase());
      });
      return list;
    }
  
    void _showDevicePicker(List<Map<String, String>> devices) {
      final t = AppLocalizations.of(context)!;
  
      showModalBottomSheet(
        context: context,
        isScrollControlled: false,
        showDragHandle: true,
        builder: (ctx) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Text(t.selectDevice, style: _textStyle(context, size: 18, weight: FontWeight.w700)),
                const SizedBox(height: 4),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: devices.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final d = devices[i];
                      final name = (d["name"] ?? "").isEmpty ? t.unnamedDevice : d["name"]!;
                      final addr = d["address"] ?? "";
                      return ListTile(
                        leading: const Icon(Icons.bluetooth),
                        title: Text(name, style: _textStyle(context, size: 16, weight: FontWeight.w600)),
                        subtitle: Text(addr, style: _textStyle(context, size: 12, weight: FontWeight.w400, color: Colors.grey[600])),
                        onTap: () async {
                          Navigator.pop(context);
                          try {
                            setState(() => _isConnecting = true);
                            final ok = await _bleChannel.invokeMethod<bool>('connect', {
                              'address': addr,
                              'type': 'spp',
                              'timeoutMs': 15000,
                            }) ?? false;
  
                            if (ok) {
                              if (!mounted) return;
                              setState(() {
                                _isConnected = true;
                                _connectedName = name;
                                _connectedAddr = addr;
                                _lastBleRxAt = DateTime.now();
                              });
                              AutomationPage.btConnected.value = true;
                              AutomationPage.btDeviceName.value = name;
                            }
                            _toast(ok ? t.connectedTo(name, addr) : t.failedToConnect(name));
                          } on PlatformException catch (e) {
                            _toast(t.connectError(e.message ?? e.code));
                          } finally {
                            if (mounted) setState(() => _isConnecting = false);
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
  
    Future<void> _onDisconnectPressed() async {
      final t = AppLocalizations.of(context)!;
      final confirm = await _showDisconnectConfirmDialog();
      if (confirm != true) return;
  
      try {
        await _bleChannel.invokeMethod('disconnect');
      } catch (e) {
        debugPrint("❌ Disconnect error: $e");
      } finally {
        if (!mounted) return;
        setState(() {
          _isConnected = false;
          _connectedName = null;
          _connectedAddr = null;
        });
        AutomationPage.btConnected.value = false;
        AutomationPage.btDeviceName.value = null;
        _toast(t.disconnected);
      }
    }
  
    Future<bool?> _showDisconnectConfirmDialog() {
      final t = AppLocalizations.of(context)!;
      return showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) {
          final cs = Theme.of(ctx).colorScheme;
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t.disconnectTitle,
                    style: _textStyle(ctx, size: 20, weight: FontWeight.w800, color: cs.onSurface),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    t.disconnectBody,
                    textAlign: TextAlign.center,
                    style: _textStyle(ctx, size: 14, weight: FontWeight.w400, color: cs.onSurface.withOpacity(0.9)),
                  ),
                  const SizedBox(height: 18),
  
                  // ✅ Buttons: right-aligned, side-by-side, consistent spacing
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: cs.onSurface,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                          ),
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(t.cancel),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                          ),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(t.confirm),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
  
    void _toast(String msg) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  
    @override
    Widget build(BuildContext context) {
      super.build(context);
      final theme = ThemeScope.of(context);
      final now = DateTime.now();
      final t = AppLocalizations.of(context)!;
  
      final Color paleRed = const Color(0xFFF28B82);
      final Color paleRedBorder = const Color(0xFFF28B82);
      final Color paleRedText = const Color(0xFFD93025);
  
      return Scaffold(
        appBar: PageHeader(
          isDarkMode: theme.isDark,
          onThemeChanged: theme.setDark,
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth;
              final bool isTablet = maxW >= 700;
              final scale = _scaleForWidth(maxW);
              final double contentMaxWidth = isTablet ? 800.0 : 600.0;
  
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentMaxWidth),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // ── Header card ──────────────────────────────────────
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: LayoutBuilder(
                              builder: (ctx, box) {
                                final double imgW = (box.maxWidth * 0.28).clamp(92.0, 160.0).toDouble();
                                final double imgH = (imgW * 1.25).clamp(110.0, 200.0).toDouble();
  
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: imgW,
                                      height: imgH,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: Image.asset("assets/images/pon.png", fit: BoxFit.cover),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
  
                                    // MOVED: Stick the date/time/button block to the RIGHT
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.only(left: 40),
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: ConstrainedBox(
                                            constraints: BoxConstraints(
                                              maxWidth: (box.maxWidth * 0.6).clamp(220, 480),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  _formatDate(now),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: _textStyle(
                                                    context,
                                                    size: (18 * _scaleForWidth(box.maxWidth)).clamp(14, 22).toDouble(),
                                                    weight: FontWeight.w700,
                                                    color: context.brand,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  _formatTime(now),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: _textStyle(
                                                    context,
                                                    size: (14 * _scaleForWidth(box.maxWidth)).clamp(12, 18).toDouble(),
                                                    weight: FontWeight.w400,
                                                  ),
                                                ),
                                                const SizedBox(height: 10),
  
                                                // CONNECT / DISCONNECT BUTTON
                                                Align(
                                                  alignment: Alignment.centerLeft,
                                                  child: ConstrainedBox(
                                                    constraints: const BoxConstraints(minWidth: 140),
                                                    child: _isConnected
                                                        ? OutlinedButton(
                                                            style: OutlinedButton.styleFrom(
                                                              side: BorderSide(color: paleRedBorder, width: 1.6),
                                                              backgroundColor: Colors.white,
                                                              foregroundColor: paleRedText,
                                                              shape: RoundedRectangleBorder(
                                                                borderRadius: BorderRadius.circular(100),
                                                              ),
                                                              padding: EdgeInsets.symmetric(
                                                                horizontal: 20,
                                                                vertical: (12 * _scaleForWidth(box.maxWidth)).clamp(8, 16).toDouble(),
                                                              ),
                                                            ),
                                                            onPressed: _onDisconnectPressed,
                                                            child: FittedBox(
                                                              fit: BoxFit.scaleDown,
                                                              child: Row(
                                                                mainAxisSize: MainAxisSize.min,
                                                                children: [
                                                                  const Icon(Icons.link_off, size: 18),
                                                                  const SizedBox(width: 8),
                                                                  Text(
                                                                    t.disconnect,
                                                                    style: _textStyle(
                                                                      context,
                                                                      size: (16 * _scaleForWidth(box.maxWidth)).clamp(13, 20).toDouble(),
                                                                      weight: FontWeight.w700,
                                                                      color: paleRedText,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          )
                                                        : ElevatedButton(
                                                            style: ElevatedButton.styleFrom(
                                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                                                              padding: EdgeInsets.symmetric(
                                                                horizontal: 20,
                                                                vertical: (12 * _scaleForWidth(box.maxWidth)).clamp(8, 16).toDouble(),
                                                              ),
                                                            ),
                                                            onPressed: _isConnecting ? null : _onConnectPressed,
                                                            child: FittedBox(
                                                              fit: BoxFit.scaleDown,
                                                              child: Row(
                                                                mainAxisSize: MainAxisSize.min,
                                                                children: [
                                                                  if (_isConnecting)
                                                                    Padding(
                                                                      padding: const EdgeInsets.only(right: 8.0),
                                                                      child: SizedBox(
                                                                        width: 16, height: 16,
                                                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                                                      ),
                                                                    ),
                                                                  const Icon(Icons.bluetooth, size: 18, color: Colors.white),
                                                                  const SizedBox(width: 8),
                                                                  Text(
                                                                    t.connect,
                                                                    style: _textStyle(
                                                                      context,
                                                                      size: (16 * _scaleForWidth(box.maxWidth)).clamp(13, 20).toDouble(),
                                                                      weight: FontWeight.w700,
                                                                      color: Colors.white,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                  ),
                                                ),
  
                                                if (_isConnected && (_connectedName?.isNotEmpty ?? false)) ...[
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    t.connectedLabel(_connectedName ?? ''),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: _textStyle(context, size: 12, color: Colors.grey[700]),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
  
                        const SizedBox(height: 14),
  
                        // ── Device Battery card (HIDDEN as requested; kept code intact)
                        // NOTE: We keep the original code but don't render it.
                        // If you want to re-enable later, set showBatteryCard=true.
                        Builder(builder: (_) {
                          const bool showBatteryCard = false; // ← requested change
                          if (!showBatteryCard) return const SizedBox.shrink();
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                              child: Row(
                                children: [
                                  Text(
                                    t.deviceBattery,
                                    style: _textStyle(context,
                                        size: (15 * _scaleForWidth(constraints.maxWidth)).clamp(13, 18).toDouble(),
                                        weight: FontWeight.w700,
                                        color: context.brand),
                                  ),
                                  const Spacer(),
                                  _BatteryBadge(percent: _batteryPct, scale: _scaleForWidth(constraints.maxWidth)),
                                ],
                              ),
                            ),
                          );
                        }),
  
                        // ── Drying Chamber progress
                        // Show ONLY when there is an active session.
                        const SizedBox(height: 14),
                        ValueListenableBuilder<bool>(
                          valueListenable: AutomationPage.isActive,
                          builder: (_, active, __) {
                            if (!active) return const SizedBox.shrink();
                            return ValueListenableBuilder<double>(
                              valueListenable: AutomationPage.progress,
                              builder: (_, prog, __) {
                                final pct = (prog * 100).clamp(0, 100);
                                final scale = _scaleForWidth(constraints.maxWidth);
                                return Card(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Text(
                                              t.dryingChamber,
                                              style: _textStyle(context,
                                                  size: (15 * scale).clamp(13, 18).toDouble(),
                                                  weight: FontWeight.w700,
                                                  color: context.brand),
                                            ),
                                            const Spacer(),
                                            Text(
                                              "${pct.toStringAsFixed(0)}%",
                                              style: _textStyle(context,
                                                  size: (14 * scale).clamp(12, 18).toDouble(),
                                                  weight: FontWeight.w800,
                                                  color: Theme.of(context).colorScheme.onSurface),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(20),
                                          child: LinearProgressIndicator(
                                            value: prog,
                                            minHeight: (10 * scale).clamp(8, 14).toDouble(),
                                            backgroundColor: context.progressTrack,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
  
                        const SizedBox(height: 14),
  
                        // ── Storage Chamber (4 tiles) ────────────────────────
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.storageChamber,
                                  style: _textStyle(
                                    context,
                                    size: (16 * _scaleForWidth(constraints.maxWidth)).clamp(14, 20).toDouble(),
                                    weight: FontWeight.w700,
                                    color: context.brand,
                                  ),
                                ),
                                const SizedBox(height: 12),
  
                                LayoutBuilder(builder: (ctx, box) {
                                  final isWide = box.maxWidth >= 520;
                                  return GridView.count(
                                    crossAxisCount: isWide ? 4 : 2,
                                    childAspectRatio: 1.05,
                                    mainAxisSpacing: 12,
                                    crossAxisSpacing: 12,
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    children: [
                                      _MiniMetricTile(
                                        icon: Icons.thermostat_outlined,
                                        label: t.temperatureShort,
                                        value: "${_tempC.toStringAsFixed(0)}ºC",
                                      ),
                                      _MiniMetricTile(
                                        icon: Icons.water_drop_outlined,
                                        label: t.humidity,
                                        value: "${_humidity.toStringAsFixed(0)}%",
                                      ),
                                      _MiniMetricTile(
                                        icon: Icons.eco_outlined,
                                        label: t.moisture,
                                        value: _estMc == null
                                            ? "--%"
                                            : "${_estMc!.toStringAsFixed(0)}%",
                                      ),
                                      _MiniStatusTile(
                                        statusText: _storageStatus,
                                        statusLabel: t.status,
                                      ),
                                    ],
                                  );
                                }),
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
  }
  
  // ───────────────────────────── Widgets ─────────────────────────────
  
  class _MiniMetricTile extends StatelessWidget {
    final IconData icon;
    final String label;
    final String value;
    final double scale;
  
    const _MiniMetricTile({
      required this.icon,
      required this.label,
      required this.value,
      this.scale = 1,
    });
  
    @override
    Widget build(BuildContext context) {
      final cs = Theme.of(context).colorScheme;
  
      return LayoutBuilder(
        builder: (context, c) {
          final shortest = c.biggest.shortestSide;
          final double iconSize  = (shortest * 0.18).clamp(16, 28).toDouble();
          final double valueSize = (shortest * 0.32).clamp(22, 52).toDouble();
          final double labelSize = (shortest * 0.14).clamp(11, 20).toDouble();
  
          return Container(
            decoration: BoxDecoration(
              color: context.tileFill,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.tileStroke),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  color: context.brand,
                  size: iconSize,
                ),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: GoogleFonts.poppins(
                      fontSize: valueSize,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                      height: 1.0,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: labelSize,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withOpacity(0.9),
                      height: 1.05,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
  }
  
  class _MiniStatusTile extends StatelessWidget {
    final String statusText;
    final String statusLabel;
    final double scale;
  
    const _MiniStatusTile({
      required this.statusText,
      required this.statusLabel,
      this.scale = 1,
    });
  
    @override
    Widget build(BuildContext context) {
      final cs = Theme.of(context).colorScheme;
  
      return LayoutBuilder(
        builder: (context, c) {
          final shortest = c.biggest.shortestSide;
          final double iconSize  = (shortest * 0.18).clamp(16, 28).toDouble();
          final double valueSize = (shortest * 0.32).clamp(22, 52).toDouble();
          final double labelSize = (shortest * 0.14).clamp(11, 20).toDouble();
  
          Color statusColor;
          if (statusText.toLowerCase().contains("at_risk")) {
            statusColor = const Color(0xFFD93025); // red
          } else if (statusText.toLowerCase().contains("warning")) {
            statusColor = const Color(0xFFF9A825); // yellow
          } else if (statusText.toLowerCase().contains("safe")) {
            statusColor = const Color(0xFF1DB954); // green
          } else {
            statusColor = cs.onSurface; // default gray
          }
  
          return Container(
            decoration: BoxDecoration(
              color: context.tileFill,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.tileStroke),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.storage_outlined, color: context.brand, size: iconSize),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    statusText.isEmpty ? "--" : statusText,
                    maxLines: 1,
                    style: GoogleFonts.poppins(
                      fontSize: valueSize,
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                      height: 1.0,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    statusLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: labelSize,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withOpacity(0.9),
                      height: 1.05,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
  }
  
  // ───────────────────────────── Battery Badge ─────────────────────────────
  
  class _BatteryBadge extends StatelessWidget {
    final int percent;
    final double scale;
  
    const _BatteryBadge({required this.percent, this.scale = 1});
  
    @override
    Widget build(BuildContext context) {
      final cs = Theme.of(context).colorScheme;
      IconData icon;
      if (percent >= 80) {
        icon = Icons.battery_full_rounded;
      } else if (percent >= 60) {
        icon = Icons.battery_6_bar_rounded;
      } else if (percent >= 40) {
        icon = Icons.battery_4_bar_rounded;
      } else if (percent >= 20) {
        icon = Icons.battery_2_bar_rounded;
      } else {
        icon = Icons.battery_alert_rounded;
      }
  
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: (10 * scale).clamp(8, 12).toDouble(),
          vertical: (6 * scale).clamp(4, 8).toDouble(),
        ),
        decoration: BoxDecoration(
          color: cs.surfaceVariant,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.outline.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: (16 * scale).clamp(14, 20).toDouble(), color: context.brand),
            const SizedBox(width: 6),
            Text(
              "$percent%",
              style: GoogleFonts.poppins(
                fontSize: (12 * scale).clamp(11, 14).toDouble(),
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      );
    }
  }
