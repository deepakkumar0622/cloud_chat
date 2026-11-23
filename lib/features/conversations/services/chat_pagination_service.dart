import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../shared/models/message_model.dart';

class ChatPaginationService extends ChangeNotifier {
  ChatPaginationService({required this.conversationId, this.pageSize = 5});

  final String conversationId;
  final int pageSize;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, MessageModel> _messages = {};

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _messagesSubscription;

  int _loadedLimit = 0;
  int _queryCount = 0;

  bool isInitialLoading = true;
  bool isLoadingMore = false;
  bool hasMoreMessages = true;
  bool _disposed = false;

  String? error;

  CollectionReference<Map<String, dynamic>> get _messagesCollection =>
      _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages');

  List<MessageModel> get messages {
    final result = _messages.values.toList();

    result.sort((a, b) {
      final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

      return aDate.compareTo(bDate);
    });

    return result;
  }

  // FIRST PAGE: Load only 5 messages.
  Future<void> startListening() async {
    await _messagesSubscription?.cancel();

    _messages.clear();
    _loadedLimit = pageSize;
    _queryCount = 0;

    isInitialLoading = true;
    isLoadingMore = false;
    hasMoreMessages = true;
    error = null;

    debugPrint('CHAT PAGINATION: Starting first page');

    _notify();

    await _subscribeToMessages();
  }

  // Creates the real-time listener for the currently loaded messages.
  Future<void> _subscribeToMessages() async {
    await _messagesSubscription?.cancel();

    _queryCount++;

    debugPrint(
      'CHAT PAGINATION: Query #$_queryCount | '
      'Fetching maximum $_loadedLimit messages',
    );

    _messagesSubscription = _messagesCollection
        .orderBy('createdAt', descending: true)
        .limit(_loadedLimit)
        .snapshots()
        .listen(
          (snapshot) {
            _messages.clear();

            for (final doc in snapshot.docs) {
              _messages[doc.id] = MessageModel.fromMap(doc.id, doc.data());
            }

            hasMoreMessages = snapshot.docs.length == _loadedLimit;

            isInitialLoading = false;
            isLoadingMore = false;
            error = null;

            debugPrint(
              'CHAT PAGINATION: Query #$_queryCount received '
              '${snapshot.docs.length} messages | '
              'Has more: $hasMoreMessages',
            );

            _notify();
          },
          onError: (Object exception) {
            isInitialLoading = false;
            isLoadingMore = false;
            error = exception.toString();

            debugPrint('CHAT PAGINATION ERROR: $exception');

            _notify();
          },
        );
  }

  // CALLED ONLY WHEN THE USER SCROLLS TO OLDER MESSAGES.
  Future<void> loadOlderMessages() async {
    if (isInitialLoading || isLoadingMore || !hasMoreMessages) {
      debugPrint('CHAT PAGINATION: Load skipped');
      return;
    }

    isLoadingMore = true;
    error = null;
    _notify();

    _loadedLimit += pageSize;

    debugPrint(
      'CHAT PAGINATION: User requested older messages. '
      'New limit: $_loadedLimit',
    );

    await _subscribeToMessages();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _messagesSubscription?.cancel();
    super.dispose();
  }
}
