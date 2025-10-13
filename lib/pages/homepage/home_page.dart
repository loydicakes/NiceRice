// lib/pages/homepage/home_page.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:nice_rice/header.dart';
import 'package:nice_rice/theme_controller.dart';
import 'package:nice_rice/pages/automation/automation.dart';

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

    // Poll environment sensor every 3s
    _sensorTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      _sendCommand("GET_DHT");      // expects: DHT:H=xx.x,T=yy.y
      _sendCommand("GET_STATUS");   // reserve for storage status later
      _sendCommand("GET_BAT");      // reserve for battery percent later
      // TODO: once EMC math is ready, request/compute and set _estMc
      // setState(() => _estMc = <computed value>);
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
    if (call.method == "onDataReceived") {
      final String data = call.arguments.toString().trim();
      _parseBleResponse(data);
    }
  }

  void _parseBleResponse(String rawData) {
    final lines = rawData.split(RegExp(r'[\r\n]+'));
    for (final line in lines) {
      final data = line.trim();
      if (data.isEmpty) continue;

      // DHT parser: "DHT:H=38.2,T=27.5"
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

      // Storage status placeholder (shape TBD). Example: "STATUS:Safe"
      if (data.startsWith("STATUS:")) {
        final txt = data.replaceFirst("STATUS:", "").trim();
        setState(() {
          _storageStatus = txt; // may still be "", which is fine for now
        });
        continue;
      }

      // Battery parser (shape TBD). Example: "BAT:76"
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
    if (!Platform.isAndroid) {
      _toast('Bluetooth flow is Android-only in this build.');
      return;
    }
    if (_isConnecting) return;

    setState(() => _isConnecting = true);
    try {
      final ok = await _bleChannel.invokeMethod<bool>('ensureBluetoothOn') ?? false;
      if (!ok) {
        _toast('Bluetooth is still OFF.');
        return;
      }

      final bonded = await _bleChannel.invokeMethod<List<dynamic>>('listBondedDevices') ?? [];
      final discovered = await _bleChannel.invokeMethod<List<dynamic>>('discoverDevices') ?? [];

      final devices = _mergeDevices(bonded, discovered);
      if (devices.isEmpty) {
        _toast('No devices found nearby.');
        return;
      }
      _showDevicePicker(devices);
    } on PlatformException catch (e) {
      _toast('Bluetooth error: ${e.message ?? e.code}');
    } catch (e) {
      _toast('Unexpected error: $e');
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
              Text("Select a device", style: _textStyle(context, size: 18, weight: FontWeight.w700)),
              const SizedBox(height: 4),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: devices.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final d = devices[i];
                    final name = (d["name"] ?? "").isEmpty ? "(Unnamed)" : d["name"]!;
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

                          _toast(ok ? 'Connected to $name ($addr)' : 'Failed to connect to $name');
                        } on PlatformException catch (e) {
                          _toast('Connect error: ${e.message ?? e.code}');
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

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = ThemeScope.of(context);
    final now = DateTime.now();

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
                                  Expanded(
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
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(minWidth: 120),
                                            child: ElevatedButton(
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
                                                    Text(
                                                      "Connect",
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
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // ── Device Battery card ──────────────────────────────
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                          child: Row(
                            children: [
                              Text(
                                "Device Battery",
                                style: _textStyle(context,
                                    size: (15 * scale).clamp(13, 18).toDouble(),
                                    weight: FontWeight.w700,
                                    color: context.brand),
                              ),
                              const Spacer(),
                              _BatteryBadge(percent: _batteryPct, scale: scale),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // ── Drying Chamber (progress mirrors Automation timer) ─
                      ValueListenableBuilder<double>(
                        valueListenable: AutomationPage.progress,
                        builder: (_, prog, __) {
                          final pct = (prog * 100).clamp(0, 100);
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
                                        "Drying Chamber",
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
                                      value: prog, // 0.0–1.0 from Automation page
                                      minHeight: (10 * scale).clamp(8, 14).toDouble(),
                                      backgroundColor: context.progressTrack,
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
                                "Storage Chamber",
                                style: _textStyle(
                                  context,
                                  size: (16 * scale).clamp(14, 20).toDouble(),
                                  weight: FontWeight.w700,
                                  color: context.brand,
                                ),
                              ),
                              const SizedBox(height: 12),

                              // 2x2 grid on phones, 4 in a row on wide screens
                              LayoutBuilder(builder: (ctx, box) {
                                final isWide = box.maxWidth >= 520;
                                return GridView.count(
                                  crossAxisCount: isWide ? 4 : 2,
                                  childAspectRatio: 1.05, // a touch taller tiles for safety
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  children: [
                                    _MiniMetricTile(
                                      icon: Icons.thermostat_outlined,
                                      label: "Temp",
                                      value: "${_tempC.toStringAsFixed(0)}ºC",
                                    ),
                                    _MiniMetricTile(
                                      icon: Icons.water_drop_outlined,
                                      label: "Humidity",
                                      value: "${_humidity.toStringAsFixed(0)}%",
                                    ),
                                    _MiniMetricTile(
                                      icon: Icons.eco_outlined,
                                      label: "Moisture",
                                      value: _estMc == null
                                          ? "--%"
                                          : "${_estMc!.toStringAsFixed(0)}%",
                                    ),
                                    _MiniStatusTile(
                                      statusText: _storageStatus, // may be ""
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

/// Responsive metric tile: sizes content RELATIVE to the tile,
/// guarantees no overflow and keeps padding minimal.
class _MiniMetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final double scale; // kept for API compatibility, not used for sizing

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
        // Size text based on the tile's own box to avoid overflow
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

/// Responsive status tile with the same no-overflow behavior.
class _MiniStatusTile extends StatelessWidget {
  final String statusText; // may be blank for now
  final double scale;      // kept for API compatibility, not used for sizing

  const _MiniStatusTile({
    required this.statusText,
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

        final isSafe = statusText.toLowerCase().contains("safe");
        final Color statusColor = isSafe ? const Color(0xFF1DB954) : cs.onSurface;

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
                  "Status",
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
