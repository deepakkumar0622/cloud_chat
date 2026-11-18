import 'package:cloud_firestore/cloud_firestore.dart';

class MessageModel {
  final String id;
  final String senderId;
  final String text;
  final DateTime? createdAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;

  // Message deletion fields
  final List<String> deletedFor;
  final bool isDeletedForEveryone;
  final DateTime? deletedAt;

  const MessageModel({
    required this.id,
    required this.senderId,
    required this.text,
    this.createdAt,
    this.deliveredAt,
    this.readAt,
    this.deletedFor = const [],
    this.isDeletedForEveryone = false,
    this.deletedAt,
  });

  factory MessageModel.fromMap(String id, Map<String, dynamic> map) {
    return MessageModel(
      id: id,
      senderId: map['senderId'] ?? '',
      text: map['text'] ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      deliveredAt: (map['deliveredAt'] as Timestamp?)?.toDate(),
      readAt: (map['readAt'] as Timestamp?)?.toDate(),
      deletedFor: List<String>.from(map['deletedFor'] ?? []),
      isDeletedForEveryone: map['isDeletedForEveryone'] ?? false,
      deletedAt: (map['deletedAt'] as Timestamp?)?.toDate(),
    );
  }
}
