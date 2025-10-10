import 'dart:collection';
import 'package:intl/intl.dart';

class MoistureReading {
  final DateTime t;
  final double value;
  const MoistureReading(this.t, this.value);

  Map<String, dynamic> toMap() => {'t': t.toIso8601String(), 'value': value};

  factory MoistureReading.fromMap(Map<String, dynamic> m) =>
      MoistureReading(DateTime.parse(m['t'] as String), (m['value'] as num).toDouble());
}

class OperationRecord {
  final String id;
  final DateTime startedAt;
  DateTime? endedAt;
  final List<MoistureReading> readings;

  OperationRecord({
    required this.id,
    required this.startedAt,
    List<MoistureReading>? readings,
  }) : readings = readings ?? [];

  Duration? get duration => endedAt == null ? null : endedAt!.difference(startedAt);

  String get displayTitle {
    final df = DateFormat('MMM d, HH:mm');
    final start = df.format(startedAt);
    final dur = duration == null
        ? ''
        : ' • ${duration!.inMinutes.remainder(60).toString().padLeft(2, '0')}:${duration!.inSeconds.remainder(60).toString().padLeft(2, '0')}';
    return 'Operation $start$dur';
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    'readings': readings.map((r) => r.toMap()).toList(),
  };

  factory OperationRecord.fromMap(Map<String, dynamic> m) => OperationRecord(
    id: m['id'] as String,
    startedAt: DateTime.parse(m['startedAt'] as String),
    readings: (m['readings'] as List)
        .map((e) => MoistureReading.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList(),
  )..endedAt = (m['endedAt'] != null ? DateTime.parse(m['endedAt'] as String) : null);
}

abstract class OperationRepository {
  UnmodifiableListView<OperationRecord> get operations;
  OperationRecord? getById(String id);
}
