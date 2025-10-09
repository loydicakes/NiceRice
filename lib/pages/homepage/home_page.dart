// lib/pages/homepage/home_page.dart
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:nice_rice/header.dart';
import 'package:nice_rice/theme_controller.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // Fake sensor stream
  final _rand = Random();
  Timer? _sensorTimer;
  Timer? _clockTimer;

  // live values
  double _tempC = 60;
  double _humidity = 38;
  double _moisture = 15;

  // rolling history
  final List<double> _moistureHistory = [];
  static const int _historyCap = 24;

  // platform channel (no plugins, no gradle changes)
  static const MethodChannel _bleChannel =
  MethodChannel('app.bluetooth/controls');

  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();

    // Register Bluetooth data handler
    _bleChannel.setMethodCallHandler(_handleBluetoothData);
    for (int i = 0; i < 6; i++) {
      final m = 13 + _rand.nextInt(6).toDouble();
      _moistureHistory.add(m);
    }

    _sensorTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      _sendCommand("GET_DHT");

      _moisture = 13 + _rand.nextInt(6).toDouble();
    });


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

  // Domain helpers
  String _statusText(double m) {
    if (m >= 13 && m <= 14) return "Safe";
    if (m >= 15 && m <= 16) return "Warning";
    if (m >= 17 && m <= 18) return "At risk";
    return m < 13 ? "Safe" : "At risk";
  }

  Color _statusColor(String s) {
    switch (s) {
      case "Safe":
        return const Color(0xFF46cc0d);
      case "Warning":
        return const Color(0xFFF9A825);
      default:
        return const Color(0xFFC62828);
    }
  }

  double get _change {
    if (_moistureHistory.length < 2) return 0;
    return _moistureHistory.last - _moistureHistory.first;
  }

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

  Future<void> _sendCommand(String command) async {
    try {
      final response = await _bleChannel.invokeMethod<String>('sendData', {'data': command});
      if (response != null) {
        print("📨 Got response: $response");
        _parseDhtResponse(response);
      } else {
        print("⚠️ No response from ESP32");
      }
    } catch (e) {
      print("❌ Bluetooth error: $e");
    }
  }

  Future<void> _handleBluetoothData(MethodCall call) async {
    if (call.method == "onDataReceived") {
      final String data = call.arguments.toString().trim();
      print("📩 Native pushed: $data");
      _parseDhtResponse(data);
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
            _humidity = h!;
            _tempC = t!;
          });
          print("🟢 Updated HomePage → H: $_humidity%, T: $_tempC°C");
        } else {
          print("⚠️ Could not parse H/T");
        }
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
      // Fetch bonded first (fast), then do a short discovery and merge results.
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
    // Expect each item: { "name": "...", "address": "XX:XX:..." }
    final Map<String, Map<String, String>> byAddr = {};
    for (final src in [a, b]) {
      for (final it in src) {
        if (it is Map) {
          final addr = (it['address'] ?? '').toString();
          if (addr.isEmpty) continue;
          final name = (it['name'] ?? '').toString();
          byAddr.putIfAbsent(addr, () => {"name": name, "address": addr});
          // prefer non-empty names
          if ((byAddr[addr]!["name"] ?? "").isEmpty && name.isNotEmpty) {
            byAddr[addr]!["name"] = name;
          }
        }
      }
    }
    // sort: named first, then by name
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
                            'type': 'spp',       // <-- SPP for your ESP32 BluetoothSerial
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
            final bool isCompact = maxW < 420;
            final bool isTablet = maxW >= 700;
            final scale = _scaleForWidth(maxW);
            final double contentMaxWidth = isTablet ? 800.0 : 600.0;

            final status = _statusText(_moisture);
            final statusColor = _statusColor(status);

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentMaxWidth),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Header card
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

                      // Drying Chamber
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    "Drying Chamber",
                                    style: _textStyle(context, size: (15 * scale).clamp(13, 18).toDouble(), weight: FontWeight.w700, color: context.brand),
                                  ),
                                  const Spacer(),
                                  Text("%", style: _textStyle(context, size: (13 * scale).clamp(11, 16).toDouble(), weight: FontWeight.w600)),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: LinearProgressIndicator(
                                  value: 0.0,
                                  minHeight: (10 * scale).clamp(8, 14).toDouble(),
                                  backgroundColor: context.progressTrack,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Storage Chamber
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  "Storage Chamber",
                                  style: _textStyle(context, size: (16 * scale).clamp(14, 20).toDouble(), weight: FontWeight.w700, color: context.brand),
                                ),
                              ),
                              const SizedBox(height: 12),
                              GridView(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: isTablet ? 3 : 2,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: isTablet ? 1.18 : (isCompact ? 0.95 : 1.05),
                                ),
                                children: [
                                  _MetricTile(icon: Icons.thermostat_outlined, label: "Temperature", value: "${_tempC.toStringAsFixed(0)}ºC", scale: scale),
                                  _MetricTile(icon: Icons.water_drop_outlined, label: "Humidity", value: "${_humidity.toStringAsFixed(0)}%", scale: scale),
                                  _MetricTile(icon: Icons.eco_outlined, label: "Moisture Content", value: "${_moisture.toStringAsFixed(1)}%", scale: scale),
                                  _StatusTile(status: status, color: statusColor, scale: scale),
                                ],
                              ),
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

// Tiles (unchanged)

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final double scale;

  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    this.scale = 1,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: context.tileFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.tileStroke),
      ),
      padding: EdgeInsets.all((14 * scale).clamp(10, 18).toDouble()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: context.brand, size: (18 * scale).clamp(16, 22).toDouble()),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: (28 * scale).clamp(22, 34).toDouble(),
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: (13 * scale).clamp(11, 16).toDouble(),
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  final String status;
  final Color color;
  final double scale;

  const _StatusTile({
    required this.status,
    required this.color,
    this.scale = 1,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: context.tileFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.tileStroke),
      ),
      padding: EdgeInsets.all((14 * scale).clamp(10, 18).toDouble()),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Icon(Icons.storage_outlined, color: color, size: (18 * scale).clamp(16, 22).toDouble()),
          ),
          const SizedBox(height: 8),
          Text(
            status,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: (20 * scale).clamp(16, 26).toDouble(),
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Storage Status",
            style: GoogleFonts.poppins(
              fontSize: (13 * scale).clamp(11, 16).toDouble(),
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
