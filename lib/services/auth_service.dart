import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Auth state changes stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign up with email and password
  Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String phone,
    required String userType, // 'patient' or 'caretaker'
  }) async {
    try {
      print('DEBUG: Starting sign up for $email');

      // Try to create user
      UserCredential? userCredential;
      String? uid;

      try {
        userCredential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        uid = userCredential.user!.uid;
      } catch (pigeonError) {
        // If we get the Pigeon error, the user might actually be created
        if (pigeonError.toString().contains('PigeonUserDetails')) {
          print('DEBUG: Caught Pigeon error during signup, checking current user...');
          // Wait a moment for auth state to update
          await Future.delayed(const Duration(milliseconds: 500));

          // Check if user is now signed in (meaning signup succeeded)
          User? currentUser = _auth.currentUser;
          if (currentUser != null) {
            print('DEBUG: User created despite error: ${currentUser.uid}');
            uid = currentUser.uid;
          } else {
            print('DEBUG: User not created, re-throwing error');
            throw pigeonError;
          }
        } else {
          throw pigeonError;
        }
      }

      print('DEBUG: User created with UID: $uid');

      // Create user document in Firestore
      await _firestore.collection('users').doc(uid).set({
        'email': email,
        'firstName': firstName,
        'lastName': lastName,
        'phone': phone,
        'userType': userType,
        'createdAt': FieldValue.serverTimestamp(),
      });

      print('DEBUG: User document created in Firestore');

      // If patient, create patient document
      if (userType == 'patient') {
        await _firestore.collection('patients').doc(uid).set({
          'userId': uid,
          'address': '',
          'dateOfBirth': '',
          'emergencyContact': '',
          'emergencyContactNumber': '',
          'setupComplete': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        print('DEBUG: Patient document created');
      }

      // If caretaker, create caretaker document
      if (userType == 'caretaker') {
        await _firestore.collection('caretakers').doc(uid).set({
          'userId': uid,
          'patients': <String>[], // Explicitly typed empty array
          'createdAt': FieldValue.serverTimestamp(),
        });
        print('DEBUG: Caretaker document created');
      }

      return {
        'success': true,
        'uid': uid,
        'userType': userType,
      };
    } on FirebaseAuthException catch (e) {
      print('DEBUG: FirebaseAuthException during signup: ${e.code}');
      String message;
      switch (e.code) {
        case 'weak-password':
          message = 'The password is too weak.';
          break;
        case 'email-already-in-use':
          message = 'An account already exists for this email.';
          break;
        case 'invalid-email':
          message = 'The email address is invalid.';
          break;
        default:
          message = 'Sign up failed: ${e.message}';
      }
      return {'success': false, 'message': message};
    } catch (e, stackTrace) {
      print('DEBUG: General exception during signup: $e');
      print('DEBUG: Stack trace: $stackTrace');
      return {'success': false, 'message': 'An unexpected error occurred: $e'};
    }
  }

  // Sign in with email and password
  Future<Map<String, dynamic>> signIn({
    required String email,
    required String password,
  }) async {
    try {
      print('DEBUG: Starting sign in for $email');

      // Try to sign in
      UserCredential? userCredential;
      try {
        userCredential = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } catch (pigeonError) {
        // If we get the Pigeon error, the user is actually signed in
        // This is a known bug with Firebase Auth on emulators
        if (pigeonError.toString().contains('PigeonUserDetails')) {
          print('DEBUG: Caught Pigeon error, checking current user...');
          // Wait a moment for auth state to update
          await Future.delayed(const Duration(milliseconds: 500));

          // Check if user is now signed in
          User? currentUser = _auth.currentUser;
          if (currentUser != null) {
            print('DEBUG: User is signed in despite error: ${currentUser.uid}');
            // Create a fake UserCredential since the real one failed to deserialize
            userCredential = null; // We'll use currentUser instead
          } else {
            print('DEBUG: User not signed in after Pigeon error');
            throw pigeonError;
          }
        } else {
          throw pigeonError;
        }
      }

      print('DEBUG: Firebase auth successful');
      String uid = userCredential?.user?.uid ?? _auth.currentUser!.uid;
      print('DEBUG: User logged in with UID: $uid');

      // Get user data from Firestore using get() method
      final userDocRef = _firestore.collection('users').doc(uid);
      final userDocSnapshot = await userDocRef.get();

      print('DEBUG: User doc exists: ${userDocSnapshot.exists}');

      if (!userDocSnapshot.exists) {
        await signOut();
        return {'success': false, 'message': 'User data not found.'};
      }

      // Get the data as a map without casting
      final rawData = userDocSnapshot.data();
      print('DEBUG: Raw data type: ${rawData.runtimeType}');

      if (rawData == null) {
        await signOut();
        return {'success': false, 'message': 'User data is null.'};
      }

      // Manually build the userData map
      Map<String, dynamic> userData = {
        'email': rawData['email'] ?? email,
        'firstName': rawData['firstName'] ?? '',
        'lastName': rawData['lastName'] ?? '',
        'phone': rawData['phone'] ?? '',
        'userType': rawData['userType'] ?? 'patient',
      };

      print('DEBUG: User data retrieved: $userData');

      return {
        'success': true,
        'uid': uid,
        'userType': userData['userType'],
        'userData': userData,
      };
    } on FirebaseAuthException catch (e) {
      print('DEBUG: FirebaseAuthException: ${e.code} - ${e.message}');
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = 'No account found with this email.';
          break;
        case 'wrong-password':
          message = 'Incorrect password.';
          break;
        case 'invalid-email':
          message = 'The email address is invalid.';
          break;
        case 'user-disabled':
          message = 'This account has been disabled.';
          break;
        default:
          message = 'Login failed: ${e.message}';
      }
      return {'success': false, 'message': message};
    } catch (e, stackTrace) {
      print('DEBUG: General exception during sign in: $e');
      print('DEBUG: Stack trace: $stackTrace');
      return {'success': false, 'message': 'An unexpected error occurred: $e'};
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // Update patient account setup
  Future<Map<String, dynamic>> updatePatientSetup({
    required String userId,
    required String address,
    required String dateOfBirth,
    required String emergencyContact,
    required String emergencyContactNumber,
    required String phone,
  }) async {
    try {
      await _firestore.collection('patients').doc(userId).update({
        'address': address,
        'dateOfBirth': dateOfBirth,
        'emergencyContact': emergencyContact,
        'emergencyContactNumber': emergencyContactNumber,
        'setupComplete': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Also update phone in users collection
      await _firestore.collection('users').doc(userId).update({
        'phone': phone,
      });

      return {'success': true};
    } catch (e) {
      return {'success': false, 'message': 'Failed to update profile: $e'};
    }
  }

  // Get user data
  Future<Map<String, dynamic>?> getUserData(String userId) async {
    try {
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists && userDoc.data() != null) {
        final data = userDoc.data();
        Map<String, dynamic> result = {};
        if (data is Map) {
          data.forEach((key, value) {
            result[key.toString()] = value;
          });
        }
        return result;
      }
      return null;
    } catch (e) {
      print('Error getting user data: $e');
      return null;
    }
  }

  // Get patient data
  Future<Map<String, dynamic>?> getPatientData(String userId) async {
    try {
      DocumentSnapshot patientDoc = await _firestore.collection('patients').doc(userId).get();
      if (patientDoc.exists && patientDoc.data() != null) {
        final data = patientDoc.data();
        Map<String, dynamic> result = {};
        if (data is Map) {
          data.forEach((key, value) {
            result[key.toString()] = value;
          });
        }
        return result;
      }
      return null;
    } catch (e) {
      print('Error getting patient data: $e');
      return null;
    }
  }

  // Get caretaker data
  Future<Map<String, dynamic>?> getCaretakerData(String userId) async {
    try {
      DocumentSnapshot caretakerDoc = await _firestore.collection('caretakers').doc(userId).get();
      if (caretakerDoc.exists && caretakerDoc.data() != null) {
        final data = caretakerDoc.data();
        Map<String, dynamic> result = {};
        if (data is Map) {
          data.forEach((key, value) {
            // Handle patients array specifically
            if (key == 'patients' && value is List) {
              result[key.toString()] = List<String>.from(value.map((e) => e.toString()));
            } else {
              result[key.toString()] = value;
            }
          });
        }
        return result;
      }
      return null;
    } catch (e) {
      print('Error getting caretaker data: $e');
      return null;
    }
  }

  // Reset password
  Future<Map<String, dynamic>> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return {
        'success': true,
        'message': 'Password reset email sent. Please check your inbox.',
      };
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = 'No account found with this email.';
          break;
        case 'invalid-email':
          message = 'The email address is invalid.';
          break;
        default:
          message = 'Failed to send reset email: ${e.message}';
      }
      return {'success': false, 'message': message};
    } catch (e) {
      return {'success': false, 'message': 'An unexpected error occurred: $e'};
    }
  }

  // Check if user is logged in and setup is complete
  Future<Map<String, dynamic>> checkAuthStatus() async {
    try {
      User? user = currentUser;

      if (user == null) {
        return {'isLoggedIn': false};
      }

      // Get user data
      Map<String, dynamic>? userData = await getUserData(user.uid);

      if (userData == null) {
        return {'isLoggedIn': false};
      }

      String userType = userData['userType'];
      bool setupComplete = true;

      // Check if patient setup is complete
      if (userType == 'patient') {
        Map<String, dynamic>? patientData = await getPatientData(user.uid);
        setupComplete = patientData?['setupComplete'] ?? false;
      }

      return {
        'isLoggedIn': true,
        'userType': userType,
        'setupComplete': setupComplete,
        'uid': user.uid,
        'userData': userData,
      };
    } catch (e) {
      print('Error checking auth status: $e');
      return {'isLoggedIn': false};
    }
  }
}