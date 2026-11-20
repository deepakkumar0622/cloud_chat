import 'package:cloud_firestore/cloud_firestore.dart';

class ConversationModel {
  final String id;
  final List<String> participants;
  final DateTime? createdAt;
  final DateTime? lastMessageAt;

  // Pre-registration conversation details.
  final String? status;
  final String? conversationType;
  final String? recipientPhoneNumber;
  final String? recipientPhoneLast4;

  const ConversationModel({
    required this.id,
    required this.participants,
    this.createdAt,
    this.lastMessageAt,
    this.status,
    this.conversationType,
    this.recipientPhoneNumber,
    this.recipientPhoneLast4,
  });

  bool get isPending => status == 'pending';

  factory ConversationModel.fromMap(String id, Map<String, dynamic> map) {
    return ConversationModel(
      id: id,
      participants: List<String>.from(map['participants'] ?? []),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      lastMessageAt: (map['lastMessageAt'] as Timestamp?)?.toDate(),
      status: map['status'] as String?,
      conversationType: map['conversationType'] as String?,
      recipientPhoneNumber: map['recipientPhoneNumber'] as String?,
      recipientPhoneLast4: map['recipientPhoneLast4'] as String?,
    );
  }
}
