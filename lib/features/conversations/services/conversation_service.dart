import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/conversation_model.dart';

class ConversationService {
  ConversationService._();

  static final ConversationService instance = ConversationService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _conversations =>
      _firestore.collection('conversations');

  CollectionReference<Map<String, dynamic>> get _publicProfiles =>
      _firestore.collection('publicProfiles');

  // Generate the same conversation ID for both users.
  String generateConversationId(String firstUid, String secondUid) {
    final participants = [firstUid, secondUid]..sort();

    return '${participants[0]}_${participants[1]}';
  }

  // Create conversation metadata when the first message is sent.
  Future<String> createConversationIfNeeded({
    required String otherUserId,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      throw Exception('Please sign in again.');
    }

    final currentUid = currentUser.uid;

    if (currentUid == otherUserId) {
      throw Exception('You cannot start a conversation with yourself.');
    }

    final conversationId = generateConversationId(currentUid, otherUserId);

    final conversationReference = _conversations.doc(conversationId);
    final otherUserReference = _publicProfiles.doc(otherUserId);

    return _firestore.runTransaction((transaction) async {
      final conversationSnapshot = await transaction.get(conversationReference);

      if (conversationSnapshot.exists) {
        return conversationId;
      }

      final otherUserSnapshot = await transaction.get(otherUserReference);

      if (!otherUserSnapshot.exists ||
          otherUserSnapshot.data()?['profileCompleted'] != true) {
        throw Exception('This user is not available.');
      }

      final participants = [currentUid, otherUserId]..sort();

      transaction.set(conversationReference, {
        'participants': participants,
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessageAt': FieldValue.serverTimestamp(),
      });

      return conversationId;
    });
  }

  // Listen only to conversation metadata.
  // This method NEVER fetches messages.
  Stream<List<ConversationModel>> watchConversations() {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return Stream.value([]);
    }

    return _conversations
        .where('participants', arrayContains: currentUser.uid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return ConversationModel.fromMap(doc.id, doc.data());
          }).toList();
        });
  }

  // Fetch one conversation's metadata.
  Future<ConversationModel?> getConversation(String conversationId) async {
    final snapshot = await _conversations
        .doc(conversationId)
        .get(const GetOptions(source: Source.server));

    if (!snapshot.exists || snapshot.data() == null) {
      return null;
    }

    return ConversationModel.fromMap(snapshot.id, snapshot.data()!);
  }
}
