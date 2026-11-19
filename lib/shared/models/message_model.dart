import 'package:cloud_firestore/cloud_firestore.dart';

class MessageModel {
  final String id;
  final String senderId;
  final String text;
  final DateTime? createdAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;

  // Message type: text, image or file.
  final String messageType;

  // Attachment information.
  final String? attachmentPath;
  final String? fileName;
  final String? mimeType;
  final int? fileSize;

  // Message deletion fields.
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
    this.messageType = 'text',
    this.attachmentPath,
    this.fileName,
    this.mimeType,
    this.fileSize,
    this.deletedFor = const [],
    this.isDeletedForEveryone = false,
    this.deletedAt,
  });

  bool get isTextMessage => messageType == 'text';

  bool get isImageMessage => messageType == 'image';

  bool get isFileMessage => messageType == 'file';

  factory MessageModel.fromMap(String id, Map<String, dynamic> map) {
    return MessageModel(
      id: id,
      senderId: map['senderId'] ?? '',
      text: map['text'] ?? '',

      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      deliveredAt: (map['deliveredAt'] as Timestamp?)?.toDate(),
      readAt: (map['readAt'] as Timestamp?)?.toDate(),

      // Old messages automatically remain text messages.
      messageType: map['messageType'] ?? 'text',

      attachmentPath: map['attachmentPath'],
      fileName: map['fileName'],
      mimeType: map['mimeType'],
      fileSize: (map['fileSize'] as num?)?.toInt(),

      deletedFor: List<String>.from(map['deletedFor'] ?? []),
      isDeletedForEveryone: map['isDeletedForEveryone'] ?? false,
      deletedAt: (map['deletedAt'] as Timestamp?)?.toDate(),
    );
  }
}
