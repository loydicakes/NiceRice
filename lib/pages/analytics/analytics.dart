// lib/pages/analytics/analytics.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:nice_rice/data/operation_models.dart';
import 'package:nice_rice/data/operation_history.dart';

import 'package:nice_rice/header.dart';
import 'package:nice_rice/theme_controller.dart'; // ThemeScope + BuildContext.brand

/// ------------ Analytics Page ------------
class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  String? _selectedOpId;
  late final OperationHistory repo;

  @override
  void initState() {
    super.initState();
    repo = OperationHistory.instance;
    repo.ensureLoaded(); // load local + watch cloud
  }

  double _scaleForWidth(double width) => (width / 375).clamp(0.85, 1.25);

  @override
  Widget build(BuildContext context) {
    final themeScope = ThemeScope.of(context);

    return Scaffold(
      appBar: PageHeader(
        isDarkMode: themeScope.isDark,
        onThemeChanged: themeScope.setDark,
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

                          // ───────── Stats tiles ─────────
                          if (selected != null &&
                              selected.readings.isNotEmpty)
                            Card(
                              child: Padding(
                                padding: EdgeInsets.all(
                                    (16 * scale).clamp(12, 22)),
                                child: _StatsRow(
                                  selected: selected!,
                                  scale: scale,
                                ),
                              ),
                            ),

                          const SizedBox(height: 14),

                          // ───────── Chart ─────────
                          _SectionCard(
                            title: 'Moisture Content',
                            titleStyle: txt(
                              size: (16 * scale).clamp(14, 20),
                              w: FontWeight.w700,
                              c: context.brand,
                            ),
                            child: (selected == null ||
                                selected.readings.length < 2)
                                ? _EmptyState(
                              height: emptyH * 0.7,
                              message: 'Not enough data points.',
                              textStyle: txt(
                                size: (14 * scale).clamp(12, 18),
                                w: FontWeight.w500,
                                c: cs.onSurface.withOpacity(0.85),
                              ),
                            )
                                : _MoistureChart(
                              readings: selected.readings,
                              height: (isTablet ? 320.0 : 260.0) *
                                  (scale.clamp(0.9, 1.1)),
                              scale: scale,
                            ),
                          ),

                          const SizedBox(height: 12),

                          // ───────── Info footer ─────────
                          if (selected != null) _InfoFooter(op: selected!),

                          const SizedBox(height: 12),

                          // ───────── Interpretation ─────────
                          _InterpretationCard(
                            op: selected,
                            titleSize: (16 * scale).clamp(14, 20),
                            bulletGap: (4 * scale).clamp(3, 8),
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

    Widget tile(String label, String value, IconData icon) {
      return Container(
        padding: EdgeInsets.all((14 * scale).clamp(10, 18)),
        decoration: BoxDecoration(
          color: cs.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: cs.primary, size: (18 * scale).clamp(16, 22)),
            SizedBox(height: (6 * scale).clamp(4, 10)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: t(size: (24 * scale).clamp(20, 30), w: FontWeight.w800),
              ),
            ),
            SizedBox(height: (2 * scale).clamp(2, 6)),
            Text(label,
                style: t(size: (13 * scale).clamp(11, 16), w: FontWeight.w600)),
          ],
        ),
      );
    }

    if (MediaQuery.of(context).size.width < 420) {
      return Column(
        children: [
          tile("Average", "${avg.toStringAsFixed(1)}%", Icons.timeline_outlined),
          const SizedBox(height: 12),
          tile("Min", "${minV.toStringAsFixed(1)}%", Icons.trending_down_outlined),
          const SizedBox(height: 12),
          tile("Max", "${maxV.toStringAsFixed(1)}%", Icons.trending_up_outlined),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
            child: tile("Average", "${avg.toStringAsFixed(1)}%",
                Icons.timeline_outlined)),
        const SizedBox(width: 12),
        Expanded(
            child: tile("Min", "${minV.toStringAsFixed(1)}%",
                Icons.trending_down_outlined)),
        const SizedBox(width: 12),
        Expanded(
            child: tile("Max", "${maxV.toStringAsFixed(1)}%",
                Icons.trending_up_outlined)),
      ],
    );
  }
}

class _MoistureChart extends StatelessWidget {
  final List<MoistureReading> readings;
  final double? height;
  final double scale;

  const _MoistureChart({
    required this.readings,
    this.height,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final first = readings.first.t;
    final spots = readings
        .map((r) =>
        FlSpot(r.t.difference(first).inSeconds.toDouble(), r.value))
        .toList();

    final yVals = readings.map((e) => e.value).toList();
    final yMin = yVals.reduce((a, b) => a < b ? a : b).floorToDouble();
    final yMax = yVals.reduce((a, b) => a > b ? a : b).ceilToDouble();
    final xMin = 0.0;
    final xMax = spots.isNotEmpty ? spots.last.x : 1.0;

    String xLabel(double x) =>
        DateFormat('HH:mm').format(first.add(Duration(seconds: x.round())));

    final lineColor = cs.primary;
    final areaColor = cs.primary.withOpacity(0.20);
    final gridColor = cs.onSurface.withOpacity(0.10);
    final borderColor = cs.outline.withOpacity(0.55);
    final labelColor = cs.onSurface.withOpacity(0.70);

    TextStyle t(double sz, [FontWeight? w]) =>
        GoogleFonts.poppins(fontSize: sz, fontWeight: w, color: labelColor);

    return SizedBox(
      height: height ?? 260,
      child: LineChart(
        LineChartData(
          minX: xMin,
          maxX: xMax,
          minY: yMin,
          maxY: yMax,
          gridData: FlGridData(
            show: true,
            horizontalInterval:
            ((yMax - yMin) / 4).clamp(1, 100).toDouble(),
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: gridColor, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            topTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: (36 * scale).clamp(28, 44),
                interval:
                ((yMax - yMin) / 5).clamp(1, 100).toDouble(),
                getTitlesWidget: (v, m) =>
                    Text(v.toStringAsFixed(0),
                        style: t((11 * scale).clamp(10, 14))),
              ),
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border.all(color: borderColor),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              barWidth: (3 * scale).clamp(2, 4),
              color: lineColor,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: areaColor),
            ),
          ],
        ),
      ),
    );
  }
}

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

/// ------------ Interpretation ------------
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
                child: Text(analysis.headline, style: t(14, w: FontWeight.w700)),
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
