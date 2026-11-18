
import 'package:cloud_firestore/cloud_firestore.dart';

class PublicUserModel {
  final String uid;
  final String displayName;
  final String username;
  final String? photoUrl;
  final bool profileCompleted;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const PublicUserModel({
    required this.uid,
    required this.displayName,
    required this.username,
    this.photoUrl,
    this.profileCompleted = false,
    this.createdAt,
    this.updatedAt,
  });

  factory PublicUserModel.fromMap(Map<String, dynamic> map) {
    return PublicUserModel(
      uid: map['uid'] as String,
      displayName: map['displayName'] as String? ?? '',
      username: map['username'] as String? ?? '',
      photoUrl: map['photoUrl'] as String?,
      profileCompleted: map['profileCompleted'] as bool? ?? false,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'displayName': displayName,
      'username': username,
      'photoUrl': photoUrl,
      'profileCompleted': profileCompleted,
      'createdAt': createdAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(createdAt!),
      'updatedAt': updatedAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(updatedAt!),
    };
  }
}
