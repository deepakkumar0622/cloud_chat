import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../../../core/services/auth_service.dart';
import '../../../shared/models/public_user_model.dart';
import '../../../shared/models/message_model.dart';
import '../../messaging/services/message_service.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final PublicUserModel otherUser;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.otherUser,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const background = Color(0xFF101827);
  static const accent = Color(0xFF7568F5);
  static const surface = Color(0xFF1B2638);
  late final Stream<List<MessageModel>> _messagesStream;

  final TextEditingController _messageController = TextEditingController();

  StreamSubscription<List<MessageModel>>? _messageStatusSubscription;

  final Set<String> _deletingMessageIds = {};

  bool _isSending = false;
  bool _isUpdatingMessageStatuses = false;

  @override
  void initState() {
    super.initState();

    _messagesStream = MessageService.instance.watchMessages(
      widget.conversationId,
    );

    _listenToMessageStatus();
  }

  // Listen for incoming messages and update their status.
  void _listenToMessageStatus() {
    _messageStatusSubscription = MessageService.instance
        .watchMessages(widget.conversationId)
        .listen((messages) async {
          if (_isUpdatingMessageStatuses) return;

          _isUpdatingMessageStatuses = true;

          try {
            await MessageService.instance.markMessagesReadAndDelivered(
              conversationId: widget.conversationId,
              messages: messages,
            );
          } catch (e) {
            debugPrint('MESSAGE STATUS ERROR: $e');
          } finally {
            _isUpdatingMessageStatuses = false;
          }
        });
  }

  String _getInitial(String name) {
    final value = name.trim();
    return value.isEmpty ? '?' : value[0].toUpperCase();
  }

  String _formatTime(DateTime? date) {
    if (date == null) return '';

    return DateFormat('h:mm a').format(date.toLocal());
  }

  String _formatDateSeparator(DateTime date) {
    final localDate = date.toLocal();
    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);

    final messageDate = DateTime(
      localDate.year,
      localDate.month,
      localDate.day,
    );

    if (messageDate == today) {
      return 'Today';
    }

    if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    }

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${localDate.day} '
        '${months[localDate.month - 1]} '
        '${localDate.year}';
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();

    if (text.isEmpty || _isSending) return;

    final currentText = _messageController.text;

    setState(() {
      _isSending = true;
    });

    try {
      await MessageService.instance.sendTextMessage(
        conversationId: widget.conversationId,
        otherUserId: widget.otherUser.uid,
        text: text,
      );

      if (!mounted) return;

      if (_messageController.text == currentText) {
        _messageController.clear();
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  // Show delete options when a message is long-pressed.
  Future<void> _showDeleteOptions(
    MessageModel message,
    String currentUid,
  ) async {
    if (message.isDeletedForEveryone ||
        message.deletedFor.contains(currentUid) ||
        _deletingMessageIds.contains(message.id)) {
      return;
    }

    final isMe = message.senderId == currentUid;

    final selectedAction = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Delete message',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.white70,
                  ),
                  title: const Text(
                    'Delete for me',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () => Navigator.pop(context, 'me'),
                ),
                if (isMe)
                  ListTile(
                    leading: const Icon(
                      Icons.delete_forever_outlined,
                      color: Colors.redAccent,
                    ),
                    title: const Text(
                      'Delete for everyone',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                    onTap: () => Navigator.pop(context, 'everyone'),
                  ),
                ListTile(
                  leading: const Icon(
                    Icons.close_rounded,
                    color: Colors.white54,
                  ),
                  title: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white54),
                  ),
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || selectedAction == null) return;

    await _confirmAndDeleteMessage(message, selectedAction);
  }

  // Confirm the selected deletion action.
  Future<void> _confirmAndDeleteMessage(
    MessageModel message,
    String action,
  ) async {
    final isEveryone = action == 'everyone';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: surface,
          title: const Text(
            'Delete message?',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            isEveryone
                ? 'This message will be deleted for both participants.'
                : 'This message will only be deleted from your chat.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white60),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) return;

    setState(() {
      _deletingMessageIds.add(message.id);
    });

    try {
      if (isEveryone) {
        await MessageService.instance.deleteMessageForEveryone(
          conversationId: widget.conversationId,
          messageId: message.id,
        );
      } else {
        await MessageService.instance.deleteMessageForMe(
          conversationId: widget.conversationId,
          messageId: message.id,
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEveryone
                ? 'Message deleted for everyone.'
                : 'Message deleted for you.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _deletingMessageIds.remove(message.id);
        });
      }
    }
  }

  Widget _buildMessageBubble(MessageModel message, String currentUid) {
    final isMe = message.senderId == currentUid;
    final isDeleted = message.isDeletedForEveryone;
    final isDeleting = _deletingMessageIds.contains(message.id);

    final messageStatus = message.readAt != null
        ? Icons.done_all_rounded
        : message.deliveredAt != null
        ? Icons.done_all_rounded
        : Icons.done_rounded;

    final statusColor = message.readAt != null
        ? Colors.lightBlueAccent
        : Colors.white70;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: isDeleted || isDeleting
            ? null
            : () => _showDeleteOptions(message, currentUid),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          decoration: BoxDecoration(
            color: isMe ? accent : surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMe ? 16 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isDeleted)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.block_rounded,
                      size: 14,
                      color: Colors.white.withOpacity(0.55),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'This message was deleted',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.65),
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  message.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
              const SizedBox(height: 5),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(message.createdAt),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.65),
                      fontSize: 10,
                    ),
                  ),
                  if (isMe && !isDeleted) ...[
                    const SizedBox(width: 5),
                    Icon(messageStatus, size: 15, color: statusColor),
                  ],
                  if (isDeleting) ...[
                    const SizedBox(width: 6),
                    const SizedBox(
                      height: 12,
                      width: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateSeparator(DateTime date) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _formatDateSeparator(date),
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessages(String currentUid) {
    return StreamBuilder<List<MessageModel>>(
      stream: _messagesStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: accent));
        }

        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Unable to load messages.',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        final allMessages = snapshot.data ?? [];

        // Hide messages deleted only for the current user.
        final messages = allMessages.where((message) {
          return !message.deletedFor.contains(currentUid);
        }).toList();

        if (messages.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.waving_hand_rounded, color: accent, size: 45),
                const SizedBox(height: 15),
                Text(
                  'Say hello to ${widget.otherUser.displayName}!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Send your first message to start chatting.',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final messageIndex = messages.length - 1 - index;
            final message = messages[messageIndex];

            final messageDate = message.createdAt;

            bool showDateSeparator = false;

            if (messageDate != null) {
              if (messageIndex == 0) {
                showDateSeparator = true;
              } else {
                final previousMessage = messages[messageIndex - 1];
                final previousDate = previousMessage.createdAt;

                showDateSeparator =
                    previousDate == null ||
                    !DateUtils.isSameDay(
                      messageDate.toLocal(),
                      previousDate.toLocal(),
                    );
              }
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showDateSeparator) _buildDateSeparator(messageDate!),
                _buildMessageBubble(message, currentUid),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _messageStatusSubscription?.cancel();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = AuthService.instance.currentUser;

    if (currentUser == null) {
      return const Scaffold(
        backgroundColor: background,
        body: Center(
          child: Text(
            'Please sign in again.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: accent.withOpacity(0.2),
              child: Text(
                _getInitial(widget.otherUser.displayName),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.otherUser.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '@${widget.otherUser.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessages(currentUser.uid)),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              color: surface,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(color: Colors.white),
                      cursorColor: accent,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: background,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                          borderSide: const BorderSide(color: accent),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  SizedBox(
                    height: 48,
                    width: 48,
                    child: IconButton(
                      onPressed: _isSending ? null : _sendMessage,
                      style: IconButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                      ),
                      icon: _isSending
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
