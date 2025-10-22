// lib/pages/analytics/analytics.dart
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
import 'package:nice_rice/theme_controller.dart'; // ThemeScope + BuildContext.brand

import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// ⬇️ Localizations like on HomePage
import 'package:nice_rice/l10n/app_localizations.dart';

/// ------------ Analytics Page ------------
class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

enum _FilterRange { today, yesterday, last3, last7 }

class _AnalyticsPageState extends State<AnalyticsPage> {
  String? _selectedOpId;
  late final OperationHistory repo;

  // Rename persistence (local fallback cache)
  final Map<String, String> _customTitles = {};

  // Filter persistence
  _FilterRange _filter = _FilterRange.today;

  // Prefs keys
  static const _kPrefsFilter = 'analytics_filter';
  static const _kPrefsTitles = 'analytics_titles_v1';

  @override
  void initState() {
    super.initState();
    repo = OperationHistory.instance;
    repo.ensureLoaded(); // load local + watch cloud
    _loadPrefs();
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

  double _scaleForWidth(double width) => (width / 375).clamp(0.85, 1.25);

  // ---------- TITLE: read & write helpers (DB-first, prefs as fallback) ----------

  /// Tries to get a custom title embedded in the operation record itself.
  /// Looks at common field names and metadata maps.
  String? _getTitleFromOp(OperationRecord op) {
    String? _pull(dynamic obj, String key) {
      try {
        final v = (obj as dynamic).toJson?.call()?[key];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      } catch (_) {}
      try {
        final v = (obj as dynamic).$key as String?;
        if (v != null && v.trim().isNotEmpty) return v.trim();
      } catch (_) {}
      return null;
    }

    // 1) direct fields on op
    for (final k in ['customTitle', 'title', 'name', 'sessionName', 'label']) {
      final got = _pull(op, k);
      if (got != null) return got;
    }

    // 2) meta-like maps
    Map<String, dynamic>? _meta(dynamic obj) {
      final tryKeys = ['meta', 'metadata', 'extras', 'extra'];
      for (final k in tryKeys) {
        try {
          final m = (obj as dynamic).toJson?.call()?[k];
          if (m is Map) {
            return m.map((kk, vv) => MapEntry(kk.toString(), vv));
          }
        } catch (_) {}
        try {
          final m = (obj as dynamic).$k;
          if (m is Map) {
            return m.map((kk, vv) => MapEntry(kk.toString(), vv));
          }
        } catch (_) {}
      }
      return null;
    }

    final m = _meta(op);
    if (m != null) {
      for (final k in ['customTitle', 'title', 'name', 'sessionName', 'label']) {
        final v = m[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    }

    return null;
  }

  /// Returns the display title: DB/record override ➜ local cache ➜ default.
  String _titleFor(OperationRecord op) {
    final fromOp = _getTitleFromOp(op);
    if (fromOp != null) return fromOp;
    final local = _customTitles[op.id];
    if (local != null && local.trim().isNotEmpty) return local;
    return op.displayTitle;
  }

  /// Attempts to persist the custom title to the underlying repository / database.
  /// Tries several common method names dynamically; falls back to storing inside
  /// operation metadata if the repo exposes an "updateOperation" or similar.
  Future<bool> _persistTitleToRepo(OperationRecord op, String newTitle) async {
    final anyRepo = repo as dynamic;

    // 1) Try explicit repo methods that might exist.
    final candidates = [
      'setCustomTitle',
      'updateTitle',
      'renameOperation',
      'rename',
      'updateOperationTitle',
    ];
    for (final method in candidates) {
      try {
        final fn = anyRepo?.$method;
        if (fn != null) {
          final result = await fn.call(op.id, newTitle);
          if (result == true || result == null) return true;
        }
      } catch (_) {}
    }

    // 2) Try to update an operation via a generic "updateOperation" style method.
    // We write to a common key in metadata: "customTitle".
    Map<String, dynamic> _metaOf(OperationRecord op) {
      // best-effort: extract the meta map, otherwise create one
      try {
        final tj = (op as dynamic).toJson?.call();
        if (tj is Map) {
          for (final k in ['meta', 'metadata', 'extras', 'extra']) {
            final m = tj[k];
            if (m is Map) {
              return m.map((kk, vv) => MapEntry(kk.toString(), vv));
            }
          }
        }
      } catch (_) {}
      return <String, dynamic>{};
    }

    final meta = _metaOf(op);
    meta['customTitle'] = newTitle;

    // Try different update entry points in the repo.
    final updateMapCandidates = [
      // (id, map)
      (String method) async {
        try {
          final fn = anyRepo?.$method;
          if (fn != null) {
            final res = await fn.call(op.id, {'meta': meta, 'customTitle': newTitle, 'title': newTitle});
            if (res == true || res == null) return true;
          }
        } catch (_) {}
        return false;
      },
      // (map) with an embedded id
      (String method) async {
        try {
          final fn = anyRepo?.$method;
          if (fn != null) {
            final res = await fn.call({
              'id': op.id,
              'meta': meta,
              'customTitle': newTitle,
              'title': newTitle,
            });
            if (res == true || res == null) return true;
          }
        } catch (_) {}
        return false;
      },
    ];

    for (final tryCall in updateMapCandidates) {
      for (final method in ['updateOperation', 'patchOperation', 'saveOperation', 'upsertOperation', 'replaceOperation']) {
        if (await tryCall(method) == true) return true;
      }
    }

    // 3) Try to replace the whole object if repo has a "replace"/"upsert" that accepts an OperationRecord.
    try {
      dynamic updatedOp = op;
      // If the model has copyWith, prefer it.
      try {
        final copyWith = (op as dynamic).copyWith;
        if (copyWith != null) {
          // attempt named params meta/title variants
          try {
            updatedOp = copyWith(meta: {...meta}, title: newTitle, customTitle: newTitle);
          } catch (_) {
            try {
              updatedOp = copyWith(meta: {...meta}, title: newTitle);
            } catch (_) {
              try {
                updatedOp = copyWith(meta: {...meta});
              } catch (_) {}
            }
          }
        }
      } catch (_) {}

      // Or try to set properties directly (no-op if immutable).
      try {
        (updatedOp as dynamic).meta = {...meta};
      } catch (_) {}
      try {
        (updatedOp as dynamic).title = newTitle;
      } catch (_) {}
      try {
        (updatedOp as dynamic).customTitle = newTitle;
      } catch (_) {}

      // Now call repo replace-like methods.
      for (final method in ['replace', 'upsert', 'save', 'put']) {
        try {
          final fn = anyRepo?.$method;
          if (fn != null) {
            final res = await fn.call(updatedOp);
            if (res == true || res == null) return true;
          }
        } catch (_) {}
      }
    } catch (_) {}

    // If everything failed, return false so caller can show a fallback message.
    return false;
  }

  // Keeps repo order; only filters items
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

  // Current selected among filtered, fallback to first filtered
  OperationRecord? _currentSelected(List<OperationRecord> ops) {
    if (ops.isEmpty) return null;
    final fallback = ops.first;
    return (_selectedOpId == null)
        ? fallback
        : (ops.firstWhere((o) => o.id == _selectedOpId, orElse: () => fallback));
  }

  // Rename dialog (order unaffected; only title changes)
  Future<void> _promptRename(OperationRecord? current) async {
    if (current == null) return;
    final cs = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: _titleFor(current));

    Future<void> _performRename() async {
      final txt = controller.text.trim();
      if (txt.isEmpty) return;

      // Update local cache immediately for snappy UX
      setState(() => _customTitles[current.id] = txt);
      await _saveTitles();

      // Try to persist to repo/db
      final ok = await _persistTitleToRepo(current, txt);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? t.analytics_renameSaved : t.analytics_renameFailed)),
      );

      // Force refresh UI (in case repo pushes newer data)
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
            await _performRename();
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
              await _performRename();
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

  // ----------------- Helpers to extract target + intended use (robust) -----------------
  double? _extractTargetMc(OperationRecord op) {
    // Try direct numeric fields on the record
    double? _tryNumField(String name) {
      try {
        final dyn = op as dynamic;
        final v = dyn.toJson?.call()?[name];
        if (v is num) return v.toDouble();
      } catch (_) {}
      try {
        final dyn = op as dynamic;
        final v = (dyn as dynamic).noSuchMethod; // noop to keep analyzer calm
      } catch (_) {}
      try {
        final dyn = op as dynamic;
        final v = (dyn as dynamic).targetMc as double?;
        if (name == 'targetMc' && v != null) return v;
      } catch (_) {}
      try {
        final dyn = op as dynamic;
        if (name == 'target') {
          final v = (dyn as dynamic).target as double?;
          if (v != null) return v;
        }
      } catch (_) {}
      try {
        final dyn = op as dynamic;
        if (name == 'targetMoisture') {
          final v = (dyn as dynamic).targetMoisture as double?;
          if (v != null) return v;
        }
      } catch (_) {}
      try {
        final dyn = op as dynamic;
        if (name == 'targetMoistureContent') {
          final v = (dyn as dynamic).targetMoistureContent as double?;
          if (v != null) return v;
        }
      } catch (_) {}
      try {
        final dyn = op as dynamic;
        if (name == 'target_mc') {
          final v = (dyn as dynamic).target_mc as double?;
          if (v != null) return v;
        }
      } catch (_) {}
      return null;
    }

    for (final key in [
      'targetMc',
      'target',
      'targetMoisture',
      'targetMoistureContent',
      'target_mc'
    ]) {
      final got = _tryNumField(key);
      if (got != null) return got;
    }

    // Try metadata-style maps
    double? _fromMap(Map m) {
      for (final key in [
        'targetMc',
        'target_mc',
        'target',
        'targetMoisture',
        'targetMoistureContent'
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

    Map<String, dynamic>? _getMap(dynamic maybe) {
      if (maybe is Map) {
        return maybe.map((k, v) => MapEntry(k.toString(), v));
      }
      return null;
    }

    try {
      final dyn = op as dynamic;
      for (final key in ['meta', 'metadata', 'extras', 'extra']) {
        try {
          final m = _getMap((dyn as dynamic).toJson?.call()?[key]);
          final got = (m == null) ? null : _fromMap(m);
          if (got != null) return got;
        } catch (_) {}
        try {
          final m = _getMap((dyn as dynamic).meta);
          final got = (m == null) ? null : _fromMap(m);
          if (got != null) return got;
        } catch (_) {}
      }
    } catch (_) {}

    // Fallback: use the minimum measured moisture (rough proxy)
    if (op.readings.isNotEmpty) {
      return op.readings.map((e) => e.value).reduce((a, b) => a < b ? a : b);
    }
    return null;
  }

  String _extractIntendedUse(OperationRecord op, double? targetMc) {
    // Try direct string fields first
    String? _tryStrField(String name) {
      try {
        final dyn = op as dynamic;
        final v = dyn.toJson?.call()?[name];
        if (v is String && v.trim().isNotEmpty) return v;
      } catch (_) {}
      try {
        final dyn = op as dynamic;
        switch (name) {
          case 'intendedUse':
            final v = (dyn as dynamic).intendedUse as String?;
            if (v != null && v.trim().isNotEmpty) return v;
            break;
          case 'intended':
            final v = (dyn as dynamic).intended as String?;
            if (v != null && v.trim().isNotEmpty) return v;
            break;
          case 'purpose':
            final v = (dyn as dynamic).purpose as String?;
            if (v != null && v.trim().isNotEmpty) return v;
            break;
          case 'targetTip':
            final v = (dyn as dynamic).targetTip as String?;
            if (v != null && v.trim().isNotEmpty) return v;
            break;
          case 'tip':
            final v = (dyn as dynamic).tip as String?;
            if (v != null && v.trim().isNotEmpty) return v;
            break;
          case 'targetLabel':
            final v = (dyn as dynamic).targetLabel as String?;
            if (v != null && v.trim().isNotEmpty) return v;
            break;
        }
      } catch (_) {}
      return null;
    }

    for (final key in [
      'intendedUse',
      'intended',
      'purpose',
      'targetTip',
      'tip',
      'targetLabel'
    ]) {
      final got = _tryStrField(key);
      if (got != null) return got;
    }

    // Map-like metadata
    String? _fromMap(Map m) {
      for (final key in [
        'intendedUse',
        'intended',
        'purpose',
        'targetTip',
        'tip',
        'targetLabel'
      ]) {
        final v = m[key];
        if (v is String && v.trim().isNotEmpty) return v;
      }
      return null;
    }

    Map<String, dynamic>? _getMap(dynamic maybe) {
      if (maybe is Map) {
        return maybe.map((k, v) => MapEntry(k.toString(), v));
      }
      return null;
    }

    try {
      final dyn = op as dynamic;
      for (final key in ['meta', 'metadata', 'extras', 'extra']) {
        try {
          final m = _getMap((dyn as dynamic).toJson?.call()?[key]);
          final got = (m == null) ? null : _fromMap(m);
          if (got != null) return got;
        } catch (_) {}
        try {
          final m = _getMap((dyn as dynamic).meta);
          final got = (m == null) ? null : _fromMap(m);
          if (got != null) return got;
        } catch (_) {}
      }
    } catch (_) {}

    // Derive from target MC (matches Automation guidance)
    final mc = targetMc;
    if (mc == null) return '—';
    if (mc <= 9.5) return 'For long term seed storage';
    if (mc <= 11.5) return 'For medium-term storage';
    if (mc <= 12.5) return 'For short-term milling';
    if (mc <= 14.0) return 'For immediate milling';
    return '—';
  }

  void _openExportSheet({
    required BuildContext context,
    required OperationRecord? current,
    required List<OperationRecord> all,
  }) {
    final selectedIds = <String>{if (current != null) current.id};
    bool pickSpecific = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final t = AppLocalizations.of(ctx)!;
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
                              ? all.where((o) => selectedIds.contains(o.id)).toList()
                              : (current == null ? <OperationRecord>[] : [current]);
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
          build: (pw.Context c) => pw.Padding(
            padding: const pw.EdgeInsets.all(24),
            child: pw.Column(
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
                pw.Text(_titleFor(op), style: const pw.TextStyle(fontSize: 12)),
                pw.SizedBox(height: 14),
                _pdfSummary(op, t),
                pw.SizedBox(height: 16),
                pw.Text(
                  t.analytics_environmentIfAvailable,
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                _pdfEnvStats(op, t),
                pw.SizedBox(height: 16),
                pw.Text(
                  t.analytics_notes,
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  t.analytics_notesBody,
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      );
    }

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename:
          'NiceRice_${DateTime.now().toIso8601String().replaceAll(":", "-")}.pdf',
    );
  }

  pw.Widget _pdfSummary(OperationRecord op, AppLocalizations t) {
    // Use same extractors so PDF matches UI
    final targetMc = _extractTargetMc(op);
    final intended = _extractIntendedUse(op, targetMc);

    final target = targetMc == null ? '—' : '${targetMc.toStringAsFixed(1)}%';

    String preset = '—';
    try {
      final d = (op as dynamic);
      preset = (d.presetLabel ?? d.preset ?? '—').toString();
    } catch (_) {}

    final dur = op.duration;
    final durText = dur == null
        ? '—'
        : '${dur.inHours}h ${dur.inMinutes.remainder(60)}m ${dur.inSeconds.remainder(60)}s';

    final estLoss = _estimateLossForPdf(op, t);

    return pw.Table(
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(3),
      },
      children: [
        _row(t.analytics_targetMoistureContent, target),
        _row(t.analytics_presetSelected, preset),
        _row(t.analytics_intendedUse, intended),
        _row(t.analytics_estimatedMoistureLoss, estLoss),
        _row(t.analytics_started, DateFormat('MMM d, HH:mm:ss').format(op.startedAt)),
        _row(
          t.analytics_ended,
          op.endedAt == null
              ? '—'
              : DateFormat('MMM d, HH:mm:ss').format(op.endedAt!),
        ),
        _row(t.analytics_durationInitCooldown, durText),
      ],
    );
  }

  pw.TableRow _row(String k, String v) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 6),
          child: pw.Text(k, style: const pw.TextStyle(fontSize: 11)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 6),
          child: pw.Text(
            v,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
        ),
      ],
    );
  }

  String _estimateLossForPdf(OperationRecord op, AppLocalizations t) {
    if (op.readings.isEmpty) return t.analytics_estDefault;
    final vals = op.readings.map((e) => e.value).toList();
    final loss = (vals.first - vals.last).abs();
    if (loss == 0) return t.analytics_estDefault;
    return '${loss.toStringAsFixed(1)}% ${t.analytics_estAbbrev}';
    // ex: "4.2% (est.)"
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
        tMin = tv.reduce((a, b) => a < b ? a : b);
        tMax = tv.reduce((a, b) => a > b ? a : b);
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
        hMin = hv.reduce((a, b) => a < b ? a : b);
        hMax = hv.reduce((a, b) => a > b ? a : b);
      }
    } catch (_) {}

    final rows = <pw.TableRow>[];

    if (tAvg != null) {
      rows.add(
        _row(
          t.analytics_temperatureAvgRange,
          '${tAvg!.toStringAsFixed(1)}°C • '
          '${(tMin ?? tAvg)!.toStringAsFixed(1)}–'
          '${(tMax ?? tAvg)!.toStringAsFixed(1)}°C',
        ),
      );
    }

    if (hAvg != null) {
      rows.add(
        _row(
          t.analytics_humidityAvgRange,
          '${hAvg!.toStringAsFixed(1)}% • '
          '${(hMin ?? hAvg)!.toStringAsFixed(1)}–'
          '${(hMax ?? hAvg)!.toStringAsFixed(1)}%',
        ),
      );
    }

    if (rows.isEmpty) {
      rows.add(_row(t.analytics_environment, t.analytics_noEnvData));
    }

    return pw.Table(children: rows);
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

      // Semi-transparent FAB (still colored), readable background
      floatingActionButton: (repo.operations.isEmpty)
          ? null
          : Theme(
              data: Theme.of(context).copyWith(
                floatingActionButtonTheme: FloatingActionButtonThemeData(
                  backgroundColor:
                      Theme.of(context).colorScheme.primary.withOpacity(0.22),
                  foregroundColor:
                      Theme.of(context).colorScheme.onPrimaryContainer,
                  elevation: 0,
                ),
                splashColor:
                    Theme.of(context).colorScheme.primary.withOpacity(0.18),
                highlightColor:
                    Theme.of(context).colorScheme.primary.withOpacity(0.12),
              ),
              child: FloatingActionButton.extended(
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
            }) {
              return GoogleFonts.poppins(
                fontSize: size,
                fontWeight: w,
                color: c ?? cs.onSurface,
                height: h,
                decoration: d,
              );
            }

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
                            message: t.analytics_emptyHistory,
                            textStyle: txt(
                              size: 14 * scale,
                              w: FontWeight.w500,
                              c: cs.onSurface.withOpacity(0.85),
                            ),
                          )
                        else ...[
                          // ───────── Operation picker with FILTER + RENAME ─────────
                          Card(
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: (12 * scale).clamp(10, 16),
                                vertical: (12 * scale).clamp(10, 16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // FILTER BUTTONS (rounded with borders)
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

                                  // Session dropdown + rename button
                                  if (filtered.isEmpty)
                                    _EmptyState(
                                      message: t.analytics_noSessionsForFilter,
                                      textStyle: txt(
                                        size: (14 * scale).clamp(12, 18),
                                        w: FontWeight.w500,
                                        c: cs.onSurface.withOpacity(0.8),
                                      ),
                                      height: (110 * scale).clamp(90, 140).toDouble(),
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
                                          width: (10 * scale).clamp(8, 14).toDouble(),
                                        ),
                                        Expanded(
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              value: (selected ?? filtered.first).id,
                                              isExpanded: true,
                                              iconEnabledColor: context.brand,
                                              items: filtered
                                                  .map(
                                                    (op) => DropdownMenuItem(
                                                      value: op.id,
                                                      child: Text(
                                                        _titleFor(op),
                                                        overflow: TextOverflow.ellipsis,
                                                        style: txt(
                                                          size: (14 * scale).clamp(12, 18),
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
                                        const SizedBox(width: 8),
                                        Tooltip(
                                          message: t.tooltip_renameSession,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(10),
                                            onTap: () => _promptRename(selected),
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

                          // ───────── Graph (kept) ─────────
                          _SectionCard(
                            title: t.analytics_tempHumOverview,
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
                                message: t.analytics_noEnvDataForSession,
                                textStyle: txt(
                                  size: (14 * scale).clamp(12, 18),
                                  w: FontWeight.w500,
                                  c: cs.onSurface.withOpacity(0.85),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // (Your Info footer class remains below; not shown here)

                          const SizedBox(height: 12),

                          // ───────── Interpretation (headline reflects data) ─────────
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

                          // ───────── Session Summary (Intended Use derived/fetched) ─────────
                          if (selected != null)
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
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: textStyle,
        ),
      ),
    );
  }
}

/// ----------------------- Filter buttons UI (rounded w/ borders) ----------------------
class _FilterButtonsRow extends StatelessWidget {
  final _FilterRange value;
  final ValueChanged<_FilterRange> onChanged;

  const _FilterButtonsRow({
    required this.value,
    required this.onChanged,
  });

  Widget _btn(BuildContext context, String label, _FilterRange me) {
    final cs = Theme.of(context).colorScheme;
    final selected = value == me;

    return Expanded(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(), // fully rounded
          side: BorderSide(color: selected ? cs.primary : cs.outline),
          backgroundColor:
              selected ? cs.primary.withOpacity(0.10) : Colors.transparent,
          foregroundColor: selected ? cs.primary : cs.onSurface,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        ),
        onPressed: () => onChanged(me),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    const gap = SizedBox(width: 6);
    return Row(
      children: [
        _btn(context, t.filters_today, _FilterRange.today),
        gap,
        _btn(context, t.filters_yesterday, _FilterRange.yesterday),
        gap,
        _btn(context, t.filters_last3, _FilterRange.last3),
        gap,
        _btn(context, t.filters_last7, _FilterRange.last7),
      ],
    );
  }
}

/// ------------ Top tiles (kept class for compatibility; unused in UI) ------------
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
    final t = AppLocalizations.of(context)!;

    TextStyle tS({double? size, FontWeight? w}) => GoogleFonts.poppins(
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
        width: width,
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
                style: tS(size: 18, w: FontWeight.w800),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(label, style: tS(size: 11, w: FontWeight.w600)),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final gap = 12.0;
        final tileW = (c.maxWidth - gap * 2) / 3;
        return Row(
          children: [
            tile(t.analytics_average, "${avg.toStringAsFixed(1)}%", Icons.timeline_outlined, tileW),
            SizedBox(width: gap),
            tile(t.analytics_min, "${minV.toStringAsFixed(1)}%", Icons.trending_down_outlined, tileW),
            SizedBox(width: gap),
            tile(t.analytics_max, "${maxV.toStringAsFixed(1)}%", Icons.trending_up_outlined, tileW),
          ],
        );
      },
    );
  }
}

/// ------------ Card 1: Temperature & Humidity Overview ------------
class _EnvChart extends StatelessWidget {
  final List<MoistureReading>? temps; // uses your existing reading type
  final List<MoistureReading>? rhs; // uses your existing reading type
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
    List<MoistureReading>? temps;
    List<MoistureReading>? rhs;

    // attempt: temps
    try {
      temps = (op as dynamic).temps as List<MoistureReading>?;
    } catch (_) {
      try {
        temps = (op as dynamic).temperatureReadings as List<MoistureReading>?;
      } catch (_) {
        temps = null;
      }
    }
    // attempt: rh
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
    final cs = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context)!;

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

    // use earliest timestamp to align series
    final start =
        (temps!.first.t.isBefore(rhs!.first.t) ? temps!.first.t : rhs!.first.t);

    List<FlSpot> toSpots(List<MoistureReading> list) =>
        list
            .map((r) => FlSpot(r.t.difference(start).inSeconds.toDouble(), r.value))
            .toList();

    final tempSpots = toSpots(temps!);
    final rhSpots = toSpots(rhs!);

    double minY(Iterable<double> v) => v.reduce((a, b) => a < b ? a : b);
    double maxY(Iterable<double> v) => v.reduce((a, b) => a > b ? a : b);

    final allTempVals = temps!.map((e) => e.value);
    final allRhVals = rhs!.map((e) => e.value);

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

    TextStyle tS(double sz, [FontWeight? w]) =>
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
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: (xMax - xMin) / 4.0,
                    getTitlesWidget: (v, m) => Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(xLabel(v), style: tS(11)),
                    ),
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
                    getTitlesWidget: (v, m) =>
                        Text(v.toStringAsFixed(0), style: tS(11)),
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
                    color:
                        Theme.of(context).colorScheme.primary.withOpacity(0.18),
                  ),
                ),
              ],
            ),
          ),
          // Humidity (right axis overlay)
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
                  topTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(
                    axisNameWidget: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('% RH', style: tS(10)),
                    ),
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      interval: ((hMax - hMin) / 5).clamp(1, 100).toDouble(),
                      getTitlesWidget: (v, m) =>
                          Text(v.toStringAsFixed(0), style: tS(11)),
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

  List<Widget> _moistureBullets(
    BuildContext context,
    OperationRecord op,
  ) {
    final cs = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context)!;

    TextStyle s() => GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: cs.onSurface,
        );

    final state = context.findAncestorStateOfType<_AnalyticsPageState>();
    final targetMc = state?._extractTargetMc(op);
    final intended = state?._extractIntendedUse(op, targetMc);

    String initial = '—';
    final target = targetMc == null ? '—' : '${targetMc.toStringAsFixed(1)}%';
    String estLoss = '—';

    if (op.readings.isNotEmpty) {
      final first = op.readings.first.value;
      final last = op.readings.last.value;
      initial = '${first.toStringAsFixed(1)}%';
      final loss = (first - last).abs();
      estLoss = '${loss.toStringAsFixed(1)}%';
    }

    Widget bullet(String label, String value) {
      return Padding(
        padding: EdgeInsets.only(bottom: bulletGap),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('• '),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: s(),
                  children: [
                    TextSpan(
                      text: '$label: ',
                      style: s().copyWith(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: value),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return [
      bullet(t.analytics_initialMoisture, initial),
      bullet(t.analytics_targetMoisture, target),
      bullet(t.analytics_estimatedMoistureLoss, estLoss),
      if (intended != null && intended != '—')
        bullet(t.analytics_intendedUse, intended),
    ];
  }

  // Headline based on target-crossing time if available; else first↦last
  String _headlineFromData(BuildContext context, OperationRecord op, {double? targetMc}) {
    final t = AppLocalizations.of(context)!;

    final readings = op.readings;
    if (readings.length < 2) return t.analytics_notEnoughData;

    final first = readings.first;
    final last = readings.last;

    // Use target crossing when we have a target
    DateTime endTimeForHeadline = last.t;
    double endValueForHeadline = last.value;

    if (targetMc != null) {
      final decreasing = last.value <= first.value;
      if (decreasing) {
        for (final r in readings) {
          if (r.value <= targetMc) {
            endTimeForHeadline = r.t;
            endValueForHeadline = r.value;
            break;
          }
        }
      } else {
        for (final r in readings) {
          if (r.value >= targetMc) {
            endTimeForHeadline = r.t;
            endValueForHeadline = r.value;
            break;
          }
        }
      }
    }

    final secs = endTimeForHeadline.difference(first.t).inSeconds;
    String fmtDur() {
      if (secs < 60) return '${secs}s';
      final m = secs ~/ 60;
      final s = secs % 60;
      if (m < 60) return '${m}m${s > 0 ? ' ${s}s' : ''}';
      final h = m ~/ 60;
      final mm = m % 60;
      return '${h}h ${mm}m';
    }

    final a = first.value.toStringAsFixed(1);
    final b = endValueForHeadline.toStringAsFixed(1);

    if (endValueForHeadline < first.value) {
      return t.analytics_mcDropped(a, b, fmtDur());
    } else if (endValueForHeadline > first.value) {
      return t.analytics_mcRose(a, b, fmtDur());
    } else {
      return t.analytics_mcStayed(a, fmtDur());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (op == null) return fallback;
    if (op!.readings.isEmpty) return fallback;

    final cs = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context)!;

    TextStyle ts(double sz, {FontWeight? w, Color? c}) => GoogleFonts.poppins(
          fontSize: sz,
          fontWeight: w,
          color: c ?? cs.onSurface,
        );

    final state = context.findAncestorStateOfType<_AnalyticsPageState>();
    final targetMc = state?._extractTargetMc(op!);

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
                  _headlineFromData(context, op!, targetMc: targetMc),
                  style: ts(14, w: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._moistureBullets(context, op!),
        ],
      ),
    );
  }
}

/// ------------ Card 3: Session Summary ------------
class _SessionSummaryCard extends StatelessWidget {
  final OperationRecord op;
  final double titleSize;

  const _SessionSummaryCard({
    required this.op,
    required this.titleSize,
  });

  String _fmtTime(DateTime dt) => DateFormat('MMM d, HH:mm:ss').format(dt);

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_AnalyticsPageState>();
    final cs = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context)!;

    TextStyle ts(double sz, {FontWeight? w, Color? c}) => GoogleFonts.poppins(
          fontSize: sz,
          fontWeight: w,
          color: c ?? cs.onSurface,
        );

    final targetMc = state?._extractTargetMc(op);
    final intended = state?._extractIntendedUse(op, targetMc) ?? '—';

    final dur = op.duration;
    final durText = (dur == null)
        ? '—'
        : '${dur.inHours > 0 ? '${dur.inHours}h ' : ''}'
            '${dur.inMinutes.remainder(60).toString().padLeft(2, '0')}m '
            '${dur.inSeconds.remainder(60).toString().padLeft(2, '0')}s';

    return _SectionCard(
      title: t.analytics_sessionSummary,
      titleStyle: ts(titleSize, w: FontWeight.w700, c: context.brand),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(t.analytics_intendedUse, intended, ts(13)),
          const Divider(height: 20),
          _row(t.analytics_start, _fmtTime(op.startedAt), ts(13)),
          _row(t.analytics_end, op.endedAt == null ? '—' : _fmtTime(op.endedAt!), ts(13)),
          _row(t.analytics_duration, durText, ts(13)),
        ],
      ),
    );
  }

  Widget _row(String label, String value, TextStyle vStyle) {
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

/// ------------ Your original Info footer ------------
/// (Kept for completeness; not shown in UI after the graph)
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
    final t = AppLocalizations.of(context)!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          '${t.analytics_started}: $start • ${t.analytics_ended}: $end • ${t.analytics_points}: $points',
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

  List<Widget> _moistureBullets(BuildContext context, OperationRecord op) {
    final cs = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context)!;

    TextStyle s() => GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: cs.onSurface,
        );

    final state = context.findAncestorStateOfType<_AnalyticsPageState>();
    final targetMc = state?._extractTargetMc(op);
    final intended = state?._extractIntendedUse(op, targetMc);

    String initial = '—';
    final target = targetMc == null ? '—' : '${targetMc.toStringAsFixed(1)}%';
    String estLoss = '—';

    if (op.readings.isNotEmpty) {
      final first = op.readings.first.value;
      final last = op.readings.last.value;
      initial = '${first.toStringAsFixed(1)}%';
      final loss = (first - last).abs();
      estLoss = '${loss.toStringAsFixed(1)}%';
    }

    Widget bullet(String label, String value) {
      return Padding(
        padding: EdgeInsets.only(bottom: bulletGap),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('• '),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: s(),
                  children: [
                    TextSpan(
                      text: '$label: ',
                      style: s().copyWith(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: value),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return [
      bullet(t.analytics_initialMoisture, initial),
      bullet(t.analytics_targetMoisture, target),
      bullet(t.analytics_estimatedMoistureLoss, estLoss),
      if (intended != null && intended != '—')
        bullet(t.analytics_intendedUse, intended),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context)!;

    TextStyle ts(double sz, {FontWeight? w, Color? c}) => GoogleFonts.poppins(
          fontSize: sz,
          fontWeight: w,
          color: c ?? cs.onSurface,
        );

    if (op == null || op!.readings.isEmpty) {
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

    final analysis = _analyzeOperation(op!);
    final statusColor = switch (analysis.status) {
      _MoistureStatus.tooDry => Colors.amber,
      _MoistureStatus.ok => context.brand,
      _MoistureStatus.tooWet => Colors.red,
    };

    return _SectionCard(
      title: t.analytics_interpretation,
      titleStyle: ts(titleSize, w: FontWeight.w700),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.agriculture_rounded, color: statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  analysis.headline, // kept original fallback copy
                  style: ts(14, w: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._moistureBullets(context, op!),
          const SizedBox(height: 8),
          Text(analysis.recommendation, style: ts(13, w: FontWeight.w700)),
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
      : '${dur.inMinutes.remainder(60).toString().padLeft(2, '0')}:'
        '${dur.inSeconds.remainder(60).toString().padLeft(2, '0')}';

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
