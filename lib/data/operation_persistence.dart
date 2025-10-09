// lib/data/operation_persistence.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:nice_rice/pages/analytics/analytics.dart' show OperationRecord;

class OperationPersistence {
  static const _kLocalKey = 'operations';

  /// Save a finished operation.
  /// If logged in => Firestore; else => local SharedPreferences (JSON).
  static Future<void> save(OperationRecord op) async {
    final user = FirebaseAuth.instance.currentUser;
    debugPrint('PERSIST save: user=${user?.uid} opId=${op.id}');
    if (user != null) {
      await _saveToFirestore(user.uid, op);
    } else {
      await _saveToLocal(op);
    }
  }

  static Future<void> _saveToFirestore(String uid, OperationRecord op) async {
    try {
      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('operations')
          .doc(op.id);

      final data = op.toMap()
        ..addAll({
          // Helpful metadata to sort/see in console
          '_createdAt': FieldValue.serverTimestamp(),
          '_source': 'app', // marker to recognize app writes
        });

      await ref.set(data, SetOptions(merge: true));
      debugPrint('FIRESTORE WRITE OK: ${ref.path}');
    } catch (e, st) {
      debugPrint('FIRESTORE WRITE ERROR: $e\n$st');
      rethrow;
    }
  }

  static Future<void> _saveToLocal(OperationRecord op) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kLocalKey);
      final list = (raw == null || raw.isEmpty)
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(jsonDecode(raw) as List);

      // upsert by id
      final idx = list.indexWhere((m) => m['id'] == op.id);
      final map = op.toMap();
      if (idx >= 0) list[idx] = map; else list.add(map);

      await prefs.setString(_kLocalKey, jsonEncode(list));
      debugPrint('LOCAL SAVE OK: count=${list.length}');
    } catch (e, st) {
      debugPrint('LOCAL SAVE ERROR: $e\n$st');
      rethrow;
    }
  }

  /// Debug helper: list the current user's operations from Firestore.
  static Future<void> debugListCloud({int limit = 20}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    debugPrint('DEBUG LIST CLOUD uid=$uid');
    if (uid == null) {
      debugPrint('No user logged in.');
      return;
    }
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('operations')
        .orderBy('_createdAt', descending: true)
        .limit(limit)
        .get();

    debugPrint('CLOUD ops: ${snap.docs.length}');
    for (final d in snap.docs) {
      debugPrint(' • ${d.reference.path}  ${d.data()}');
    }
  }

  /// Debug helper: list all operations across users using a collection group.
  static Future<void> debugListAllOps({int limit = 20}) async {
    final snap = await FirebaseFirestore.instance
        .collectionGroup('operations')
        .orderBy('_createdAt', descending: true)
        .limit(limit)
        .get();

    debugPrint('CG ops: ${snap.docs.length}');
    for (final d in snap.docs) {
      debugPrint(' • ${d.reference.path}');
    }
  }

  /// Load locally saved operations (for offline history).
  static Future<List<OperationRecord>> loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLocalKey);
    if (raw == null || raw.isEmpty) return [];
    final list = List<Map<String, dynamic>>.from(jsonDecode(raw) as List);
    return list.map(OperationRecord.fromMap).toList();
  }
}
