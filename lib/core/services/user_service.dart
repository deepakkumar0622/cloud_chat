import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../shared/models/user_model.dart';
import '../../shared/models/public_user_model.dart';

class UserService {
  UserService._();

  static final UserService instance = UserService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> get _publicProfiles =>
      _firestore.collection('publicProfiles');

  CollectionReference<Map<String, dynamic>> get _usernames =>
      _firestore.collection('usernames');

  // Store searchable phone-number fragments in the private user document.
  // The Edge Function uses these tokens and returns only public profile data.
  List<String> _buildPhoneSearchTokens(String? phoneNumber) {
    if (phoneNumber == null || phoneNumber.isEmpty) return [];

    final digits = phoneNumber.replaceAll(RegExp(r'\D'), '');
    final tokens = <String>{};

    for (var start = 0; start < digits.length; start++) {
      for (
        var length = 2;
        length <= 10 && start + length <= digits.length;
        length++
      ) {
        tokens.add(digits.substring(start, start + length));
      }
    }

    return tokens.toList();
  }

  // Create private user document after authentication and backfill search tokens
  // for existing accounts the next time they authenticate.
  Future<void> createUserIfNotExists(User user) async {
    final userReference = _users.doc(user.uid);
    final snapshot = await userReference.get(
      const GetOptions(source: Source.server),
    );

    final tokens = _buildPhoneSearchTokens(user.phoneNumber);

    if (snapshot.exists) {
      final existingTokens = List<String>.from(
        snapshot.data()?['phoneSearchTokens'] ?? const [],
      );
      if (tokens.isNotEmpty && existingTokens.isEmpty) {
        await userReference.update({'phoneSearchTokens': tokens});
      }
      return;
    }

    final newUser = UserModel(uid: user.uid, phoneNumber: user.phoneNumber);
    await userReference.set({...newUser.toMap(), 'phoneSearchTokens': tokens});
  }

  // Listen to the current user's private profile.
  Stream<UserModel?> watchUser(String uid) {
    return _users.doc(uid).snapshots().map((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) return null;
      return UserModel.fromMap(snapshot.data()!);
    });
  }

  // Fetch current user's private profile.
  Future<UserModel?> getUser(String uid) async {
    final snapshot = await _users
        .doc(uid)
        .get(const GetOptions(source: Source.server));

    if (!snapshot.exists || snapshot.data() == null) return null;
    return UserModel.fromMap(snapshot.data()!);
  }

  // Create public profile and reserve username atomically.
  Future<void> createProfile({
    required String uid,
    required String displayName,
    required String username,
    String? photoPath,
  }) async {
    final normalizedUsername = username.trim().toLowerCase();
    final normalizedDisplayName = displayName.trim();

    if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(normalizedUsername)) {
      throw Exception(
        'Username must contain 3-20 letters, numbers or underscores.',
      );
    }
    if (normalizedDisplayName.isEmpty) {
      throw Exception('Display name cannot be empty.');
    }

    final profileReference = _users.doc(uid);
    final publicProfileReference = _publicProfiles.doc(uid);
    final usernameReference = _usernames.doc(normalizedUsername);

    await _firestore.runTransaction((transaction) async {
      final profileSnapshot = await transaction.get(profileReference);
      final usernameSnapshot = await transaction.get(usernameReference);

      if (!profileSnapshot.exists) {
        throw Exception('User profile does not exist. Please sign in again.');
      }
      if (profileSnapshot.data()?['profileCompleted'] == true) {
        throw Exception('Profile already completed.');
      }
      if (usernameSnapshot.exists)
        throw Exception('Username is already taken.');

      transaction.set(usernameReference, {
        'uid': uid,
        'username': normalizedUsername,
      });
      transaction.set(publicProfileReference, {
        'uid': uid,
        'displayName': normalizedDisplayName,
        'username': normalizedUsername,
        'photoUrl': null,
        'photoPath': photoPath,
        'profileCompleted': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(profileReference, {
        'profileCompleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // Update display name, username and profile photo.
  Future<void> updateProfile({
    required String uid,
    required String displayName,
    required String username,
    String? photoPath,
    bool removePhoto = false,
  }) async {
    final normalizedUsername = username.trim().toLowerCase();
    final normalizedDisplayName = displayName.trim();

    if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(normalizedUsername)) {
      throw Exception(
        'Username must contain 3-20 letters, numbers or underscores.',
      );
    }
    if (normalizedDisplayName.isEmpty)
      throw Exception('Display name cannot be empty.');
    if (removePhoto && photoPath != null) {
      throw Exception('Cannot upload and remove a photo at the same time.');
    }

    final profileReference = _publicProfiles.doc(uid);
    final newUsernameReference = _usernames.doc(normalizedUsername);

    await _firestore.runTransaction((transaction) async {
      final profileSnapshot = await transaction.get(profileReference);
      if (!profileSnapshot.exists || profileSnapshot.data() == null) {
        throw Exception('Public profile not found.');
      }

      final profileData = profileSnapshot.data()!;
      if (profileData['uid'] != uid ||
          profileData['profileCompleted'] != true) {
        throw Exception('Invalid profile.');
      }

      final oldUsername = (profileData['username'] as String?)?.toLowerCase();
      if (oldUsername == null || oldUsername.isEmpty) {
        throw Exception('Current username not found.');
      }

      final usernameChanged = oldUsername != normalizedUsername;
      final oldUsernameReference = _usernames.doc(oldUsername);
      final oldUsernameSnapshot = await transaction.get(oldUsernameReference);

      if (!oldUsernameSnapshot.exists ||
          oldUsernameSnapshot.data()?['uid'] != uid) {
        throw Exception('Current username registration is invalid.');
      }

      if (usernameChanged) {
        final newUsernameSnapshot = await transaction.get(newUsernameReference);
        if (newUsernameSnapshot.exists)
          throw Exception('Username is already taken.');
        transaction.delete(oldUsernameReference);
        transaction.set(newUsernameReference, {
          'uid': uid,
          'username': normalizedUsername,
        });
      }

      final updates = <String, dynamic>{
        'displayName': normalizedDisplayName,
        'username': normalizedUsername,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (photoPath != null) {
        updates['photoPath'] = photoPath;
        updates['photoUrl'] = null;
      }
      if (removePhoto) {
        updates['photoPath'] = null;
        updates['photoUrl'] = null;
      }
      transaction.update(profileReference, updates);
    });
  }

  // Listen to all completed public profiles except the current user.
  Stream<List<PublicUserModel>> watchContacts(String currentUid) {
    return _publicProfiles
        .where('profileCompleted', isEqualTo: true)
        .orderBy('username')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .where((doc) => doc.id != currentUid)
              .map((doc) => PublicUserModel.fromMap(doc.data()))
              .toList(),
        );
  }

  // Search users by username prefix.
  Future<List<PublicUserModel>> searchUsers({
    required String query,
    required String currentUid,
  }) async {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return [];

    final snapshot = await _publicProfiles
        .where('profileCompleted', isEqualTo: true)
        .orderBy('username')
        .startAt([normalizedQuery])
        .endAt(['$normalizedQuery\uf8ff'])
        .limit(20)
        .get();

    return snapshot.docs
        .where((doc) => doc.id != currentUid)
        .map((doc) => PublicUserModel.fromMap(doc.data()))
        .toList();
  }

  // Get another user's public profile.
  Future<PublicUserModel?> getPublicProfile(String uid) async {
    final snapshot = await _publicProfiles
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    if (!snapshot.exists || snapshot.data() == null) return null;
    return PublicUserModel.fromMap(snapshot.data()!);
  }

  // Listen to another user's public profile.
  Stream<PublicUserModel?> watchPublicProfile(String uid) {
    return _publicProfiles.doc(uid).snapshots().map((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) return null;
      return PublicUserModel.fromMap(snapshot.data()!);
    });
  }
}
