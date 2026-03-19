import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';

/// Manages geofence data in Firestore and provides distance calculations.
///
/// Firestore structure:
///   geofences/{patientId} → { patientId, caretakerId, centerLat, centerLng,
///                             radiusMeters, label, isActive, updatedAt }
///   geofence_states/{patientId} → { isOutside, updatedAt }  (written by Cloud Function)
class GeofenceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _geofencesCollection = 'geofences';

  // ── Write ──────────────────────────────────────────────────────────────────

  Future<void> saveGeofence({
    required String patientId,
    required String caretakerId,
    required double centerLat,
    required double centerLng,
    required double radiusMeters,
    String label = 'Safe Zone',
    String? addressDisplay,
  }) async {
    await _firestore.collection(_geofencesCollection).doc(patientId).set({
      'patientId': patientId,
      'caretakerId': caretakerId,
      'centerLat': centerLat,
      'centerLng': centerLng,
      'radiusMeters': radiusMeters,
      'label': label,
      'addressDisplay': addressDisplay,
      'isActive': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> toggleGeofence(String patientId, {required bool isActive}) async {
    await _firestore
        .collection(_geofencesCollection)
        .doc(patientId)
        .update({'isActive': isActive});
  }

  Future<void> deleteGeofence(String patientId) async {
    await _firestore.collection(_geofencesCollection).doc(patientId).delete();
  }

  // ── Read ───────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getGeofence(String patientId) async {
    try {
      final doc = await _firestore
          .collection(_geofencesCollection)
          .doc(patientId)
          .get();
      if (!doc.exists || doc.data() == null) return null;
      return _parse(doc.data()!);
    } catch (e) {
      print('Error getting geofence: $e');
      return null;
    }
  }

  /// Real-time stream of geofence changes for a patient.
  Stream<Map<String, dynamic>?> listenToGeofence(String patientId) {
    return _firestore
        .collection(_geofencesCollection)
        .doc(patientId)
        .snapshots()
        .map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return _parse(snap.data()!);
    });
  }

  Map<String, dynamic> _parse(Map<String, dynamic> data) => {
    'patientId': data['patientId'] as String? ?? '',
    'caretakerId': data['caretakerId'] as String? ?? '',
    'centerLat': (data['centerLat'] as num).toDouble(),
    'centerLng': (data['centerLng'] as num).toDouble(),
    'radiusMeters': (data['radiusMeters'] as num).toDouble(),
    'label': data['label'] as String? ?? 'Safe Zone',
    'isActive': data['isActive'] as bool? ?? true,
    'addressDisplay': data['addressDisplay'] as String?,
  };

  // ── Distance ───────────────────────────────────────────────────────────────

  /// Haversine distance in metres between two WGS-84 coordinates.
  static double distanceInMeters(
      double lat1,
      double lng1,
      double lat2,
      double lng2,
      ) {
    const earthRadius = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) *
            cos(_toRad(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRad(double deg) => deg * pi / 180;

  /// Human-readable distance string.
  static String formatDistance(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '${meters.round()} m';
  }
}