// lib/data/operation_persistence.dart
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:nice_rice/data/operation_models.dart';

class OperationPersistence {
  static const _kLocalKey = 'operations';

  // Guards for one-time login sync per app session
  static bool _didAttachLoginSync = false;
  static bool _didRunLoginSync = false;

  static Future<void> save(OperationRecord op) async {
    final user = FirebaseAuth.instance.currentUser;
    debugPrint('PERSIST save: user=${user?.uid} opId=${op.id}');
    if (user != null) {
      await _saveToFirestore(user.uid, op);
    } else {
      await _saveToLocal(op);
    }
  }

  // ---------- Firestore ----------
  static Future<void> _saveToFirestore(String uid, OperationRecord op) async {
    try {
      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('operations')
          .doc(op.id);

      final data = op.toMap()
        ..addAll({
          '_createdAt': FieldValue.serverTimestamp(),
          '_source': 'app', 
        });

      await ref.set(data, SetOptions(merge: true));
      debugPrint('FIRESTORE WRITE OK: ${ref.path}');
    } catch (e, st) {
      debugPrint('🔥 FIRESTORE WRITE ERROR: $e\n$st');
      rethrow;
    }
  }

  // ---------- Local SharedPreferences ----------
  static Future<void> _saveToLocal(OperationRecord op) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kLocalKey);
      final list = (raw == null || raw.isEmpty)
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(jsonDecode(raw) as List);

      final idx = list.indexWhere((m) => m['id'] == op.id);
      final map = op.toMap();
      if (idx >= 0) {
        list[idx] = map;
      } else {
        list.add(map);
      }

      await prefs.setString(_kLocalKey, jsonEncode(list));
      debugPrint('💾 LOCAL SAVE OK: count=${list.length}');
    } catch (e, st) {
      debugPrint('❌ LOCAL SAVE ERROR: $e\n$st');
      rethrow;
    }
  }

  // ---------- Loaders ----------
  /// Loads locally saved operations (for offline history).
  static Future<List<OperationRecord>> loadLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kLocalKey);
      if (raw == null || raw.isEmpty) return [];
      final list = List<Map<String, dynamic>>.from(jsonDecode(raw) as List);
      return list.map(OperationRecord.fromMap).toList();
    } catch (e, st) {
      debugPrint('❌ LOCAL LOAD ERROR: $e\n$st');
      return [];
    }
  }

  /// Loads operations from Firestore once (not streaming).
  static Future<List<OperationRecord>> loadCloudOnce({int limit = 100}) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return [];
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('operations')
          .orderBy('startedAt', descending: true)
          .limit(limit)
          .get();

      return snap.docs
          .map((d) => OperationRecord.fromMap(Map<String, dynamic>.from(d.data())))
          .toList();
    } catch (e, st) {
      debugPrint('❌ FIRESTORE LOAD ERROR: $e\n$st');
      return [];
    }
  }

  /// Watches Firestore in real-time.
  /// Falls back to local (one-shot) when user not logged in.
  static Stream<List<OperationRecord>> watchCloud({int limit = 200}) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      // No user: stream local once, then close.
      return Stream.fromFuture(loadLocal());
    }

    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('operations')
        .orderBy('startedAt', descending: true)
        .limit(limit);

    return col.snapshots().map((qs) =>
        qs.docs.map((d) => OperationRecord.fromMap(Map<String, dynamic>.from(d.data()))).toList());
  }

  // ---------- One-time local → cloud sync on first login ----------

  /// Call this once (e.g., right after Firebase.initializeApp()).
  /// The first time a user logs in, local ops are migrated to that user's Firestore.
  static void attachOneTimeLoginSync({bool clearLocalAfter = true}) {
    if (_didAttachLoginSync) return;
    _didAttachLoginSync = true;

    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null || _didRunLoginSync) return;
      _didRunLoginSync = true;
      await syncLocalToCloudAndOptionallyClear(clearLocalAfter: clearLocalAfter);
    });
  }

  /// Performs the migration of local operations to Firestore for the current user.
  static Future<void> syncLocalToCloudAndOptionallyClear({
    bool clearLocalAfter = true,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final localOps = await loadLocal();
    if (localOps.isEmpty) return;

    debugPrint('🔄 Syncing ${localOps.length} local ops to cloud for uid=$uid');
    for (final op in localOps) {
      try {
        await _saveToFirestore(uid, op);
      } catch (e, st) {
        debugPrint('⚠️ Sync failed for ${op.id}: $e\n$st');
      }
    }

    if (clearLocalAfter) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kLocalKey);
      debugPrint('🧹 Cleared local operations after successful sync.');
    }
  }

  // ---------- Debug helpers ----------
  static Future<void> debugListCloud({int limit = 20}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    debugPrint('DEBUG LIST CLOUD uid=$uid');
    if (uid == null) {
      debugPrint('⚠️ No user logged in.');
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
}
