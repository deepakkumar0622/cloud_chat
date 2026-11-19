import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/services/supabase_storage_service.dart';
import '../../../shared/models/public_user_model.dart';
import '../../../shared/models/message_model.dart';
import '../../messaging/services/message_service.dart';
import '../../../shared/widgets/profile_avatar.dart';

import 'dart:typed_data';

class _CachedAttachmentUrl {
  final Future<Map<String, dynamic>> future;
  final DateTime expiresAt;

  _CachedAttachmentUrl(this.future, this.expiresAt);
}

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
  final ImagePicker _imagePicker = ImagePicker();

  StreamSubscription<List<MessageModel>>? _messageStatusSubscription;

  final Set<String> _deletingMessageIds = {};
  final Set<String> _openingAttachmentIds = {};

  final Map<String, _CachedAttachmentUrl> _attachmentUrlCache = {};

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

    if (messageDate == today) return 'Today';

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

    return '${localDate.day} ${months[localDate.month - 1]} ${localDate.year}';
  }

  String _getMimeType(String extension) {
    const mimeTypes = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp',
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'txt': 'text/plain',
    };

    return mimeTypes[extension.toLowerCase()] ?? '';
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  // Attachment selection menu.
  Future<void> _showAttachmentOptions() async {
    if (_isSending) return;

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Share attachment',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 15),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF302A59),
                    child: Icon(Icons.image_rounded, color: accent),
                  ),
                  title: const Text(
                    'Photos',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Share an image from your gallery',
                    style: TextStyle(color: Colors.white54),
                  ),
                  onTap: () => Navigator.pop(context, 'image'),
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF302A59),
                    child: Icon(Icons.insert_drive_file_rounded, color: accent),
                  ),
                  title: const Text(
                    'Documents',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'PDF, Word, Excel, PowerPoint and TXT',
                    style: TextStyle(color: Colors.white54),
                  ),
                  onTap: () => Navigator.pop(context, 'file'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || selected == null) return;

    if (selected == 'image') {
      await _pickImage();
    } else if (selected == 'file') {
      await _pickDocument();
    }
  }

  // Select image from gallery.
  Future<void> _pickImage() async {
    try {
      final pickedImage = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );

      if (pickedImage == null) return;

      final bytes = await pickedImage.readAsBytes();
      final extension = pickedImage.name.split('.').last.toLowerCase();
      final mimeType = _getMimeType(extension);

      if (!mimeType.startsWith('image/')) {
        _showError('Unsupported image format.');
        return;
      }

      await _uploadAndSendAttachment(
        bytes: bytes,
        fileName: pickedImage.name,
        extension: extension,
        mimeType: mimeType,
        messageType: 'image',
      );
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  // Select document.
  Future<void> _pickDocument() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'doc',
          'docx',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
          'txt',
        ],
      );

      // User cancelled the picker.
      if (files.isEmpty) return;

      final PlatformFile pickedFile = files.first;

      // Read selected file as Uint8List.
      final Uint8List bytes = await pickedFile.readAsBytes();

      // Continue with your existing upload logic.
      await _uploadAndSendAttachment(
        bytes: bytes,
        fileName: pickedFile.name,
        extension: pickedFile.extension ?? '',
        mimeType: _getMimeType(pickedFile.extension ?? ''),
        messageType: 'file',
      );
    } catch (e) {
      debugPrint('Document picker error: $e');
    }
  }

  // Upload to Supabase, then create the Firestore message.
  Future<void> _uploadAndSendAttachment({
    required Uint8List bytes,
    required String fileName,
    required String extension,
    required String mimeType,
    required String messageType,
  }) async {
    if (_isSending) return;

    final currentUser = AuthService.instance.currentUser;

    if (currentUser == null) {
      _showError('Please sign in again.');
      return;
    }

    setState(() {
      _isSending = true;
    });

    String? uploadedPath;

    try {
      uploadedPath = await SupabaseStorageService.instance.uploadChatAttachment(
        uid: currentUser.uid,
        conversationId: widget.conversationId,
        bytes: bytes,
        extension: extension,
        mimeType: mimeType,
      );

      await MessageService.instance.sendAttachmentMessage(
        conversationId: widget.conversationId,
        otherUserId: widget.otherUser.uid,
        messageType: messageType,
        attachmentPath: uploadedPath,
        fileName: fileName,
        mimeType: mimeType,
        fileSize: bytes.length,
      );

      if (!mounted) return;
    } catch (e) {
      // Remove the uploaded object if the Firestore write fails.
      if (uploadedPath != null) {
        try {
          await SupabaseStorageService.instance.deleteChatAttachment(
            uploadedPath,
          );
        } catch (cleanupError) {
          debugPrint('ATTACHMENT CLEANUP ERROR: $cleanupError');
        }
      }

      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  // Get a cached signed URL. Refresh it after four minutes.
  Future<Map<String, dynamic>> _getAttachmentData(MessageModel message) {
    final cached = _attachmentUrlCache[message.id];

    if (cached != null && DateTime.now().isBefore(cached.expiresAt)) {
      return cached.future;
    }

    final future = MessageService.instance.getChatAttachmentUrl(
      conversationId: widget.conversationId,
      messageId: message.id,
    );

    _attachmentUrlCache[message.id] = _CachedAttachmentUrl(
      future,
      DateTime.now().add(const Duration(minutes: 4)),
    );

    return future;
  }

  Future<void> _openAttachment(MessageModel message) async {
    if (_openingAttachmentIds.contains(message.id)) return;

    setState(() {
      _openingAttachmentIds.add(message.id);
    });

    try {
      final data = await _getAttachmentData(message);
      final url = data['signedUrl'] as String?;

      if (url == null) {
        throw Exception('Attachment URL is unavailable.');
      }

      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );

      if (!opened) {
        throw Exception('Unable to open this attachment.');
      }
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _openingAttachmentIds.remove(message.id);
        });
      }
    }
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '';

    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }

    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _fileIcon(String? mimeType) {
    if (mimeType == 'application/pdf') {
      return Icons.picture_as_pdf_rounded;
    }

    if (mimeType?.contains('word') == true) {
      return Icons.description_rounded;
    }

    if (mimeType?.contains('spreadsheet') == true ||
        mimeType == 'application/vnd.ms-excel') {
      return Icons.table_chart_rounded;
    }

    if (mimeType?.contains('presentation') == true ||
        mimeType == 'application/vnd.ms-powerpoint') {
      return Icons.slideshow_rounded;
    }

    return Icons.insert_drive_file_rounded;
  }

  Widget _buildImageAttachment(MessageModel message) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _getAttachmentData(message),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: 220,
            height: 150,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2,
            ),
          );
        }

        final url = snapshot.data?['signedUrl'] as String?;

        if (snapshot.hasError || url == null) {
          return const SizedBox(
            width: 220,
            child: Text(
              'Unable to load image.',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        return GestureDetector(
          onTap: () => _openAttachment(message),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              url,
              width: 220,
              height: 220,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;

                return Container(
                  width: 220,
                  height: 150,
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 220,
                  height: 130,
                  alignment: Alignment.center,
                  color: Colors.black12,
                  child: const Text(
                    'Image unavailable',
                    style: TextStyle(color: Colors.white70),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildFileAttachment(MessageModel message) {
    final isOpening = _openingAttachmentIds.contains(message.id);

    return GestureDetector(
      onTap: () => _openAttachment(message),
      child: Container(
        width: 230,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(_fileIcon(message.mimeType), color: Colors.white, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.fileName ?? 'Attachment',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatFileSize(message.fileSize),
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 5),
            isOpening
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(
                    Icons.download_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
          ],
        ),
      ),
    );
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
      _showError(e.toString().replaceFirst('Exception: ', ''));
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
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'This message was deleted',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                )
              else if (message.isImageMessage)
                _buildImageAttachment(message)
              else if (message.isFileMessage)
                _buildFileAttachment(message)
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
                      color: Colors.white.withValues(alpha: 0.65),
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
            ProfileAvatar(
              name: widget.otherUser.displayName,
              photoPath: widget.otherUser.photoPath,
              radius: 20,
              backgroundColor: accent,
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
              padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
              color: surface,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: _isSending ? null : _showAttachmentOptions,
                    icon: const Icon(
                      Icons.attach_file_rounded,
                      color: Colors.white70,
                    ),
                    tooltip: 'Attach file',
                  ),
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
