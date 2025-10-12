// lib/pages/analytics/analytics.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:nice_rice/data/operation_models.dart';
import 'package:nice_rice/data/operation_history.dart';

import 'package:nice_rice/header.dart';
import 'package:nice_rice/theme_controller.dart'; // ThemeScope + BuildContext.brand

import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';


/// ------------ Analytics Page ------------
class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  String? _selectedOpId;
  late final OperationHistory repo;

  OperationRecord? _currentSelected(List<OperationRecord> ops) {
    if (ops.isEmpty) return null;
    final fallback = ops.first;
    return (_selectedOpId == null)
        ? fallback
        : repo.getById(_selectedOpId!) ?? fallback;
  }

  @override
  void initState() {
    super.initState();
    repo = OperationHistory.instance;
    repo.ensureLoaded(); // load local + watch cloud
  }

  double _scaleForWidth(double width) => (width / 375).clamp(0.85, 1.25);

  void _openExportSheet({
  required BuildContext context,
  required OperationRecord? current,
  required List<OperationRecord> all,
}) {
  final selectedIds = <String>{ if (current != null) current.id };
  bool pickSpecific = false;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSt) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16, right: 16,
              top: 12,
              bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Export Analytics PDF',
                    style: GoogleFonts.poppins(
                      fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('Choose which sessions to include.',
                    style: GoogleFonts.poppins(fontSize: 13)),
                const SizedBox(height: 12),

                // Options
                RadioListTile<bool>(
                  value: false,
                  groupValue: pickSpecific,
                  onChanged: (v) => setSt(() => pickSpecific = v ?? false),
                  title: const Text('Current session only'),
                ),
                RadioListTile<bool>(
                  value: true,
                  groupValue: pickSpecific,
                  onChanged: (v) => setSt(() => pickSpecific = v ?? true),
                  title: const Text('Select sessions…'),
                ),

                if (pickSpecific) ...[
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: all.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final op = all[i];
                        final checked = selectedIds.contains(op.id);
                        return CheckboxListTile(
                          dense: true,
                          value: checked,
                          title: Text(op.displayTitle,
                              overflow: TextOverflow.ellipsis),
                          onChanged: (v) {
                            setSt(() {
                              if (v == true) { selectedIds.add(op.id); }
                              else { selectedIds.remove(op.id); }
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],

                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      icon: const Icon(Icons.download),
                      label: const Text('Generate PDF'),
                      onPressed: () async {
                        final chosen = pickSpecific
                            ? all.where((o) => selectedIds.contains(o.id)).toList()
                            : (current == null ? <OperationRecord>[] : [current]);
                        if (chosen.isEmpty) return;
                        Navigator.pop(ctx); // close sheet
                        await _generatePdf(context, chosen);
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

Future<void> _generatePdf(BuildContext context, List<OperationRecord> sessions) async {
  final doc = pw.Document();

  for (final op in sessions) {
    doc.addPage(
      pw.Page(
        build: (pw.Context c) => pw.Padding(
          padding: const pw.EdgeInsets.all(24),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('NiceRice Session Report',
                  style: pw.TextStyle(
                      fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.Text(op.displayTitle,
                  style: const pw.TextStyle(fontSize: 12)),
              pw.SizedBox(height: 14),

              // Summary table
              _pdfSummary(op),

              pw.SizedBox(height: 16),
              pw.Text('Environment (if available)',
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold)),
              _pdfEnvStats(op),

              pw.SizedBox(height: 16),
              pw.Text('Notes',
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.Text(
                'Generated by NiceRice Analytics. This summary includes target, preset, intended use, duration, and basic statistics.',
                style: const pw.TextStyle(fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Present share/download dialog
  await Printing.sharePdf(
    bytes: await doc.save(),
    filename:
        'NiceRice_${DateTime.now().toIso8601String().replaceAll(":", "-")}.pdf',
  );
}

pw.Widget _pdfSummary(OperationRecord op) {
  // Read optional fields safely
  String target = '—';
  String preset = '—';
  String intended = '—';
  try {
    final d = (op as dynamic);
    final mc = d.targetMc as double?;
    if (mc != null) target = '${mc.toStringAsFixed(1)}%';
    preset = (d.presetLabel ?? d.preset ?? '—').toString();
    intended = (d.intendedUse ?? '—').toString();
  } catch (_) {}

  final dur = op.duration;
  final durText = dur == null
      ? '—'
      : '${dur.inHours}h ${dur.inMinutes.remainder(60)}m ${dur.inSeconds.remainder(60)}s';

  final estLoss = _estimateLossForPdf(op);

  return pw.Table(
    defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
    columnWidths: const {
      0: pw.FlexColumnWidth(2),
      1: pw.FlexColumnWidth(3),
    },
    children: [
      _row('Target Moisture Content', target),
      _row('Preset Selected', preset),
      _row('Intended Use', intended),
      _row('Estimated Moisture Loss', estLoss),
      _row('Started', DateFormat('MMM d, HH:mm:ss').format(op.startedAt)),
      _row('Ended', op.endedAt == null ? '—' : DateFormat('MMM d, HH:mm:ss').format(op.endedAt!)),
      _row('Duration (incl. init & cooldown)', durText),
    ],
  );
}

pw.TableRow _row(String k, String v) => pw.TableRow(
  children: [
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      child: pw.Text(k, style: const pw.TextStyle(fontSize: 11)),
    ),
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      child: pw.Text(v, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
    ),
  ],
);

String _estimateLossForPdf(OperationRecord op) {
  if (op.readings.isEmpty) return '~3–5% (est.)';
  final vals = op.readings.map((e) => e.value).toList();
  final loss = (vals.first - vals.last).abs();
  if (loss == 0) return '~3–5% (est.)';
  return '${loss.toStringAsFixed(1)}% (est.)';
}

pw.Widget _pdfEnvStats(OperationRecord op) {
  // A very light read of temp/RH if present (safe dynamic access)
  double? tAvg, tMin, tMax, hAvg, hMin, hMax;
  try {
    final temps = ((op as dynamic).temps ??
        (op as dynamic).temperatureReadings) as List<dynamic>?;
    if (temps != null && temps.isNotEmpty) {
      final tv = temps.map((e) => (e as dynamic).value as num).map((e) => e.toDouble()).toList();
      tAvg = tv.reduce((a, b) => a + b) / tv.length;
      tMin = tv.reduce((a, b) => a < b ? a : b);
      tMax = tv.reduce((a, b) => a > b ? a : b);
    }
  } catch (_) {}
  try {
    final rhs = ((op as dynamic).humidities ??
        (op as dynamic).humidityReadings) as List<dynamic>?;
    if (rhs != null && rhs.isNotEmpty) {
      final hv = rhs.map((e) => (e as dynamic).value as num).map((e) => e.toDouble()).toList();
      hAvg = hv.reduce((a, b) => a + b) / hv.length;
      hMin = hv.reduce((a, b) => a < b ? a : b);
      hMax = hv.reduce((a, b) => a > b ? a : b);
    }
  } catch (_) {}

  final rows = <pw.TableRow>[];
  if (tAvg != null) {
    rows.add(_row('Temperature (avg / range)',
        '${tAvg!.toStringAsFixed(1)}°C • ${(tMin ?? tAvg)!.toStringAsFixed(1)}–${(tMax ?? tAvg)!.toStringAsFixed(1)}°C'));
  }
  if (hAvg != null) {
    rows.add(_row('Humidity (avg / range)',
        '${hAvg!.toStringAsFixed(1)}% • ${(hMin ?? hAvg)!.toStringAsFixed(1)}–${(hMax ?? hAvg)!.toStringAsFixed(1)}%'));
  }
  if (rows.isEmpty) {
    rows.add(_row('Environment', 'No temperature/humidity data'));
  }
  return pw.Table(children: rows);
}

  @override
  Widget build(BuildContext context) {
    final themeScope = ThemeScope.of(context);

    return Scaffold(
      appBar: PageHeader(
        isDarkMode: themeScope.isDark,
        onThemeChanged: themeScope.setDark,
      ),
      
      floatingActionButton: (repo.operations.isEmpty)
    ? null
    : FloatingActionButton.extended(
        icon: const Icon(Icons.picture_as_pdf),
        label: const Text('Export PDF'),
        onPressed: () {
          _openExportSheet( 
            context: context,
            current: _currentSelected(repo.operations), // <— here
            all: repo.operations,
          );
        },
      ),

      body: SafeArea(
        child: ListenableBuilder(
          listenable: repo,
          builder: (context, _) {
            final cs = Theme.of(context).colorScheme;
            final ops = repo.operations;

            OperationRecord? selected;
            if (ops.isNotEmpty) {
              final fallback = ops.first;
              selected = (_selectedOpId == null)
                  ? fallback
                  : repo.getById(_selectedOpId!) ?? fallback;
            }

            TextStyle txt({
              double? size,
              FontWeight? w,
              Color? c,
              double? h,
              TextDecoration? d,
            }) =>
                GoogleFonts.poppins(
                  fontSize: size,
                  fontWeight: w,
                  color: c ?? cs.onSurface,
                  height: h,
                  decoration: d,
                );

            return LayoutBuilder(
              builder: (context, constraints) {
                final maxW = constraints.maxWidth;
                final isTablet = maxW >= 700;
                final scale = _scaleForWidth(maxW);
                final contentMaxWidth = isTablet ? 860.0 : 600.0;
                final emptyH = (180 * scale).clamp(140, 220);

                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: contentMaxWidth),
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (ops.isEmpty)
                          _EmptyState(
                            height: emptyH.toDouble(),
                            message:
                                'No completed operations yet.\nRun one in Automation to build history.',
                            textStyle: txt(
                              size: 14 * scale,
                              w: FontWeight.w500,
                              c: cs.onSurface.withOpacity(0.85),
                            ),
                          )
                        else ...[
                          // ───────── Operation picker ─────────
                          Card(
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: (12 * scale).clamp(10, 16),
                                vertical: (10 * scale).clamp(8, 14),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.history,
                                      size: (20 * scale).clamp(18, 24),
                                      color: context.brand),
                                  SizedBox(width: (10 * scale).clamp(8, 14)),
                                  Expanded(
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: (selected ?? ops.first).id,
                                        isExpanded: true,
                                        iconEnabledColor: context.brand,
                                        items: ops
                                            .map(
                                              (op) => DropdownMenuItem(
                                                value: op.id,
                                                child: Text(
                                                  op.displayTitle,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: txt(
                                                    size: (14 * scale)
                                                        .clamp(12, 18),
                                                    w: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (value) {
                                          if (value != null) {
                                            setState(() {
                                              _selectedOpId = value;
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 14),

                          // ───────── Stats tiles (based on selected.readings) ─────────
                          if (selected != null &&
                              selected.readings.isNotEmpty)
                            Card(
                              child: Padding(
                                padding:
                                    EdgeInsets.all((16 * scale).clamp(12, 22)),
                                child: _StatsRow(
                                  selected: selected!,
                                  scale: scale,
                                ),
                              ),
                            ),

                          const SizedBox(height: 14),

                          // ───────── Card 1: Environmental Chart ─────────
                          _SectionCard(
                            title: 'Temperature & Humidity Overview',
                            titleStyle: txt(
                              size: (16 * scale).clamp(14, 20),
                              w: FontWeight.w700,
                              c: context.brand,
                            ),
                            child: _EnvChart.fromOperation(
                              op: selected,
                              height: (isTablet ? 320.0 : 260.0) *
                                  (scale.clamp(0.9, 1.1)),
                              scale: scale,
                              empty: _EmptyState(
                                height: emptyH * 0.7,
                                message:
                                    'No temperature/humidity data for this session.',
                                textStyle: txt(
                                  size: (14 * scale).clamp(12, 18),
                                  w: FontWeight.w500,
                                  c: cs.onSurface.withOpacity(0.85),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // ───────── Info footer ─────────
                          if (selected != null) _InfoFooter(op: selected!),

                          const SizedBox(height: 12),

                          // ───────── Card 2: Interpretation (env-first) ─────────
                          _EnvInterpretationCard(
                            op: selected,
                            fallback: _InterpretationCard(
                              op: selected,
                              titleSize: (16 * scale).clamp(14, 20),
                              bulletGap: (4 * scale).clamp(3, 8),
                            ),
                            titleSize: (16 * scale).clamp(14, 20),
                            bulletGap: (4 * scale).clamp(3, 8),
                          ),

                          const SizedBox(height: 12),

                          // ───────── Card 3: Session Summary ─────────
                          _SessionSummaryCard(
                            op: selected!,
                            titleSize: (16 * scale).clamp(14, 20),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// ------------ UI helpers ------------
class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final TextStyle titleStyle;

  const _SectionCard({
    required this.title,
    required this.child,
    required this.titleStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: titleStyle),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  final TextStyle textStyle;
  final double? height;
  const _EmptyState({
    required this.message,
    required this.textStyle,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height ?? 180,
      child: Center(
        child: Text(message, textAlign: TextAlign.center, style: textStyle),
      ),
    );
  }
}

/// ------------ Top tiles (still using .readings so nothing breaks) ------------
class _StatsRow extends StatelessWidget {
  final OperationRecord selected;
  final double scale;

  const _StatsRow({
    required this.selected,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    TextStyle t({double? size, FontWeight? w}) => GoogleFonts.poppins(
      fontSize: size,
      fontWeight: w,
      color: cs.onSurface,
    );

    final vals = selected.readings.map((e) => e.value).toList();
    final avg = vals.reduce((a, b) => a + b) / vals.length;
    final minV = vals.reduce((a, b) => a < b ? a : b);
    final maxV = vals.reduce((a, b) => a > b ? a : b);

    Widget tile(String label, String value, IconData icon, double width) {
      return SizedBox(
        width: width, // fixed width -> always 3 across
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: cs.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outline.withOpacity(.7)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: cs.primary, size: 18),
              const SizedBox(height: 4),
              Text(
                value,
                style: t(size: 18, w: FontWeight.w800), // smaller headline
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(label, style: t(size: 11, w: FontWeight.w600)),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        // 12px gaps between tiles => 2 gaps for 3 tiles
        final gap = 12.0;
        final tileW = (c.maxWidth - gap * 2) / 3;
        return Row(
          children: [
            tile("Average", "${avg.toStringAsFixed(1)}%", Icons.timeline_outlined, tileW),
            SizedBox(width: gap),
            tile("Min", "${minV.toStringAsFixed(1)}%", Icons.trending_down_outlined, tileW),
            SizedBox(width: gap),
            tile("Max", "${maxV.toStringAsFixed(1)}%", Icons.trending_up_outlined, tileW),
          ],
        );
      },
    );
  }
}


/// ------------ Card 1: Temperature & Humidity Overview ------------
class _EnvChart extends StatelessWidget {
  final List<MoistureReading>? temps; // uses your existing reading type
  final List<MoistureReading>? rhs;   // uses your existing reading type
  final double? height;
  final double scale;
  final Widget? empty;

  const _EnvChart({
    required this.temps,
    required this.rhs,
    this.height,
    this.scale = 1.0,
    this.empty,
  });

  /// Safe helper that tries to access common field names dynamically
  factory _EnvChart.fromOperation({
    required OperationRecord? op,
    double? height,
    double scale = 1.0,
    Widget? empty,
  }) {
    List<MoistureReading>? tryGetList(dynamic dyn, String name) {
      try {
        final v = (dyn as dynamic)
            .noSuchMethod; // just to ensure dynamic; we don't call this.
      } catch (_) {}
      try {
        return (op as dynamic)?.temps as List<MoistureReading>?;
      } catch (_) {}
      try {
        return (op as dynamic)?.temperatureReadings
            as List<MoistureReading>?;
      } catch (_) {}
      return null;
    }

    List<MoistureReading>? temps;
    List<MoistureReading>? rhs;

    // attempt: temps
    try {
      temps = (op as dynamic).temps as List<MoistureReading>?;
    } catch (_) {
      try {
        temps = (op as dynamic).temperatureReadings
            as List<MoistureReading>?;
      } catch (_) {
        temps = null;
      }
    }
    // attempt: rh
    try {
      rhs = (op as dynamic).humidities as List<MoistureReading>?;
    } catch (_) {
      try {
        rhs = (op as dynamic).humidityReadings
            as List<MoistureReading>?;
      } catch (_) {
        rhs = null;
      }
    }

    return _EnvChart(
      temps: temps,
      rhs: rhs,
      height: height,
      scale: scale,
      empty: empty,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (temps == null || rhs == null || temps!.length < 2 || rhs!.length < 2) {
      return empty ??
          _EmptyState(
            message: 'No temperature/humidity data for this session.',
            textStyle: GoogleFonts.poppins(
              fontSize: 13,
              color: cs.onSurface.withOpacity(0.75),
              fontWeight: FontWeight.w500,
            ),
          );
    }

    // use earliest timestamp to align series
    final start =
        (temps!.first.t.isBefore(rhs!.first.t) ? temps!.first.t : rhs!.first.t);

    List<FlSpot> toSpots(List<MoistureReading> list) => list
        .map((r) =>
            FlSpot(r.t.difference(start).inSeconds.toDouble(), r.value))
        .toList();

    final tempSpots = toSpots(temps!);
    final rhSpots = toSpots(rhs!);

    double minY(Iterable<double> v) => v.reduce((a, b) => a < b ? a : b);
    double maxY(Iterable<double> v) => v.reduce((a, b) => a > b ? a : b);

    final allTempVals = temps!.map((e) => e.value);
    final allRhVals = rhs!.map((e) => e.value);

    // Separate axes
    final xMin = 0.0;
    final xMax = [
      tempSpots.isNotEmpty ? tempSpots.last.x : 0.0,
      rhSpots.isNotEmpty ? rhSpots.last.x : 0.0
    ].reduce((a, b) => a > b ? a : b);

    final tMin = (minY(allTempVals).floorToDouble());
    final tMax = (maxY(allTempVals).ceilToDouble());
    final hMin = (minY(allRhVals).floorToDouble());
    final hMax = (maxY(allRhVals).ceilToDouble());

    String xLabel(double x) =>
        DateFormat('HH:mm').format(start.add(Duration(seconds: x.round())));

    final gridColor = cs.onSurface.withOpacity(0.10);
    final borderColor = cs.outline.withOpacity(0.55);
    final labelColor = cs.onSurface.withOpacity(0.70);

    TextStyle t(double sz, [FontWeight? w]) =>
        GoogleFonts.poppins(fontSize: sz, fontWeight: w, color: labelColor);

    return SizedBox(
      height: height ?? 260,
      child: Stack(
        children: [
          // Temperature (left axis)
          LineChart(
            LineChartData(
              minX: xMin,
              maxX: xMax,
              minY: tMin,
              maxY: tMax,
              gridData: FlGridData(
                show: true,
                horizontalInterval:
                    ((tMax - tMin) / 4).clamp(1, 100).toDouble(),
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: gridColor, strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: (28 * scale).clamp(24, 36),
                    interval: (xMax - xMin) / 4.0,
                    getTitlesWidget: (v, m) => Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(xLabel(v),
                          style: t((11 * scale).clamp(10, 14))),
                    ),
                  ),
                ),
                leftTitles: AxisTitles(
                  axisNameWidget:
                      Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('°C', style: t(10))),
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: (36 * scale).clamp(28, 44),
                    interval: ((tMax - tMin) / 5).clamp(1, 100).toDouble(),
                    getTitlesWidget: (v, m) =>
                        Text(v.toStringAsFixed(0), style: t((11 * scale).clamp(10, 14))),
                  ),
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(color: borderColor),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: tempSpots,
                  isCurved: true,
                  barWidth: (3 * scale).clamp(2, 4),
                  color: Theme.of(context).colorScheme.primary,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withOpacity(0.18),
                  ),
                ),
              ],
            ),
          ),
          // Humidity (right axis overlay)
          Padding(
            padding: const EdgeInsets.only(right: 40.0), // visual room
            child: LineChart(
              LineChartData(
                minX: xMin,
                maxX: xMax,
                minY: hMin,
                maxY: hMax,
                gridData: FlGridData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(
                    axisNameWidget:
                        Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('% RH', style: t((10 * scale).clamp(9, 12)))),
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: (36 * scale).clamp(26, 44),
                      interval: ((hMax - hMin) / 5).clamp(1, 100).toDouble(),
                      getTitlesWidget: (v, m) =>
                          Text(v.toStringAsFixed(0), style: t((11 * scale).clamp(10, 14))),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: rhSpots,
                    isCurved: true,
                    barWidth: (3 * scale).clamp(2, 4),
                    color: Theme.of(context).colorScheme.secondary,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Theme.of(context)
                          .colorScheme
                          .secondary
                          .withOpacity(0.14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ------------ Card 2: Environment-first interpretation ------------
class _EnvInterpretationCard extends StatelessWidget {
  final OperationRecord? op;
  final Widget fallback; // your existing moisture interpretation card
  final double titleSize;
  final double bulletGap;

  const _EnvInterpretationCard({
    required this.op,
    required this.fallback,
    required this.titleSize,
    this.bulletGap = 4,
  });

  List<MoistureReading>? _tryTemps(dynamic d) {
    try {
      return (op as dynamic).temps as List<MoistureReading>?;
    } catch (_) {
      try {
        return (op as dynamic).temperatureReadings
            as List<MoistureReading>?;
      } catch (_) {
        return null;
      }
    }
  }

  List<MoistureReading>? _tryRhs(dynamic d) {
    try {
      return (op as dynamic).humidities as List<MoistureReading>?;
    } catch (_) {
      try {
        return (op as dynamic).humidityReadings
            as List<MoistureReading>?;
      } catch (_) {
        return null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (op == null) return fallback;

    final temps = _tryTemps(op);
    final rhs = _tryRhs(op);

    if (temps == null || rhs == null || temps.isEmpty || rhs.isEmpty) {
      // fall back to your old moisture-based interpretation
      return fallback;
    }

    final cs = Theme.of(context).colorScheme;
    TextStyle t(double sz, {FontWeight? w, Color? c}) =>
        GoogleFonts.poppins(fontSize: sz, fontWeight: w, color: c ?? cs.onSurface);

    // compute simple stats & trend
    double avg(List<double> xs) => xs.reduce((a, b) => a + b) / xs.length;
    double delta(List<double> xs) => xs.last - xs.first;

    final tVals = temps.map((e) => e.value).toList();
    final hVals = rhs.map((e) => e.value).toList();

    final tAvg = avg(tVals);
    final tMin = tVals.reduce((a, b) => a < b ? a : b);
    final tMax = tVals.reduce((a, b) => a > b ? a : b);
    final tDel = delta(tVals);

    final hAvg = avg(hVals);
    final hMin = hVals.reduce((a, b) => a < b ? a : b);
    final hMax = hVals.reduce((a, b) => a > b ? a : b);
    final hDel = delta(hVals);

    // simple rule set (milling-safe window)
    final tempOk = (tAvg >= 55 && tAvg <= 60);
    final rhOk = (hAvg <= 45);
    final statusIconColor = (tempOk && rhOk)
        ? context.brand
        : (tAvg > 65 || hAvg > 55)
            ? Colors.red
            : Colors.amber;

    String trend(double d) =>
        d.abs() < 0.6 ? 'stable' : (d > 0 ? 'rising' : 'falling');

    return _SectionCard(
      title: 'Interpretation',
      titleStyle: t(titleSize, w: FontWeight.w700),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.agriculture_rounded, color: statusIconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  (tempOk && rhOk)
                      ? 'Drying environment is stable and within safe range for milling.'
                      : (tAvg > 65 || hAvg > 55)
                          ? 'Environment outside recommended window.'
                          : 'Environment may be improved for tighter control.',
                  style: t(14, w: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _bullet('Temperature — Avg: ${tAvg.toStringAsFixed(1)}°C • '
              'Range: ${tMin.toStringAsFixed(1)}–${tMax.toStringAsFixed(1)}°C • '
              'Change: ${trend(tDel)} (Δ ${tDel >= 0 ? '+' : ''}${tDel.toStringAsFixed(1)}°C)', t(13, w: FontWeight.w500), bulletGap),
          _bullet('Humidity — Avg: ${hAvg.toStringAsFixed(1)}% • '
              'Range: ${hMin.toStringAsFixed(1)}–${hMax.toStringAsFixed(1)}% • '
              'Change: ${trend(hDel)} (Δ ${hDel >= 0 ? '+' : ''}${hDel.toStringAsFixed(1)}%)', t(13, w: FontWeight.w500), bulletGap),
          const SizedBox(height: 8),
          Text(
            (tempOk && rhOk)
                ? 'Recommendation: Maintain airflow and temperature; conditions are optimal for controlled drying.'
                : (tAvg > 65 || hAvg > 55)
                    ? 'Recommendation: Lower temperature and/or increase airflow to reduce RH; avoid overdrying risk.'
                    : 'Recommendation: Slightly raise temperature or reduce RH to tighten control window.',
            style: t(13, w: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _bullet(String text, TextStyle style, double gap) => Padding(
        padding: EdgeInsets.only(bottom: gap),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('• '),
            Expanded(child: Text(text, style: style)),
          ],
        ),
      );
}

/// ------------ Card 3: Session Summary ------------
class _SessionSummaryCard extends StatelessWidget {
  final OperationRecord op;
  final double titleSize;

  const _SessionSummaryCard({
    required this.op,
    required this.titleSize,
  });

  // very light placeholder – tune with calibration
  String _estimateLoss(OperationRecord op) {
    // If you have real fields, swap this out.
    // Fallback uses top-tiles average as a rough proxy.
    if (op.readings.isEmpty) return '—';
    final vals = op.readings.map((e) => e.value).toList();
    final loss = (vals.first - vals.last).abs();
    if (loss == 0) return '~3–5% (est.)'; // default guess while calibrating
    return '${loss.toStringAsFixed(1)}% (est.)';
    }

  String _fmtTime(DateTime dt) => DateFormat('MMM d, HH:mm:ss').format(dt);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    TextStyle t(double sz, {FontWeight? w, Color? c}) =>
        GoogleFonts.poppins(fontSize: sz, fontWeight: w, color: c ?? cs.onSurface);

    // Safely try to read optional user inputs.
    String target = '—';
    String preset = '—';
    String intended = '—';
    try {
      final d = (op as dynamic);
      final mc = d.targetMc as double?;
      if (mc != null) target = '${mc.toStringAsFixed(1)}%';
      preset = (d.presetLabel ?? d.preset ?? '—').toString();
      intended = (d.intendedUse ?? '—').toString();
    } catch (_) {}

    final dur = op.duration;
    final durText = (dur == null)
        ? '—'
        : '${dur.inHours > 0 ? '${dur.inHours}h ' : ''}'
          '${dur.inMinutes.remainder(60).toString().padLeft(2, '0')}m '
          '${dur.inSeconds.remainder(60).toString().padLeft(2, '0')}s';

    final trapdoor = 'Activated at end of session';

    return _SectionCard(
      title: 'Session Summary',
      titleStyle: t(titleSize, w: FontWeight.w700, c: context.brand),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('Target Moisture Content', target, t(13)),
          _row('Preset Selected', preset, t(13)),
          _row('Intended Use', intended, t(13)),
          const SizedBox(height: 8),
          _row('Estimated Moisture Loss', _estimateLoss(op), t(13, w: FontWeight.w600, c: cs.primary)),
          const Divider(height: 20),
          _row('Started', _fmtTime(op.startedAt), t(13)),
          _row('Ended', op.endedAt == null ? '—' : _fmtTime(op.endedAt!), t(13)),
          _row('Duration (incl. init & cooldown)', durText, t(13)),
          _row('Trapdoor', trapdoor, t(13)),
        ],
      ),
    );
  }

  Widget _row(String label, String value, TextStyle vStyle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500))),
          Text(value, style: vStyle),
        ],
      ),
    );
  }
}

/// ------------ Your original Info footer ------------
class _InfoFooter extends StatelessWidget {
  final OperationRecord op;
  const _InfoFooter({required this.op});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final df = DateFormat('MMM d, HH:mm:ss');
    final start = df.format(op.startedAt);
    final end = op.endedAt == null ? '—' : df.format(op.endedAt!);
    final points = op.readings.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Started: $start • Ended: $end • Points: $points',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: cs.onSurface.withOpacity(0.85),
          ),
        ),
      ),
    );
  }
}

/// ------------ (Kept) Moisture interpretation for fallback ------------
enum _MoistureStatus { tooDry, ok, tooWet }

class _AnalysisResult {
  final _MoistureStatus status;
  final String headline;
  final List<String> points;
  final String recommendation;
  _AnalysisResult({
    required this.status,
    required this.headline,
    required this.points,
    required this.recommendation,
  });
}

class _InterpretationCard extends StatelessWidget {
  final OperationRecord? op;
  final double titleSize;
  final EdgeInsets? padding;
  final double bulletGap;

  const _InterpretationCard({
    required this.op,
    required this.titleSize,
    this.padding,
    this.bulletGap = 4,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    TextStyle t(double sz, {FontWeight? w, Color? c}) =>
        GoogleFonts.poppins(
            fontSize: sz, fontWeight: w, color: c ?? cs.onSurface);

    if (op == null || op!.readings.isEmpty) {
      return _SectionCard(
        title: 'Interpretation',
        titleStyle: t(titleSize, w: FontWeight.w700),
        child: _EmptyState(
          message: 'No data to interpret.',
          textStyle:
              t(14, w: FontWeight.w500, c: cs.onSurface.withOpacity(0.85)),
        ),
      );
    }

    final analysis = _analyzeOperation(op!);
    final statusColor = switch (analysis.status) {
      _MoistureStatus.tooDry => Colors.amber,
      _MoistureStatus.ok => context.brand,
      _MoistureStatus.tooWet => Colors.red,
    };

    return _SectionCard(
      title: 'Interpretation',
      titleStyle: t(titleSize, w: FontWeight.w700),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.agriculture_rounded, color: statusColor),
              const SizedBox(width: 8),
              Expanded(
                child:
                    Text(analysis.headline, style: t(14, w: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...analysis.points.map(
            (p) => Padding(
              padding: EdgeInsets.only(bottom: bulletGap),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• '),
                  Expanded(child: Text(p, style: t(13, w: FontWeight.w500))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(analysis.recommendation, style: t(13, w: FontWeight.w700)),
        ],
      ),
    );
  }
}

_AnalysisResult _analyzeOperation(OperationRecord op) {
  final r = op.readings;
  final n = r.length;
  final values = r.map((e) => e.value).toList();
  final avg = values.reduce((a, b) => a + b) / n;
  final minV = values.reduce((a, b) => a < b ? a : b);
  final maxV = values.reduce((a, b) => a > b ? a : b);
  final first = values.first;
  final last = values.last;
  final delta = last - first;

  final trend =
      delta.abs() < 1.0 ? 'stable' : (delta > 0 ? 'rising' : 'falling');

  final dur = op.duration;
  final durText = (dur == null)
      ? '—'
      : '${dur.inMinutes.remainder(60).toString().padLeft(2, '0')}:${dur.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  const low = 12.0;
  const high = 18.0;

  final status = avg < low
      ? _MoistureStatus.tooDry
      : (avg > high ? _MoistureStatus.tooWet : _MoistureStatus.ok);

  final headline = switch (status) {
    _MoistureStatus.tooDry => 'Soil is DRY overall',
    _MoistureStatus.ok => 'Moisture is within the target range',
    _MoistureStatus.tooWet => 'Soil is TOO WET overall',
  };

  final points = <String>[
    'Average moisture: ${avg.toStringAsFixed(1)}%',
    'Range: ${minV.toStringAsFixed(1)}% – ${maxV.toStringAsFixed(1)}%',
    'Change Rate: $trend (Δ ${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}%)',
    'Duration: $durText',
    'Samples: $n',
  ];

  final recommendation = switch (status) {
    _MoistureStatus.tooDry =>
        'Recommendation: Consider watering soon to lift moisture above $low%.',
    _MoistureStatus.ok =>
        'Recommendation: Conditions look good (target is $low–$high%). Maintain current routine.',
    _MoistureStatus.tooWet =>
        'Recommendation: Reduce watering or allow drying until moisture falls below $high%.',
  };

  return _AnalysisResult(
    status: status,
    headline: headline,
    points: points,
    recommendation: recommendation,
  );
}
