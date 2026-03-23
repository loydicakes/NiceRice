import 'dart:convert';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nice_rice/data/operation_models.dart';
import 'package:nice_rice/data/operation_history.dart';

import 'package:nice_rice/header.dart';
import 'package:nice_rice/theme_controller.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:nice_rice/l10n/app_localizations.dart';

// -----------------------------------------------------------------------------
// Constants
// -----------------------------------------------------------------------------
const double _kRateMcPerMin = 0.27;

// -----------------------------------------------------------------------------
// Top‑level helpers (shared by UI + PDF)
// -----------------------------------------------------------------------------
String intendedUseFromTarget(double? targetMc) {
  if (targetMc == null) return '—';
  final mc = targetMc;
  if (mc <= 9.5) return 'for long‑term seed storage';
  if (mc <= 11.5) return 'for medium‑term storage';
  if (mc <= 12.5) return 'for short‑term milling';
  if (mc <= 14.0) return 'for storage within 2–3 months (good for milling)';
  return '—';
}

String fmtHMS(Duration d) =>
    '${d.inHours > 0 ? '${d.inHours}h ' : ''}'
    '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}m '
    '${d.inSeconds.remainder(60).toString().padLeft(2, '0')}s';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

enum _FilterRange { today, yesterday, last3, last7 }

class _AnalyticsPageState extends State<AnalyticsPage> {
  String? _selectedOpId;
  late final OperationHistory repo;

  final Map<String, String> _customTitles = {};
  _FilterRange _filter = _FilterRange.today;

  final _scroll = ScrollController();
  bool _isAtBottom = false;

  static const _kPrefsFilter = 'analytics_filter';
  static const _kPrefsTitles = 'analytics_titles_v1';

  @override
  void initState() {
    super.initState();
    repo = OperationHistory.instance;
    repo.ensureLoaded();
    _loadPrefs();

    _scroll.addListener(() {
      final pos = _scroll.position;
      final atBottom = pos.pixels >= (pos.maxScrollExtent - 12);
      if (atBottom != _isAtBottom) setState(() => _isAtBottom = atBottom);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();

    final idx = p.getInt(_kPrefsFilter);
    if (idx != null && idx >= 0 && idx < _FilterRange.values.length) {
      _filter = _FilterRange.values[idx];
    }

    final titlesJson = p.getString(_kPrefsTitles);
    if (titlesJson != null && titlesJson.isNotEmpty) {
      final Map<String, dynamic> raw = json.decode(titlesJson);
      _customTitles
        ..clear()
        ..addAll(raw.map((k, v) => MapEntry(k, v.toString())));
    }

    if (mounted) setState(() {});
  }

  Future<void> _saveFilter(_FilterRange f) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kPrefsFilter, f.index);
  }

  Future<void> _saveTitles() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPrefsTitles, json.encode(_customTitles));
  }

  // FIX 1: added .toDouble() so return type is actually double, not num
  double _scaleForWidth(double width) =>
      (width / 375).clamp(0.85, 1.25).toDouble();

  // FIX 2: simplified to read the real field; removed all dead orphaned code
  // that was previously floating outside any method body
  String? _getTitleFromOp(OperationRecord op) => op.customTitle;

  String _titleFor(OperationRecord op) {
    final fromOp = _getTitleFromOp(op);
    if (fromOp != null) return fromOp;
    final local = _customTitles[op.id];
    if (local != null && local.trim().isNotEmpty) return local;
    return op.displayTitle;
  }

  // FIX 3: replaced the broken dynamic-probing block with a direct call
  Future<bool> _persistTitleToRepo(OperationRecord op, String newTitle) async {
    try {
      await repo.setCustomTitle(op.id, newTitle);
      return true;
    } catch (e) {
      debugPrint('❌ Failed to persist title: $e');
      return false;
    }
  }

  List<OperationRecord> _applyFilter(List<OperationRecord> all) {
    final now = DateTime.now();

    bool isSameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    bool withinDays(DateTime when, int days) {
      final cutoff = now.subtract(Duration(days: days));
      return when.isAfter(cutoff) || isSameDay(when, cutoff);
    }

    bool inYesterday(DateTime when) {
      final y = now.subtract(const Duration(days: 1));
      return isSameDay(when, y);
    }

    Iterable<OperationRecord> pick(Iterable<OperationRecord> src) sync* {
      for (final op in src) {
        final keyTime = op.endedAt ?? op.startedAt;
        switch (_filter) {
          case _FilterRange.today:
            if (isSameDay(keyTime, now)) yield op;
            break;
          case _FilterRange.yesterday:
            if (inYesterday(keyTime)) yield op;
            break;
          case _FilterRange.last3:
            if (withinDays(keyTime, 3)) yield op;
            break;
          case _FilterRange.last7:
            if (withinDays(keyTime, 7)) yield op;
            break;
        }
      }
    }

    return pick(all).toList();
  }

  OperationRecord? _currentSelected(List<OperationRecord> ops) {
    if (ops.isEmpty) return null;
    final fallback = ops.first;
    return (_selectedOpId == null)
        ? fallback
        : (ops.firstWhere(
            (o) => o.id == _selectedOpId,
            orElse: () => fallback,
          ));
  }

  Future<void> _promptRename(OperationRecord? current) async {
    if (current == null) return;
    final cs = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: _titleFor(current));

    Future<void> performRename() async {
      final txt = controller.text.trim();
      if (txt.isEmpty) return;
      setState(() => _customTitles[current.id] = txt);
      await _saveTitles();
      final ok = await _persistTitleToRepo(current, txt);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? t.analytics_renameSaved : t.analytics_renameFailed,
          ),
        ),
      );
      if (mounted) setState(() {});
    }

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          t.analytics_renameSession,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: t.analytics_sessionName,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) async {
            await performRename();
            if (ctx.mounted) Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              t.common_cancel,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: context.brand,
              ),
            ),
          ),
          FilledButton(
            onPressed: () async {
              await performRename();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(
              t.common_save,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                color: cs.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  double? _extractTargetMc(OperationRecord op) {
    double? tryNumField(String name) {
      try {
        final dyn = op as dynamic;
        final v = dyn.toJson?.call()?[name];
        if (v is num) return v.toDouble();
      } catch (_) {}
      try {
        final dyn = op as dynamic;
        if (name == 'targetMc') return (dyn as dynamic).targetMc as double?;
        if (name == 'target') return (dyn as dynamic).target as double?;
        if (name == 'targetMoisture')
          return (dyn as dynamic).targetMoisture as double?;
        if (name == 'targetMoistureContent')
          return (dyn as dynamic).targetMoistureContent as double?;
        if (name == 'target_mc') return (dyn as dynamic).target_mc as double?;
      } catch (_) {}
      return null;
    }

    for (final key in [
      'targetMc',
      'target',
      'targetMoisture',
      'targetMoistureContent',
      'target_mc',
    ]) {
      final got = tryNumField(key);
      if (got != null) return got;
    }

    double? fromMap(Map m) {
      for (final key in [
        'targetMc',
        'target_mc',
        'target',
        'targetMoisture',
        'targetMoistureContent',
      ]) {
        final v = m[key];
        if (v is num) return v.toDouble();
        if (v is String) {
          final p = double.tryParse(v);
          if (p != null) return p;
        }
      }
      return null;
    }

    Map<String, dynamic>? getMap(dynamic maybe) {
      if (maybe is Map) return maybe.map((k, v) => MapEntry(k.toString(), v));
      return null;
    }

    try {
      final dyn = op as dynamic;
      for (final key in ['meta', 'metadata', 'extras', 'extra']) {
        try {
          final m = getMap((dyn as dynamic).toJson?.call()?[key]);
          final got = (m == null) ? null : fromMap(m);
          if (got != null) return got;
        } catch (_) {}
        try {
          final m = getMap((dyn as dynamic).meta);
          final got = (m == null) ? null : fromMap(m);
          if (got != null) return got;
        } catch (_) {}
      }
    } catch (_) {}

    return null;
  }

  double? _extractInitialMc(OperationRecord op) {
    double? tryNumField(String name) {
      try {
        final dyn = op as dynamic;
        final v = dyn.toJson?.call()?[name];
        if (v is num) return v.toDouble();
      } catch (_) {}
      try {
        final dyn = op as dynamic;
        if (name == 'initialMc') return (dyn as dynamic).initialMc as double?;
        if (name == 'initialMoisture')
          return (dyn as dynamic).initialMoisture as double?;
        if (name == 'initial') return (dyn as dynamic).initial as double?;
      } catch (_) {}
      return null;
    }

    for (final key in ['initialMc', 'initialMoisture', 'initial']) {
      final got = tryNumField(key);
      if (got != null) return got;
    }

    double? fromMap(Map m) {
      for (final key in ['initialMc', 'initial_moisture', 'initial']) {
        final v = m[key];
        if (v is num) return v.toDouble();
        if (v is String) {
          final p = double.tryParse(v);
          if (p != null) return p;
        }
      }
      return null;
    }

    Map<String, dynamic>? getMap(dynamic maybe) {
      if (maybe is Map) return maybe.map((k, v) => MapEntry(k.toString(), v));
      return null;
    }

    try {
      final dyn = op as dynamic;
      for (final key in ['meta', 'metadata', 'extras', 'extra']) {
        try {
          final m = getMap((dyn as dynamic).toJson?.call()?[key]);
          final got = (m == null) ? null : fromMap(m);
          if (got != null) return got;
        } catch (_) {}
        try {
          final m = getMap((dyn as dynamic).meta);
          final got = (m == null) ? null : fromMap(m);
          if (got != null) return got;
        } catch (_) {}
      }
    } catch (_) {}
    return null;
  }

  void _openExportSheet({
    required BuildContext context,
    required OperationRecord? current,
    required List<OperationRecord> all,
  }) {
    final t = AppLocalizations.of(context)!;
    final selectedIds = <String>{if (current != null) current.id};
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
                left: 16,
                right: 16,
                top: 12,
                bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.analytics_exportAnalyticsPdf,
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t.analytics_chooseSessions,
                    style: GoogleFonts.poppins(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  RadioListTile<bool>(
                    value: false,
                    groupValue: pickSpecific,
                    onChanged: (v) => setSt(() => pickSpecific = v ?? false),
                    title: Text(t.analytics_currentSessionOnly),
                  ),
                  RadioListTile<bool>(
                    value: true,
                    groupValue: pickSpecific,
                    onChanged: (v) => setSt(() => pickSpecific = v ?? true),
                    title: Text(t.analytics_selectSessions),
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
                            title: Text(
                              _titleFor(op),
                              overflow: TextOverflow.ellipsis,
                            ),
                            onChanged: (v) {
                              setSt(() {
                                if (v == true) {
                                  selectedIds.add(op.id);
                                } else {
                                  selectedIds.remove(op.id);
                                }
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
                        child: Text(t.common_cancel),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        icon: const Icon(Icons.download),
                        label: Text(t.analytics_generatePdf),
                        onPressed: () async {
                          final chosen = pickSpecific
                              ? all
                                    .where((o) => selectedIds.contains(o.id))
                                    .toList()
                              : (current == null
                                    ? <OperationRecord>[]
                                    : [current]);
                          if (chosen.isEmpty) return;
                          Navigator.pop(ctx);
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

  Future<void> _generatePdf(
    BuildContext context,
    List<OperationRecord> sessions,
  ) async {
    final t = AppLocalizations.of(context)!;
    final doc = pw.Document();

    for (final op in sessions) {
      doc.addPage(
        pw.Page(
          build: (pw.Context c) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                t.analytics_reportTitle,
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                _titleFor(op),
                style: const pw.TextStyle(
                  fontSize: 12,
                  color: PdfColors.grey600,
                ),
              ),
              pw.Divider(height: 24),
              _pdfEstimatedMoistureSection(op, t),
              pw.SizedBox(height: 20),
              _pdfInterpretationSection(op, t),
              pw.SizedBox(height: 20),
              _pdfDryingSpeedSection(op, t),
              pw.SizedBox(height: 20),
              pw.Text(
                t.analytics_environmentIfAvailable,
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              _pdfEnvStats(op, t),
              pw.Spacer(),
              pw.Divider(),
              pw.Text(
                t.analytics_notesBody,
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename:
          'NiceRice-Report_${DateTime.now().toIso8601String().replaceAll(":", "-")}.pdf',
    );
  }

  pw.Widget _pdfSection(String title, {required pw.Widget child}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.green800,
          ),
        ),
        pw.SizedBox(height: 12),
        child,
      ],
    );
  }

  pw.Widget _pdfEstimatedMoistureSection(
    OperationRecord op,
    AppLocalizations t,
  ) {
    final targetMc = _extractTargetMc(op) ?? 14.0;
    double? initialMc = _extractInitialMc(op);
    Duration dur = op.duration ?? Duration.zero;

    if (dur == Duration.zero && op.readings.length >= 2) {
      dur = op.readings.last.t.difference(op.readings.first.t);
    }
    if (dur == Duration.zero) {
      final mins = (initialMc != null)
          ? ((initialMc - targetMc).clamp(0, 999.0) / _kRateMcPerMin)
          : 30.0;
      dur = Duration(minutes: mins.ceil());
    }

    // FIX 4: null-coalesce initialMc before using in FlSpot/PointChartValue
    initialMc ??= targetMc + max(1, dur.inMinutes) * _kRateMcPerMin;

    final spots = <pw.PointChartValue>[
      pw.PointChartValue(0, initialMc),
      pw.PointChartValue(max(1, dur.inSeconds).toDouble(), targetMc),
    ];

    final yMin = min(spots.first.y, spots.last.y).floorToDouble();
    final yMax = max(spots.first.y, spots.last.y).ceilToDouble();
    final xMax = spots.last.x;

    final start = op.startedAt;
    String xLabel(double x) =>
        DateFormat('HH:mm').format(start.add(Duration(seconds: x.round())));

    return _pdfSection(
      t.analytics_estimatedGrainMoisture,
      child: pw.Container(
        height: 180,
        child: pw.Chart(
          grid: pw.CartesianGrid(
            xAxis: pw.FixedAxis([
              0,
              xMax / 2,
              xMax,
            ], format: (v) => xLabel(v.toDouble())),
            yAxis: pw.FixedAxis([
              yMin,
              (yMin + yMax) / 2,
              yMax,
            ], format: (v) => '${v.toStringAsFixed(0)}%'),
          ),
          datasets: [
            pw.LineDataSet(
              data: spots,
              color: PdfColors.green,
              lineWidth: 2,
              drawPoints: true,
              drawSurface: true,
              surfaceColor: PdfColor.fromInt(0x80A5D66D),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _pdfInterpretationSection(OperationRecord op, AppLocalizations t) {
    final targetMc = _extractTargetMc(op) ?? 14.0;
    double initialMc =
        _extractInitialMc(op) ??
        (targetMc +
            max(1, (op.duration ?? const Duration(minutes: 30)).inMinutes) *
                _kRateMcPerMin);

    final dur =
        op.duration ??
        (op.readings.length >= 2
            ? op.readings.last.t.difference(op.readings.first.t)
            : const Duration(minutes: 30));
    final loss = (initialMc - targetMc).clamp(0, 999).toDouble();

    pw.Widget bullet(String label, String value) {
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(width: 8, child: pw.Text('- ')),
          pw.Expanded(
            child: pw.RichText(
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(
                    text: '$label: ',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return _pdfSection(
      t.analytics_interpretation,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  t.analytics_moistureChartDescription,
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontStyle: pw.FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          bullet(
            t.analytics_initialMoisture,
            '${initialMc.toStringAsFixed(1)}%',
          ),
          pw.SizedBox(height: 3),
          bullet(t.analytics_targetMoisture, '${targetMc.toStringAsFixed(1)}%'),
          pw.SizedBox(height: 3),
          bullet(
            t.analytics_estimatedMoistureLoss,
            '${loss.toStringAsFixed(1)}%',
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            t.analytics_summary,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '- ${t.analytics_mcDropped(initialMc.toStringAsFixed(1), targetMc.toStringAsFixed(1), fmtHMS(dur))}',
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            '- ${t.analytics_moistureLossSummary(loss.toStringAsFixed(1))}',
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfDryingSpeedSection(OperationRecord op, AppLocalizations t) {
    final dur = op.duration;
    final durText = (dur == null) ? '—' : fmtHMS(dur);

    pw.TableRow row(String label, String value) {
      return pw.TableRow(
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Text(label),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Text(
              value,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      );
    }

    return _pdfSection(
      t.analytics_sessionSummary,
      child: pw.Table(
        columnWidths: const {
          0: pw.FlexColumnWidth(1),
          1: pw.FlexColumnWidth(2),
        },
        children: [
          row(
            t.analytics_start,
            DateFormat('MMM d, HH:mm:ss').format(op.startedAt),
          ),
          row(
            t.analytics_end,
            op.endedAt == null
                ? '—'
                : DateFormat('MMM d, HH:mm:ss').format(op.endedAt!),
          ),
          row(t.analytics_duration, durText),
        ],
      ),
    );
  }

  pw.Widget _pdfEnvStats(OperationRecord op, AppLocalizations t) {
    double? tAvg, tMin, tMax, hAvg, hMin, hMax;

    try {
      final temps =
          ((op as dynamic).temps ?? (op as dynamic).temperatureReadings)
              as List<dynamic>?;
      if (temps != null && temps.isNotEmpty) {
        final tv = temps
            .map((e) => (e as dynamic).value as num)
            .map((e) => e.toDouble())
            .toList();
        tAvg = tv.reduce((a, b) => a + b) / tv.length;
        tMin = tv.reduce(min);
        tMax = tv.reduce(max);
      }
    } catch (_) {}

    try {
      final rhs =
          ((op as dynamic).humidities ?? (op as dynamic).humidityReadings)
              as List<dynamic>?;
      if (rhs != null && rhs.isNotEmpty) {
        final hv = rhs
            .map((e) => (e as dynamic).value as num)
            .map((e) => e.toDouble())
            .toList();
        hAvg = hv.reduce((a, b) => a + b) / hv.length;
        hMin = hv.reduce(min);
        hMax = hv.reduce(max);
      }
    } catch (_) {}

    pw.TableRow row(String label, String value) {
      return pw.TableRow(
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Text(
              value,
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      );
    }

    final rows = <pw.TableRow>[];
    if (tAvg != null) {
      rows.add(
        row(
          t.analytics_temperatureAvgRange,
          '${tAvg.toStringAsFixed(1)}°C • '
          '${(tMin ?? tAvg).toStringAsFixed(1)}–${(tMax ?? tAvg).toStringAsFixed(1)}°C',
        ),
      );
    }
    if (hAvg != null) {
      rows.add(
        row(
          t.analytics_humidityAvgRange,
          '${hAvg.toStringAsFixed(1)}% • '
          '${(hMin ?? hAvg).toStringAsFixed(1)}–${(hMax ?? hAvg).toStringAsFixed(1)}%',
        ),
      );
    }
    if (rows.isEmpty) {
      return pw.Text(
        t.analytics_noEnvData,
        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
      );
    }

    return pw.Table(
      columnWidths: const {0: pw.FlexColumnWidth(1), 1: pw.FlexColumnWidth(2)},
      children: rows,
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeScope = ThemeScope.of(context);
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: PageHeader(
        isDarkMode: themeScope.isDark,
        onThemeChanged: themeScope.setDark,
      ),
      floatingActionButton: (repo.operations.isEmpty || _isAtBottom)
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.picture_as_pdf),
              label: Text(t.analytics_exportPdf),
              onPressed: () {
                _openExportSheet(
                  context: context,
                  current: _currentSelected(_applyFilter(repo.operations)),
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
            final filtered = _applyFilter(ops);
            final selected = _currentSelected(filtered);

            TextStyle txt({
              double? size,
              FontWeight? w,
              Color? c,
              double? h,
              TextDecoration? d,
            }) => GoogleFonts.poppins(
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
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (ops.isEmpty)
                          _EmptyState(
                            height: emptyH.toDouble(),
                            message: t.analytics_emptyHistory,
                            textStyle: txt(
                              size: 14 * scale,
                              w: FontWeight.w500,
                              c: cs.onSurface.withOpacity(0.85),
                            ),
                          )
                        else ...[
                          // ── Picker + Filter + Rename ──
                          Card(
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: (12 * scale).clamp(10, 16),
                                vertical: (12 * scale).clamp(10, 16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _FilterButtonsRow(
                                    value: _filter,
                                    onChanged: (f) async {
                                      setState(() {
                                        _filter = f;
                                        _selectedOpId = null;
                                      });
                                      await _saveFilter(f);
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  if (filtered.isEmpty)
                                    _EmptyState(
                                      message: t.analytics_noSessionsForFilter,
                                      textStyle: txt(
                                        size: (14 * scale).clamp(12, 18),
                                        w: FontWeight.w500,
                                        c: cs.onSurface.withOpacity(0.8),
                                      ),
                                      height: (110 * scale)
                                          .clamp(90, 140)
                                          .toDouble(),
                                    )
                                  else
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.history,
                                          size: (20 * scale).clamp(18, 24),
                                          color: context.brand,
                                        ),
                                        SizedBox(
                                          width: (10 * scale)
                                              .clamp(8, 14)
                                              .toDouble(),
                                        ),
                                        Expanded(
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              value:
                                                  (selected ?? filtered.first)
                                                      .id,
                                              isExpanded: true,
                                              iconEnabledColor: context.brand,
                                              items: filtered
                                                  .map(
                                                    (op) => DropdownMenuItem(
                                                      value: op.id,
                                                      child: Text(
                                                        _titleFor(op),
                                                        overflow: TextOverflow
                                                            .ellipsis,
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
                                                  setState(
                                                    () =>
                                                        _selectedOpId = value,
                                                  );
                                                }
                                              },
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Tooltip(
                                          message: t.tooltip_renameSession,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            onTap: () =>
                                                _promptRename(selected),
                                            child: const Padding(
                                              padding: EdgeInsets.all(6.0),
                                              child: Icon(Icons.edit_outlined),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 14),

                          _SectionCard(
                            title: t.analytics_estimatedGrainMoisture,
                            titleStyle: txt(
                              size: (16 * scale).clamp(14, 20),
                              w: FontWeight.w700,
                              c: context.brand,
                            ),
                            child: _EstimatedMoistureChart(
                              op: selected,
                              height:
                                  (isTablet ? 320.0 : 260.0) *
                                  (scale.clamp(0.9, 1.1)),
                              empty: _EmptyState(
                                height: emptyH * 0.7,
                                message: t.analytics_notEnoughData,
                                textStyle: txt(
                                  size: (14 * scale).clamp(12, 18),
                                  w: FontWeight.w500,
                                  c: cs.onSurface.withOpacity(0.85),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          _EstimatedMcInterpretationCard(
                            op: selected,
                            titleSize: (16 * scale).clamp(14, 20),
                            bulletGap: (4 * scale).clamp(3, 8),
                          ),

                          const SizedBox(height: 12),

                          if (selected != null)
                            _SessionSummaryCard(
                              op: selected,
                              titleSize: (16 * scale).clamp(14, 20),
                            ),

                          const SizedBox(height: 12),

                          if (repo.operations.isNotEmpty && _isAtBottom)
                            SafeArea(
                              top: false,
                              child: SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  icon: const Icon(Icons.picture_as_pdf),
                                  label: Text(t.analytics_exportPdf),
                                  onPressed: () {
                                    _openExportSheet(
                                      context: context,
                                      current: _currentSelected(
                                        _applyFilter(repo.operations),
                                      ),
                                      all: repo.operations,
                                    );
                                  },
                                ),
                              ),
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

// -----------------------------------------------------------------------------
// UI helpers
// -----------------------------------------------------------------------------

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

class _FilterButtonsRow extends StatelessWidget {
  final _FilterRange value;
  final ValueChanged<_FilterRange> onChanged;
  const _FilterButtonsRow({required this.value, required this.onChanged});

  Widget _btn(BuildContext context, _FilterRange me) {
    final t = AppLocalizations.of(context)!;
    final Map<_FilterRange, String> labels = {
      _FilterRange.today: t.filters_today,
      _FilterRange.yesterday: t.filters_yesterday,
      _FilterRange.last3: t.filters_last3,
      _FilterRange.last7: t.filters_last7,
    };

    final cs = Theme.of(context).colorScheme;
    final selected = value == me;
    return Expanded(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          side: BorderSide(color: selected ? cs.primary : cs.outline),
          backgroundColor: selected
              ? cs.primary.withOpacity(0.10)
              : Colors.transparent,
          foregroundColor: selected ? cs.primary : cs.onSurface,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        ),
        onPressed: () => onChanged(me),
        child: Text(
          labels[me]!,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(width: 6);
    return Row(
      children: [
        _btn(context, _FilterRange.today),
        gap,
        _btn(context, _FilterRange.yesterday),
        gap,
        _btn(context, _FilterRange.last3),
        gap,
        _btn(context, _FilterRange.last7),
      ],
    );
  }
}

class _EnvChart extends StatelessWidget {
  final List<MoistureReading>? temps;
  final List<MoistureReading>? rhs;
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

  factory _EnvChart.fromOperation({
    required OperationRecord? op,
    double? height,
    double scale = 1.0,
    Widget? empty,
  }) {
    List<MoistureReading>? temps;
    List<MoistureReading>? rhs;
    try {
      temps = (op as dynamic).temps as List<MoistureReading>?;
    } catch (_) {
      try {
        temps = (op as dynamic).temperatureReadings as List<MoistureReading>?;
      } catch (_) {
        temps = null;
      }
    }
    try {
      rhs = (op as dynamic).humidities as List<MoistureReading>?;
    } catch (_) {
      try {
        rhs = (op as dynamic).humidityReadings as List<MoistureReading>?;
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
    final t = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    if (temps == null || rhs == null || temps!.length < 2 || rhs!.length < 2) {
      return empty ??
          _EmptyState(
            message: t.analytics_noEnvDataForSession,
            textStyle: GoogleFonts.poppins(
              fontSize: 13,
              color: cs.onSurface.withOpacity(0.75),
              fontWeight: FontWeight.w500,
            ),
          );
    }

    final start = (temps!.first.t.isBefore(rhs!.first.t)
        ? temps!.first.t
        : rhs!.first.t);
    List<FlSpot> toSpots(List<MoistureReading> list) => list
        .map((r) => FlSpot(r.t.difference(start).inSeconds.toDouble(), r.value))
        .toList();

    final tempSpots = toSpots(temps!);
    final rhSpots = toSpots(rhs!);

    double minY(Iterable<double> v) => v.reduce(min);
    double maxY(Iterable<double> v) => v.reduce(max);

    final allTempVals = temps!.map((e) => e.value);
    final allRhVals = rhs!.map((e) => e.value);

    final xMin = 0.0;
    final xMax = [
      tempSpots.isNotEmpty ? tempSpots.last.x : 0.0,
      rhSpots.isNotEmpty ? rhSpots.last.x : 0.0,
    ].reduce(max);

    final tMin = (minY(allTempVals).floorToDouble());
    final tMax = (maxY(allTempVals).ceilToDouble());
    final hMin = (minY(allRhVals).floorToDouble());
    final hMax = (maxY(allRhVals).ceilToDouble());

    String xLabel(double x) =>
        DateFormat('HH:mm').format(start.add(Duration(seconds: x.round())));

    final gridColor = cs.onSurface.withOpacity(0.10);
    final borderColor = cs.outline.withOpacity(0.55);
    final labelColor = cs.onSurface.withOpacity(0.70);
    TextStyle tS(double sz, [FontWeight? w]) =>
        GoogleFonts.poppins(fontSize: sz, fontWeight: w, color: labelColor);

    Widget bottomTitleWidgets(double value, TitleMeta meta) {
      return SideTitleWidget(
        axisSide: meta.axisSide,
        space: 8.0,
        child: Text(xLabel(value), style: tS(11)),
      );
    }

    Widget leftTitleWidgets(double value, TitleMeta meta) {
      return Text(value.toStringAsFixed(0), style: tS(11));
    }

    Widget rightTitleWidgets(double value, TitleMeta meta) {
      return Text(value.toStringAsFixed(0), style: tS(11));
    }

    return SizedBox(
      height: height ?? 260,
      child: Stack(
        children: [
          LineChart(
            LineChartData(
              minX: xMin,
              maxX: xMax,
              minY: tMin,
              maxY: tMax,
              gridData: FlGridData(
                show: true,
                horizontalInterval: ((tMax - tMin) / 4)
                    .clamp(1, 100)
                    .toDouble(),
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: gridColor, strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: (xMax - xMin) / 4.0,
                    getTitlesWidget: bottomTitleWidgets,
                  ),
                ),
                leftTitles: AxisTitles(
                  axisNameWidget: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('°C', style: tS(10)),
                  ),
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    interval: ((tMax - tMin) / 5).clamp(1, 100).toDouble(),
                    getTitlesWidget: leftTitleWidgets,
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
                  barWidth: 3,
                  color: Theme.of(context).colorScheme.primary,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.18),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 40.0),
            child: LineChart(
              LineChartData(
                minX: xMin,
                maxX: xMax,
                minY: hMin,
                maxY: hMax,
                gridData: const FlGridData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    axisNameWidget: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('% RH', style: tS(10)),
                    ),
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      interval: ((hMax - hMin) / 5).clamp(1, 100).toDouble(),
                      getTitlesWidget: rightTitleWidgets,
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: rhSpots,
                    isCurved: true,
                    barWidth: 3,
                    color: Theme.of(context).colorScheme.secondary,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Theme.of(
                        context,
                      ).colorScheme.secondary.withOpacity(0.14),
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

class _EstimatedMoistureChart extends StatelessWidget {
  final OperationRecord? op;
  final double? height;
  final Widget? empty;
  const _EstimatedMoistureChart({required this.op, this.height, this.empty});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    if (op == null) return empty ?? Text(t.analytics_notEnoughData);

    final state = context.findAncestorStateOfType<_AnalyticsPageState>();
    final targetMc = state?._extractTargetMc(op!) ?? 14.0;
    double? initialMc = state?._extractInitialMc(op!);

    Duration dur = op!.duration ?? Duration.zero;
    if (dur == Duration.zero && op!.readings.length >= 2) {
      dur = op!.readings.last.t.difference(op!.readings.first.t);
    }
    if (dur == Duration.zero) {
      final mins = (initialMc != null)
          ? ((initialMc - targetMc).clamp(0, 999.0) / _kRateMcPerMin)
          : 30.0;
      dur = Duration(minutes: mins.ceil());
    }

    // FIX 4: null-coalesce before using in FlSpot (double? → double)
    initialMc ??= targetMc + max(1, dur.inMinutes) * _kRateMcPerMin;

    final spots = <FlSpot>[
      FlSpot(0, initialMc),
      FlSpot(max(1, dur.inSeconds).toDouble(), targetMc),
    ];

    final cs = Theme.of(context).colorScheme;
    final start = op!.startedAt;
    String xLabel(double x) =>
        DateFormat('HH:mm').format(start.add(Duration(seconds: x.round())));

    Widget bottomTitleWidgets(double value, TitleMeta meta) {
      return SideTitleWidget(
        axisSide: meta.axisSide,
        space: 8.0,
        child: Text(
          xLabel(value),
          style: GoogleFonts.poppins(
            fontSize: 11,
            color: cs.onSurface.withOpacity(0.7),
          ),
        ),
      );
    }

    Widget leftTitleWidgets(double value, TitleMeta meta) {
      return Text(
        '${value.toStringAsFixed(0)}%',
        style: GoogleFonts.poppins(
          fontSize: 11,
          color: cs.onSurface.withOpacity(0.7),
        ),
      );
    }

    return SizedBox(
      height: height ?? 260,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: spots.last.x,
          minY: min(spots.first.y, spots.last.y).floorToDouble(),
          maxY: max(spots.first.y, spots.last.y).ceilToDouble(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: cs.onSurface.withOpacity(0.08), strokeWidth: 1),
            getDrawingVerticalLine: (_) =>
                FlLine(color: cs.onSurface.withOpacity(0.06), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: max(60, spots.last.x / 4),
                getTitlesWidget: bottomTitleWidgets,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: leftTitleWidgets,
              ),
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border.all(color: cs.outline.withOpacity(0.55)),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              barWidth: 3,
              color: context.brand,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                color: context.brand.withOpacity(0.14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Interpretation card for estimated MC
// -----------------------------------------------------------------------------
class _EstimatedMcInterpretationCard extends StatelessWidget {
  final OperationRecord? op;
  final double titleSize;
  final double bulletGap;
  const _EstimatedMcInterpretationCard({
    required this.op,
    required this.titleSize,
    this.bulletGap = 4,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context)!;
    TextStyle ts(double sz, {FontWeight? w, Color? c}) => GoogleFonts.poppins(
      fontSize: sz,
      fontWeight: w,
      color: c ?? cs.onSurface,
    );

    if (op == null) {
      return _SectionCard(
        title: t.analytics_interpretation,
        titleStyle: ts(titleSize, w: FontWeight.w700),
        child: _EmptyState(
          message: t.analytics_notEnoughData,
          textStyle: ts(
            14,
            w: FontWeight.w500,
            c: cs.onSurface.withOpacity(0.85),
          ),
        ),
      );
    }

    final state = context.findAncestorStateOfType<_AnalyticsPageState>();
    final targetMc = state?._extractTargetMc(op!) ?? 14.0;
    final initialMc =
        state?._extractInitialMc(op!) ??
        (targetMc +
            max(1, (op!.duration ?? const Duration(minutes: 30)).inMinutes) *
                _kRateMcPerMin);

    final dur =
        op!.duration ??
        (op!.readings.length >= 2
            ? op!.readings.last.t.difference(op!.readings.first.t)
            : const Duration(minutes: 30));

    final predictedFinal = targetMc;
    final loss = (initialMc - predictedFinal).clamp(0, 999).toDouble();

    List<Widget> bullet(String label, String value) => [
      Padding(
        padding: EdgeInsets.only(bottom: bulletGap),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('- ', style: ts(13, w: FontWeight.w800)),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: ts(13, w: FontWeight.w500),
                  children: [
                    TextSpan(
                      text: '$label: ',
                      style: ts(13, w: FontWeight.w800),
                    ),
                    TextSpan(text: value),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ];

    return _SectionCard(
      title: t.analytics_interpretation,
      titleStyle: ts(titleSize, w: FontWeight.w700),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.agriculture_rounded, color: context.brand),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t.analytics_moistureChartDescription,
                  style: ts(14, w: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...bullet(
            t.analytics_initialMoisture,
            '${initialMc.toStringAsFixed(1)}%',
          ),
          ...bullet(
            t.analytics_targetMoisture,
            '${targetMc.toStringAsFixed(1)}%',
          ),
          ...bullet(
            t.analytics_estimatedMoistureLoss,
            '${loss.toStringAsFixed(1)}%',
          ),
          const SizedBox(height: 6),
          Text(
            t.analytics_summary,
            style: ts(13, w: FontWeight.w800, c: context.brand),
          ),
          const SizedBox(height: 4),
          Text(
            '• ${t.analytics_mcDropped(initialMc.toStringAsFixed(1), predictedFinal.toStringAsFixed(1), fmtHMS(dur))}',
            style: ts(13, w: FontWeight.w600),
          ),
          Text(
            '• ${t.analytics_moistureLossSummary(loss.toStringAsFixed(1))}',
            style: ts(13, w: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _SessionSummaryCard extends StatelessWidget {
  final OperationRecord op;
  final double titleSize;
  const _SessionSummaryCard({required this.op, required this.titleSize});

  String _fmtTime(DateTime dt) => DateFormat('MMM d, HH:mm:ss').format(dt);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context)!;
    TextStyle ts(double sz, {FontWeight? w, Color? c}) => GoogleFonts.poppins(
      fontSize: sz,
      fontWeight: w,
      color: c ?? cs.onSurface,
    );

    final dur = op.duration;
    final durText = (dur == null) ? '—' : fmtHMS(dur);

    return _SectionCard(
      title: t.analytics_sessionSummary,
      titleStyle: ts(titleSize, w: FontWeight.w700, c: context.brand),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _rowUi(t.analytics_start, _fmtTime(op.startedAt), ts(13)),
          _rowUi(
            t.analytics_end,
            op.endedAt == null ? '—' : _fmtTime(op.endedAt!),
            ts(13),
          ),
          _rowUi(t.analytics_duration, durText, ts(13)),
        ],
      ),
    );
  }

  Widget _rowUi(String label, String value, TextStyle vStyle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(value, style: vStyle),
        ],
      ),
    );
  }
}