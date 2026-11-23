import 'package:cloud_firestore/cloud_firestore.dart';

class ContactModel {
  final String id;
  final String contactName;
  final String phoneNumber;
  final String? matchedUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ContactModel({
    required this.id,
    required this.contactName,
    required this.phoneNumber,
    this.matchedUid,
    this.createdAt,
    this.updatedAt,
  });

  bool get isRegistered => matchedUid != null && matchedUid!.isNotEmpty;

  factory ContactModel.fromMap(String id, Map<String, dynamic> map) {
    return ContactModel(
      id: id,
      contactName: map['contactName'] ?? '',
      phoneNumber: map['phoneNumber'] ?? '',
      matchedUid: map['matchedUid'] as String?,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  // Client-created fields.
  // matchedUid is intentionally excluded because it is backend-managed.
  Map<String, dynamic> toCreateMap() {
    return {
      'contactName': contactName.trim(),
      'phoneNumber': phoneNumber,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  // Client-editable fields.
  Map<String, dynamic> toUpdateMap() {
    return {
      'contactName': contactName.trim(),
      'phoneNumber': phoneNumber,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
