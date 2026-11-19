import 'package:cloud_chat/core/services/auth_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/message_model.dart';

class MessageService {
  MessageService._();

  static final MessageService instance = MessageService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _conversations =>
      _firestore.collection('conversations');

  CollectionReference<Map<String, dynamic>> get _publicProfiles =>
      _firestore.collection('publicProfiles');

  // Listen to messages in chronological order.
  Stream<List<MessageModel>> watchMessages(String conversationId) {
    return _conversations
        .doc(conversationId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return MessageModel.fromMap(doc.id, doc.data());
          }).toList();
        });
  }

  // Create the conversation only when the first message is sent.
  Future<void> sendTextMessage({
    required String conversationId,
    required String otherUserId,
    required String text,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      throw Exception('Please sign in again.');
    }

    final messageText = text.trim();

    if (messageText.isEmpty) {
      return;
    }

    if (currentUser.uid == otherUserId) {
      throw Exception('You cannot message yourself.');
    }

    final currentUid = currentUser.uid;

    final participants = [currentUid, otherUserId]..sort();

    final expectedId = '${participants[0]}_${participants[1]}';

    if (conversationId != expectedId) {
      throw Exception('Invalid conversation.');
    }

    final conversationReference = _conversations.doc(conversationId);
    final messageReference = conversationReference.collection('messages').doc();

    await _firestore.runTransaction((transaction) async {
      // Read the conversation first.
      final conversationSnapshot = await transaction.get(conversationReference);

      if (conversationSnapshot.exists) {
        final existingParticipants = List<String>.from(
          conversationSnapshot.data()?['participants'] ?? [],
        );

        if (!existingParticipants.contains(currentUid) ||
            !existingParticipants.contains(otherUserId)) {
          throw Exception('You are not allowed to message this user.');
        }

        // Update the existing conversation timestamp.
        transaction.update(conversationReference, {
          'lastMessageAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Verify the other user's public profile before creating a conversation.
        final otherProfileSnapshot = await transaction.get(
          _publicProfiles.doc(otherUserId),
        );

        if (!otherProfileSnapshot.exists ||
            otherProfileSnapshot.data()?['profileCompleted'] != true) {
          throw Exception('This user is not available.');
        }

        // Create conversation metadata with the first message.
        transaction.set(conversationReference, {
          'participants': participants,
          'createdAt': FieldValue.serverTimestamp(),
          'lastMessageAt': FieldValue.serverTimestamp(),
        });
      }

      // Save the message.
      transaction.set(messageReference, {
        'senderId': currentUid,
        'text': messageText,
        'createdAt': FieldValue.serverTimestamp(),
        'deliveredAt': null,
        'readAt': null,
        'deletedFor': [],
        'isDeletedForEveryone': false,
        'deletedAt': null,
      });
    });
  }

  Future<void> sendAttachmentMessage({
    required String conversationId,
    required String otherUserId,
    required String messageType,
    required String attachmentPath,
    required String fileName,
    required String mimeType,
    required int fileSize,
  }) async {
    final currentUser = AuthService.instance.currentUser;

    if (currentUser == null) {
      throw Exception('User is not authenticated.');
    }

    final uid = currentUser.uid;

    if (uid == otherUserId) {
      throw Exception('Cannot send an attachment to yourself.');
    }

    if (messageType != 'image' && messageType != 'file') {
      throw Exception('Invalid attachment message type.');
    }

    if (fileName.trim().isEmpty || fileName.length > 255) {
      throw Exception('Invalid file name.');
    }

    if (fileSize < 1024 * 1024 || fileSize > 20 * 1024 * 1024) {
      throw Exception('Attachment size must be between 1 MB and 20 MB.');
    }

    final allowedMimeTypes = messageType == 'image'
        ? {'image/jpeg', 'image/png', 'image/webp'}
        : {
            'application/pdf',
            'application/msword',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            'application/vnd.ms-excel',
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'application/vnd.ms-powerpoint',
            'application/vnd.openxmlformats-officedocument.presentationml.presentation',
            'text/plain',
          };

    if (!allowedMimeTypes.contains(mimeType)) {
      throw Exception('Unsupported attachment type.');
    }

    final participants = [uid, otherUserId]..sort();
    final expectedConversationId = '${participants[0]}_${participants[1]}';

    if (conversationId != expectedConversationId) {
      throw Exception('Invalid conversation.');
    }

    final pathParts = attachmentPath.split('/');

    if (pathParts.length != 3 ||
        pathParts[0] != uid ||
        pathParts[1] != conversationId ||
        pathParts[2].isEmpty) {
      throw Exception('Invalid attachment path.');
    }

    final conversationRef = _conversations.doc(conversationId);
    final messageRef = conversationRef.collection('messages').doc();
    final otherProfileRef = _publicProfiles.doc(otherUserId);

    await _firestore.runTransaction((transaction) async {
      final conversationSnapshot = await transaction.get(conversationRef);

      if (conversationSnapshot.exists) {
        final conversationData = conversationSnapshot.data()!;

        final existingParticipants = List<String>.from(
          conversationData['participants'] ?? [],
        );

        if (!existingParticipants.contains(uid) ||
            !existingParticipants.contains(otherUserId) ||
            existingParticipants.length != 2) {
          throw Exception('You are not a participant in this conversation.');
        }
      } else {
        final otherProfileSnapshot = await transaction.get(otherProfileRef);

        if (!otherProfileSnapshot.exists ||
            otherProfileSnapshot.data()?['profileCompleted'] != true) {
          throw Exception('Recipient profile not found.');
        }

        transaction.set(conversationRef, {
          'participants': participants,
          'createdAt': FieldValue.serverTimestamp(),
          'lastMessageAt': FieldValue.serverTimestamp(),
        });
      }

      if (conversationSnapshot.exists) {
        transaction.update(conversationRef, {
          'lastMessageAt': FieldValue.serverTimestamp(),
        });
      }

      transaction.set(messageRef, {
        'senderId': uid,
        'text': '',
        'createdAt': FieldValue.serverTimestamp(),
        'deliveredAt': null,
        'readAt': null,
        'deletedFor': <String>[],
        'isDeletedForEveryone': false,
        'deletedAt': null,
        'messageType': messageType,
        'attachmentPath': attachmentPath,
        'fileName': fileName,
        'mimeType': mimeType,
        'fileSize': fileSize,
      });
    });
  }

  // Mark incoming messages as delivered and read.
  Future<void> markMessagesReadAndDelivered({
    required String conversationId,
    required List<MessageModel> messages,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) return;

    var batch = _firestore.batch();
    var operationCount = 0;

    final messagesReference = _conversations
        .doc(conversationId)
        .collection('messages');

    for (final message in messages) {
      // Ignore our own messages and already-read messages.
      if (message.senderId == currentUser.uid || message.readAt != null) {
        continue;
      }

      if (message.senderId == currentUser.uid ||
          message.readAt != null ||
          message.isDeletedForEveryone ||
          message.deletedFor.contains(currentUser.uid)) {
        continue;
      }

      final updates = <String, dynamic>{'readAt': FieldValue.serverTimestamp()};

      // Set delivery timestamp if it hasn't been set.
      if (message.deliveredAt == null) {
        updates['deliveredAt'] = FieldValue.serverTimestamp();
      }

      batch.update(messagesReference.doc(message.id), updates);

      operationCount++;

      // Firestore batches support a maximum of 500 writes.
      if (operationCount == 450) {
        await batch.commit();

        batch = _firestore.batch();
        operationCount = 0;
      }
    }

    if (operationCount > 0) {
      await batch.commit();
    }
  }

  /// Delete a message only for the current user.
  Future<void> deleteMessageForMe({
    required String conversationId,
    required String messageId,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      throw Exception('User is not authenticated.');
    }

    await _conversations
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .update({
          'deletedFor': FieldValue.arrayUnion([currentUser.uid]),
        });
  }

  /// Delete a message for both participants.
  /// Only the original sender should be allowed to do this.
  Future<void> deleteMessageForEveryone({
    required String conversationId,
    required String messageId,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      throw Exception('User is not authenticated.');
    }

    final messageReference = _conversations
        .doc(conversationId)
        .collection('messages')
        .doc(messageId);

    final messageSnapshot = await messageReference.get();

    if (!messageSnapshot.exists) {
      throw Exception('Message not found.');
    }

    final messageData = messageSnapshot.data()!;

    if (messageData['senderId'] != currentUser.uid) {
      throw Exception('Only the sender can delete this message for everyone.');
    }

    if (messageData['isDeletedForEveryone'] == true) {
      return;
    }

    await messageReference.update({
      'text': '',
      'isDeletedForEveryone': true,
      'deletedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<Map<String, dynamic>> getChatAttachmentUrl({
    required String conversationId,
    required String messageId,
  }) async {
    final currentUser = AuthService.instance.currentUser;

    if (currentUser == null) {
      throw Exception('User is not authenticated.');
    }

    final firebaseToken = await currentUser.getIdToken();

    if (firebaseToken == null) {
      throw Exception('Unable to get Firebase authentication token.');
    }

    final response = await Supabase.instance.client.functions.invoke(
      'get-chat-attachment-url',
      method: HttpMethod.post,
      headers: {'Authorization': 'Bearer $firebaseToken'},
      body: {'conversationId': conversationId, 'messageId': messageId},
    );

    if (response.status < 200 || response.status >= 300) {
      throw Exception(
        response.data is Map
            ? response.data['error'] ?? 'Unable to access attachment.'
            : 'Unable to access attachment.',
      );
    }

    final data = Map<String, dynamic>.from(response.data as Map);

    if (data['signedUrl'] == null) {
      throw Exception('Attachment URL was not returned.');
    }

    return data;
  }
}
