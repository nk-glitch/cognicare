import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Handles location for patients (share to Firestore) and caretakers (read patient location).
/// Uses Firestore so caretaker on a different device can see patient location.
class LocationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _locationCollection = 'patient_locations';

  Future<bool> requestPermission() async {
    try {
      PermissionStatus status = await Permission.location.request();
      if (status.isGranted) return true;
      if (status.isDenied) {
        status = await Permission.location.request();
        return status.isGranted;
      }
      if (status.isPermanentlyDenied) {
        await openAppSettings();
        return false;
      }
    } catch (e) {
      print('Location permission error: $e');
    }
    return false;
  }

  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Timeout so GPS wait doesn't freeze the app. Low accuracy gets a fix faster (indoor/emulator).
  static const Duration _locationTimeout = Duration(seconds: 25);

  Future<Position?> getCurrentLocation() async {
    try {
      final serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) return null;
      final hasPermission = await requestPermission();
      if (!hasPermission) return null;
      // Use low accuracy first for faster fix (works better indoors / on emulator)
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      ).timeout(
        _locationTimeout,
        onTimeout: () {
          print('Location request timed out after ${_locationTimeout.inSeconds}s');
          throw Exception('Location timeout');
        },
      );
    } catch (e) {
      print('Error getting location: $e');
      return null;
    }
  }

  /// Patient: share current location to Firestore so caretakers can see it.
  /// Returns true if location was saved, false if unavailable or timed out.
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
      print('Location saved to Firestore for $userId: ${position.latitude}, ${position.longitude}');
      return true;
    } catch (e) {
      print('Error saving location to Firestore: $e');
      return false;
    }
  }

  /// Caretaker: get stored patient location from Firestore.
  Future<Map<String, dynamic>?> getStoredLocation(String patientId) async {
    try {
      final doc = await _firestore.collection(_locationCollection).doc(patientId).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        return {
          'latitude': (data['latitude'] as num).toDouble(),
          'longitude': (data['longitude'] as num).toDouble(),
          'accuracy': (data['accuracy'] as num?)?.toDouble() ?? 0.0,
          'timestamp': data['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        };
      }
    } catch (e) {
      print('Error getting stored location: $e');
    }
    return null;
  }

  /// Caretaker: listen to real-time patient location updates from Firestore.
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
        'timestamp': data['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      };
    });
  }
}
