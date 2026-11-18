
import 'package:cloud_firestore/cloud_firestore.dart';

class ConversationModel {
  final String id;
  final List<String> participants;
  final DateTime? createdAt;
  final DateTime? lastMessageAt;

  const ConversationModel({
    required this.id,
    required this.participants,
    this.createdAt,
    this.lastMessageAt,
  });

  factory ConversationModel.fromMap(
    String id,
    Map<String, dynamic> map,
  ) {
    return ConversationModel(
      id: id,
      participants: List<String>.from(
        map['participants'] ?? [],
      ),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      lastMessageAt: (map['lastMessageAt'] as Timestamp?)?.toDate(),
    );
  }
}
