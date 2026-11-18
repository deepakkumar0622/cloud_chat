
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

  // Create private user document after authentication.
  Future<void> createUserIfNotExists(User user) async {
    final userReference = _users.doc(user.uid);

    final snapshot = await userReference.get(
      const GetOptions(source: Source.server),
    );

    if (snapshot.exists) return;

    final newUser = UserModel(
      uid: user.uid,
      phoneNumber: user.phoneNumber,
    );

    await userReference.set(newUser.toMap());
  }

  // Listen to the current user's private profile.
  Stream<UserModel?> watchUser(String uid) {
    return _users.doc(uid).snapshots().map((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) {
        return null;
      }

      return UserModel.fromMap(snapshot.data()!);
    });
  }

  // Fetch current user's private profile.
  Future<UserModel?> getUser(String uid) async {
    final snapshot = await _users.doc(uid).get(
      const GetOptions(source: Source.server),
    );

    if (!snapshot.exists || snapshot.data() == null) {
      return null;
    }

    return UserModel.fromMap(snapshot.data()!);
  }

  // Create public profile and reserve username atomically.
  Future<void> createProfile({
    required String uid,
    required String displayName,
    required String username,
  }) async {
    final normalizedUsername = username.trim().toLowerCase();
    final normalizedDisplayName = displayName.trim();

    if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$')
        .hasMatch(normalizedUsername)) {
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
        throw Exception(
          'User profile does not exist. Please sign in again.',
        );
      }

      if (profileSnapshot.data()?['profileCompleted'] == true) {
        throw Exception('Profile already completed.');
      }

      if (usernameSnapshot.exists) {
        throw Exception('Username is already taken.');
      }

      transaction.set(usernameReference, {
        'uid': uid,
        'username': normalizedUsername,
      });

      transaction.set(
        publicProfileReference,
        {
          'uid': uid,
          'displayName': normalizedDisplayName,
          'username': normalizedUsername,
          'photoUrl': null,
          'profileCompleted': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );

      transaction.update(profileReference, {
        'profileCompleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // Listen to all completed public profiles except the current user.
  Stream<List<PublicUserModel>> watchContacts(String currentUid) {
    return _publicProfiles
        .where('profileCompleted', isEqualTo: true)
        .orderBy('username')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .where((doc) => doc.id != currentUid)
          .map((doc) => PublicUserModel.fromMap(doc.data()))
          .toList();
    });
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
    final snapshot = await _publicProfiles.doc(uid).get(
      const GetOptions(source: Source.server),
    );

    if (!snapshot.exists || snapshot.data() == null) {
      return null;
    }

    return PublicUserModel.fromMap(snapshot.data()!);
  }

  // Listen to another user's public profile.
  Stream<PublicUserModel?> watchPublicProfile(String uid) {
    return _publicProfiles.doc(uid).snapshots().map((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) {
        return null;
      }

      return PublicUserModel.fromMap(snapshot.data()!);
    });
  }
}
