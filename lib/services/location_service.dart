import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

/// Handles location for patients (share to Firestore) and caretakers (read patient location).
class LocationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _locationCollection = 'patient_locations';
  static const Duration _freshLocationMaxAge = Duration(minutes: 10);

  Future<bool> isLocationServiceEnabled() async {
    return Geolocator.isLocationServiceEnabled();
  }

  Future<LocationPermission?> _ensurePermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      print('Location permission denied');
      return null;
    }
    if (permission == LocationPermission.deniedForever) {
      print('Location permission permanently denied');
      await Geolocator.openAppSettings();
      return null;
    }
    return permission;
  }

  bool _isFresh(Position position) {
    final age = DateTime.now().difference(position.timestamp);
    return age <= _freshLocationMaxAge;
  }

  Future<Position> _tryGetCurrentPosition({
    required LocationAccuracy accuracy,
    required Duration timeLimit,
    bool forceAndroidLocationManager = false,
  }) async {
    return Geolocator.getCurrentPosition(
      desiredAccuracy: accuracy,
      timeLimit: timeLimit,
      forceAndroidLocationManager: forceAndroidLocationManager,
    );
  }

  Future<Position?> getCurrentLocation() async {
    try {
      final serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('Location services are disabled');
        return null;
      }

      final permission = await _ensurePermission();
      if (permission == null) return null;

      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && _isFresh(lastKnown)) {
        print('Using fresh cached location');
        return lastKnown;
      }

      final attempts = <({
        LocationAccuracy accuracy,
        Duration timeLimit,
        bool forceAndroidLocationManager,
      })>[
        (
          accuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 12),
          forceAndroidLocationManager: false,
        ),
        (
          accuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 8),
          forceAndroidLocationManager: false,
        ),
        (
          accuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 8),
          forceAndroidLocationManager: true,
        ),
      ];

      for (final attempt in attempts) {
        try {
          final position = await _tryGetCurrentPosition(
            accuracy: attempt.accuracy,
            timeLimit: attempt.timeLimit,
            forceAndroidLocationManager: attempt.forceAndroidLocationManager,
          );
          print(
            'Got location fix: ${position.latitude}, ${position.longitude}',
          );
          return position;
        } on TimeoutException catch (e) {
          print('Location attempt timed out: $e');
        } on LocationServiceDisabledException catch (e) {
          print('Location service disabled during fix: $e');
          return null;
        }
      }

      if (lastKnown != null) {
        final age = DateTime.now().difference(lastKnown.timestamp);
        print('Using stale cached location (${age.inMinutes} min old)');
        return lastKnown;
      }

      print('No location available after all attempts');
      return null;
    } catch (e) {
      print('Error getting location: $e');
      return null;
    }
  }

  Future<bool> shareLocation(String userId) async {
    try {
      final position = await getCurrentLocation();
      if (position == null) return false;

      final locationData = {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await _firestore.collection(_locationCollection).doc(userId).set(
            locationData,
            SetOptions(merge: true),
          );
      print(
        'Location saved to Firestore for $userId: '
        '${position.latitude}, ${position.longitude}',
      );
      return true;
    } catch (e) {
      print('Error saving location to Firestore: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getStoredLocation(String patientId) async {
    try {
      final doc =
          await _firestore.collection(_locationCollection).doc(patientId).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        return {
          'latitude': (data['latitude'] as num).toDouble(),
          'longitude': (data['longitude'] as num).toDouble(),
          'accuracy': (data['accuracy'] as num?)?.toDouble() ?? 0.0,
          'timestamp':
              data['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        };
      }
    } catch (e) {
      print('Error getting stored location: $e');
    }
    return null;
  }

  Stream<Map<String, dynamic>?> listenToLocation(String patientId) {
    return _firestore
        .collection(_locationCollection)
        .doc(patientId)
        .snapshots()
        .map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      final data = snap.data()!;
      return {
        'latitude': (data['latitude'] as num).toDouble(),
        'longitude': (data['longitude'] as num).toDouble(),
        'accuracy': (data['accuracy'] as num?)?.toDouble() ?? 0.0,
        'timestamp':
            data['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      };
    });
  }
}
