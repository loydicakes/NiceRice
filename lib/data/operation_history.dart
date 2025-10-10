import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth, User;

import 'package:nice_rice/data/operation_models.dart';
import 'package:nice_rice/data/operation_persistence.dart';

class OperationHistory extends ChangeNotifier implements OperationRepository {
  OperationHistory._();
  static final OperationHistory instance = OperationHistory._();

  final List<OperationRecord> _ops = [];
  bool _loaded = false;
  StreamSubscription<List<OperationRecord>>? _cloudSub;
  StreamSubscription<User?>? _authSub;

  Future<void> ensureLoaded() async {
    if (_loaded) return;

    // Offline-first
    final local = await OperationPersistence.loadLocal();
    _replaceAll(local);

    // Watch cloud (or local fallback)
    _cloudSub = OperationPersistence.watchCloud().listen((ops) {
      _replaceAll(ops.isNotEmpty ? ops : local);
    });

    // Rewire when auth changes
    _authSub = FirebaseAuth.instance.authStateChanges().listen((_) async {
      await _cloudSub?.cancel();
      _cloudSub = OperationPersistence.watchCloud().listen((ops) {
        _replaceAll(ops);
      });
    });

    _loaded = true;
  }

  @override
  void dispose() {
    _cloudSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  // ——— API you can call from Automation ———
  String startOperation() {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    _ops.add(OperationRecord(id: id, startedAt: DateTime.now()));
    notifyListeners();
    return id;
  }

  void logReading(String opId, double moisture, {DateTime? at}) {
    final op = getById(opId);
    if (op == null) return;
    op.readings.add(MoistureReading(at ?? DateTime.now(), moisture));
    notifyListeners();
  }

  Future<OperationRecord?> endOperation(String opId) async {
    final op = getById(opId);
    if (op == null) return null;
    op.endedAt ??= DateTime.now();
    await OperationPersistence.save(op);  // persist
    notifyListeners();
    return op;
  }

  // ——— Repository ———
  @override
  UnmodifiableListView<OperationRecord> get operations =>
      UnmodifiableListView(_ops..sort((a, b) => b.startedAt.compareTo(a.startedAt)));

  @override
  OperationRecord? getById(String id) {
    for (final o in _ops) {
      if (o.id == id) return o;
    }
    return null;
  }

  // ——— internals ———
  void _replaceAll(List<OperationRecord> next) {
    next.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    _ops
      ..clear()
      ..addAll(next);
    notifyListeners();
  }
}
