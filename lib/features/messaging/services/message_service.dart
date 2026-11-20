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

  // ---------------------------------------------------------------------------
  // PENDING CONVERSATION CREATION
  // ---------------------------------------------------------------------------

  /// Creates or reuses the pending conversation through the Edge Function.
  ///
  /// This is called only when the sender actually sends their first message
  /// or attachment, never when they merely open the chat.

  Future<void> _ensurePendingConversation({
    required String conversationId,
    required String? recipientPhoneNumber,
    required String? otherUserId,
  }) async {
    final currentUser = AuthService.instance.currentUser;

    if (currentUser == null) {
      throw Exception('Please sign in again.');
    }

    final currentUid = currentUser.uid;
    final conversationRef = _conversations.doc(conversationId);
    final existingSnapshot = await conversationRef.get();

    if (existingSnapshot.exists) {
      final data = existingSnapshot.data()!;
      final participants = List<String>.from(data['participants'] ?? []);
      final status = data['status'];

      if (!participants.contains(currentUid)) {
        throw Exception('You are not a participant in this conversation.');
      }

      // The recipient has registered and claimed this conversation.
      if (status == 'active') {
        if (participants.length != 2 ||
            otherUserId == null ||
            otherUserId.isEmpty ||
            otherUserId == currentUid ||
            !participants.contains(otherUserId)) {
          throw Exception('Invalid active conversation.');
        }

        return;
      }

      // The recipient has not registered yet.
      if (status == 'pending') {
        if (otherUserId != null ||
            participants.length != 1 ||
            participants.first != currentUid ||
            data['conversationType'] != 'phone') {
          throw Exception('Invalid pending conversation.');
        }

        return;
      }

      throw Exception('This conversation is not available.');
    }

    // A missing pending document can only be created by the original sender.
    if (otherUserId != null) {
      throw Exception('Invalid pending conversation.');
    }

    final phoneNumber = recipientPhoneNumber?.trim() ?? '';

    if (phoneNumber.isEmpty) {
      throw Exception('Recipient phone number is missing.');
    }

    final firebaseToken = await currentUser.getIdToken();

    if (firebaseToken == null || firebaseToken.isEmpty) {
      throw Exception('Unable to authenticate. Please sign in again.');
    }

    final response = await Supabase.instance.client.functions.invoke(
      'create-or-find-phone-conversation',
      method: HttpMethod.post,
      headers: {'Authorization': 'Bearer $firebaseToken'},
      body: {'action': 'create', 'phoneNumber': phoneNumber},
    );

    if (response.status < 200 || response.status >= 300) {
      final data = response.data;

      throw Exception(
        data is Map
            ? data['error']?.toString() ?? 'Unable to create conversation.'
            : 'Unable to create conversation.',
      );
    }

    if (response.data is! Map) {
      throw Exception('Invalid response from server.');
    }

    final data = Map<String, dynamic>.from(response.data as Map);

    if (data['success'] != true) {
      throw Exception(
        data['error']?.toString() ?? 'Unable to create conversation.',
      );
    }

    final returnedConversationId = data['conversationId']?.toString();

    if (returnedConversationId != conversationId) {
      throw Exception(
        'The recipient account status has changed. '
        'Please return to Contacts and reopen the conversation.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // MESSAGE LISTENER
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // SEND TEXT MESSAGE
  // ---------------------------------------------------------------------------

  Future<void> sendTextMessage({
    required String conversationId,
    required String? otherUserId,
    required String text,
    String? recipientPhoneNumber,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      throw Exception('Please sign in again.');
    }

    final messageText = text.trim();

    if (messageText.isEmpty) return;

    final currentUid = currentUser.uid;
    final isPendingConversation = conversationId.startsWith('pending_');

    if (isPendingConversation) {
      await _ensurePendingConversation(
        conversationId: conversationId,
        recipientPhoneNumber: recipientPhoneNumber,
        otherUserId: otherUserId,
      );
    } else {
      if (otherUserId == null || otherUserId.isEmpty) {
        throw Exception('Recipient information is missing.');
      }

      if (currentUid == otherUserId) {
        throw Exception('You cannot message yourself.');
      }

      final participants = [currentUid, otherUserId]..sort();
      final expectedId = '${participants[0]}_${participants[1]}';

      if (conversationId != expectedId) {
        throw Exception('Invalid conversation.');
      }
    }

    final conversationReference = _conversations.doc(conversationId);
    final messageReference = conversationReference.collection('messages').doc();

    await _firestore.runTransaction((transaction) async {
      final conversationSnapshot = await transaction.get(conversationReference);

      if (isPendingConversation) {
        if (!conversationSnapshot.exists) {
          throw Exception('Pending conversation could not be created.');
        }

        final conversationData = conversationSnapshot.data()!;

        final existingParticipants = List<String>.from(
          conversationData['participants'] ?? [],
        );

        final status = conversationData['status'];

        if (!existingParticipants.contains(currentUid)) {
          throw Exception('You are not allowed to message this user.');
        }

        if (status == 'pending') {
          if (otherUserId != null ||
              conversationData['conversationType'] != 'phone' ||
              existingParticipants.length != 1 ||
              existingParticipants.first != currentUid) {
            throw Exception('Invalid pending conversation.');
          }
        } else if (status == 'active') {
          if (otherUserId == null ||
              otherUserId.isEmpty ||
              otherUserId == currentUid ||
              existingParticipants.length != 2 ||
              !existingParticipants.contains(otherUserId)) {
            throw Exception('Invalid active conversation.');
          }
        } else {
          throw Exception('This conversation is not available.');
        }

        transaction.update(conversationReference, {
          'lastMessageAt': FieldValue.serverTimestamp(),
        });
      } else {
        final participants = [currentUid, otherUserId!]..sort();

        if (conversationSnapshot.exists) {
          final existingParticipants = List<String>.from(
            conversationSnapshot.data()?['participants'] ?? [],
          );

          if (!existingParticipants.contains(currentUid) ||
              !existingParticipants.contains(otherUserId)) {
            throw Exception('You are not allowed to message this user.');
          }

          transaction.update(conversationReference, {
            'lastMessageAt': FieldValue.serverTimestamp(),
          });
        } else {
          final otherProfileSnapshot = await transaction.get(
            _publicProfiles.doc(otherUserId),
          );

          if (!otherProfileSnapshot.exists ||
              otherProfileSnapshot.data()?['profileCompleted'] != true) {
            throw Exception('This user is not available.');
          }

          transaction.set(conversationReference, {
            'participants': participants,
            'createdAt': FieldValue.serverTimestamp(),
            'lastMessageAt': FieldValue.serverTimestamp(),
          });
        }
      }

      transaction.set(messageReference, {
        'senderId': currentUid,
        'text': messageText,
        'createdAt': FieldValue.serverTimestamp(),
        'deliveredAt': null,
        'readAt': null,
        'deletedFor': <String>[],
        'isDeletedForEveryone': false,
        'deletedAt': null,
      });
    });
  }

  // ---------------------------------------------------------------------------
  // SEND ATTACHMENT MESSAGE
  // ---------------------------------------------------------------------------

  Future<void> sendAttachmentMessage({
    required String conversationId,
    required String? otherUserId,
    required String messageType,
    required String attachmentPath,
    required String fileName,
    required String mimeType,
    required int fileSize,
    String? recipientPhoneNumber,
  }) async {
    final currentUser = AuthService.instance.currentUser;

    if (currentUser == null) {
      throw Exception('User is not authenticated.');
    }

    final uid = currentUser.uid;
    final isPendingConversation = conversationId.startsWith('pending_');

    if (otherUserId != null && uid == otherUserId) {
      throw Exception('Cannot send an attachment to yourself.');
    }

    if (messageType != 'image' && messageType != 'file') {
      throw Exception('Invalid attachment message type.');
    }

    if (fileName.trim().isEmpty || fileName.length > 255) {
      throw Exception('Invalid file name.');
    }

    if (fileSize < 1024) {
      throw Exception('File must be at least 1 KB.');
    }

    if (fileSize > 20 * 1024 * 1024) {
      throw Exception('File cannot exceed 20 MB.');
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

    if (isPendingConversation) {
      await _ensurePendingConversation(
        conversationId: conversationId,
        recipientPhoneNumber: recipientPhoneNumber,
        otherUserId: otherUserId,
      );
    } else {
      if (otherUserId == null || otherUserId.isEmpty) {
        throw Exception('Recipient information is missing.');
      }

      final participants = [uid, otherUserId]..sort();
      final expectedConversationId = '${participants[0]}_${participants[1]}';

      if (conversationId != expectedConversationId) {
        throw Exception('Invalid conversation.');
      }
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

    final otherProfileRef = otherUserId != null
        ? _publicProfiles.doc(otherUserId)
        : null;

    await _firestore.runTransaction((transaction) async {
      final conversationSnapshot = await transaction.get(conversationRef);

      if (isPendingConversation) {
        if (!conversationSnapshot.exists) {
          throw Exception('Pending conversation could not be created.');
        }

        final conversationData = conversationSnapshot.data()!;

        final existingParticipants = List<String>.from(
          conversationData['participants'] ?? [],
        );

        final status = conversationData['status'];

        if (!existingParticipants.contains(uid)) {
          throw Exception('You are not a participant in this conversation.');
        }

        if (status == 'pending') {
          if (otherUserId != null ||
              conversationData['conversationType'] != 'phone' ||
              existingParticipants.length != 1 ||
              existingParticipants.first != uid) {
            throw Exception('Invalid pending conversation.');
          }
        } else if (status == 'active') {
          if (otherUserId == null ||
              otherUserId.isEmpty ||
              otherUserId == uid ||
              existingParticipants.length != 2 ||
              !existingParticipants.contains(otherUserId)) {
            throw Exception('Invalid active conversation.');
          }
        } else {
          throw Exception('Invalid conversation status.');
        }

        transaction.update(conversationRef, {
          'lastMessageAt': FieldValue.serverTimestamp(),
        });
      } else {
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

          transaction.update(conversationRef, {
            'lastMessageAt': FieldValue.serverTimestamp(),
          });
        } else {
          final otherProfileSnapshot = await transaction.get(otherProfileRef!);

          if (!otherProfileSnapshot.exists ||
              otherProfileSnapshot.data()?['profileCompleted'] != true) {
            throw Exception('Recipient profile not found.');
          }

          final participants = [uid, otherUserId!]..sort();

          transaction.set(conversationRef, {
            'participants': participants,
            'createdAt': FieldValue.serverTimestamp(),
            'lastMessageAt': FieldValue.serverTimestamp(),
          });
        }
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

  // ---------------------------------------------------------------------------
  // READ AND DELIVERY STATUS
  // ---------------------------------------------------------------------------

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
      if (message.senderId == currentUser.uid ||
          message.readAt != null ||
          message.isDeletedForEveryone ||
          message.deletedFor.contains(currentUser.uid)) {
        continue;
      }

      final updates = <String, dynamic>{'readAt': FieldValue.serverTimestamp()};

      if (message.deliveredAt == null) {
        updates['deliveredAt'] = FieldValue.serverTimestamp();
      }

      batch.update(messagesReference.doc(message.id), updates);

      operationCount++;

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

  // ---------------------------------------------------------------------------
  // DELETE MESSAGE
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // SECURE ATTACHMENT URL
  // ---------------------------------------------------------------------------

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
