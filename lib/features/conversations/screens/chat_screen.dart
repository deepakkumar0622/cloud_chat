import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:file_saver/file_saver.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../contacts/screens/add_contact_screen.dart';
import '../services/chat_pagination_service.dart';
import '../../contacts/services/contact_service.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/services/supabase_storage_service.dart';
import '../../../shared/models/public_user_model.dart';
import '../../../shared/models/message_model.dart';
import '../../messaging/services/message_service.dart';
import '../../../shared/widgets/profile_avatar.dart';
import '../widgets/chat_message_list.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/chat_attachment_widget.dart';
import '../widgets/message_bubble.dart';
import '../widgets/image_viewer_screen.dart';

class _CachedAttachmentUrl {
  final Future<Map<String, dynamic>> future;
  final DateTime expiresAt;

  _CachedAttachmentUrl(this.future, this.expiresAt);
}

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final PublicUserModel? otherUser;
  final String? recipientPhoneNumber;

  const ChatScreen({
    super.key,
    required this.conversationId,
    this.otherUser,
    this.recipientPhoneNumber,
  }) : assert(otherUser != null || recipientPhoneNumber != null);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const background = Color(0xFF101827);
  static const accent = Color(0xFF7568F5);
  static const surface = Color(0xFF1B2638);

  late final ChatPaginationService _paginationService;
  late final Stream<String?> _contactNameStream;

  Map<String, dynamic>? _chatUserDetails;
  bool _isLoadingChatUserDetails = false;

  // Minimum chat loading duration.
  bool _isChatLoading = true;

  final ScrollController _messageScrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  final Set<String> _deletingMessageIds = {};
  final Set<String> _openingAttachmentIds = {};

  final Map<String, _CachedAttachmentUrl> _attachmentUrlCache = {};

  bool _isSending = false;
  bool _isUpdatingMessageStatuses = false;
  bool _pendingMessageStatusUpdate = false;
  bool _conversationReady = false;
  bool _listenersActivated = false;

  @override
  void initState() {
    super.initState();

    debugPrint('========== CHAT SCREEN DEBUG ==========');
    debugPrint('Conversation ID: ${widget.conversationId}');
    debugPrint('Other User ID: ${widget.otherUser?.uid}');
    debugPrint('Recipient Phone: ${widget.recipientPhoneNumber}');
    debugPrint('Current User UID: ${AuthService.instance.currentUser?.uid}');
    debugPrint('========================================');

    _paginationService = ChatPaginationService(
      conversationId: widget.conversationId,
      pageSize: 5,
    );

    _contactNameStream = ContactService.instance.watchContactName(
      phoneNumber: widget.recipientPhoneNumber,
      matchedUid: widget.otherUser?.uid,
    );

    // Start initialization tasks in parallel.
    _checkExistingConversation();
    unawaited(_loadChatUserDetails());
    unawaited(_finishChatLoading());
  }

  // ---------------------------------------------------------------------------
  // CHAT LOADING
  // ---------------------------------------------------------------------------

  Future<void> _finishChatLoading() async {
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    setState(() {
      _isChatLoading = false;
    });
  }

  Widget _buildMessagesLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 32,
            width: 32,
            child: CircularProgressIndicator(color: accent, strokeWidth: 3),
          ),
          SizedBox(height: 16),
          Text(
            'Loading conversation...',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CONVERSATION INITIALIZATION
  // ---------------------------------------------------------------------------

  Future<void> _checkExistingConversation() async {
    final currentUser = AuthService.instance.currentUser;

    if (currentUser == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId)
          .get();

      if (!mounted || !snapshot.exists) return;

      final data = snapshot.data();

      if (data == null) return;

      final participants = List<String>.from(data['participants'] ?? []);

      if (!participants.contains(currentUser.uid)) {
        debugPrint('Current user is not a conversation participant.');
        return;
      }

      if (widget.conversationId.startsWith('pending_')) {
        final status = data['status'];

        if (status != 'pending' && status != 'active') {
          return;
        }
      }

      _activateMessageListeners();
    } catch (e) {
      debugPrint('CONVERSATION INITIALIZATION: $e');
    }
  }

  void _activateMessageListeners() {
    if (!mounted || _listenersActivated) return;

    _listenersActivated = true;
    setState(() => _conversationReady = true);

    _paginationService.addListener(_onPaginatedMessagesChanged);
    unawaited(_paginationService.startListening());
  }

  void _onPaginatedMessagesChanged() {
    if (_paginationService.isInitialLoading) return;

    if (_isUpdatingMessageStatuses) {
      _pendingMessageStatusUpdate = true;
      return;
    }

    unawaited(_markLoadedMessagesReadAndDelivered());
  }

  Future<void> _markLoadedMessagesReadAndDelivered() async {
    if (_isUpdatingMessageStatuses || !mounted) return;

    _isUpdatingMessageStatuses = true;

    try {
      await MessageService.instance.markMessagesReadAndDelivered(
        conversationId: widget.conversationId,
        messages: _paginationService.messages,
      );
    } catch (e) {
      debugPrint('MESSAGE STATUS ERROR: $e');
    } finally {
      _isUpdatingMessageStatuses = false;

      if (_pendingMessageStatusUpdate && mounted) {
        _pendingMessageStatusUpdate = false;
        unawaited(_markLoadedMessagesReadAndDelivered());
      }
    }
  }

  Future<void> _loadChatUserDetails() async {
    if (widget.otherUser == null) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    if (mounted) {
      setState(() => _isLoadingChatUserDetails = true);
    }

    try {
      final token = await user.getIdToken(true);

      if (token == null || token.isEmpty) {
        throw Exception('Unable to get authentication token.');
      }

      final result = await Supabase.instance.client.functions.invoke(
        'create-or-find-phone-conversation',
        method: HttpMethod.post,
        headers: {'Authorization': 'Bearer $token'},
        body: {
          'action': 'getChatUserDetails',
          'conversationId': widget.conversationId,
        },
      );

      if (result.data is! Map) {
        throw Exception('Invalid contact details response.');
      }

      final data = Map<String, dynamic>.from(result.data as Map);

      if (data['success'] != true) {
        throw Exception(
          data['error']?.toString() ?? 'Unable to retrieve contact details.',
        );
      }

      if (!mounted) return;

      setState(() {
        _chatUserDetails = data;
      });
    } catch (error) {
      debugPrint('CHAT USER DETAILS ERROR: $error');
    } finally {
      if (mounted) {
        setState(() => _isLoadingChatUserDetails = false);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // FORMATTERS
  // ---------------------------------------------------------------------------

  String _formatTime(DateTime? date) {
    if (date == null) return '';
    return DateFormat('h:mm a').format(date.toLocal());
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

    return mimeTypes[extension.toLowerCase()] ?? 'application/octet-stream';
  }

  String _extensionOf(String? fileName) {
    if (fileName == null || !fileName.contains('.')) return '';
    return fileName.split('.').last.toLowerCase();
  }

  String _fileNameWithoutExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0) return fileName;
    return fileName.substring(0, dotIndex);
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _showSuccess(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String? get _recipientPhone {
    final phone =
        _chatUserDetails?['phoneNumber'] ?? widget.recipientPhoneNumber;

    if (phone is String && phone.trim().isNotEmpty) {
      return phone.trim();
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // SEND TEXT MESSAGE
  // ---------------------------------------------------------------------------

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
        otherUserId: widget.otherUser?.uid,
        recipientPhoneNumber: widget.recipientPhoneNumber,
        text: text,
      );

      _activateMessageListeners();

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

  // ---------------------------------------------------------------------------
  // ATTACHMENT OPTIONS
  // ---------------------------------------------------------------------------

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

      if (files.isEmpty) return;

      final PlatformFile pickedFile = files.first;
      final Uint8List bytes = await pickedFile.readAsBytes();

      await _uploadAndSendAttachment(
        bytes: bytes,
        fileName: pickedFile.name,
        extension: pickedFile.extension ?? '',
        mimeType: _getMimeType(pickedFile.extension ?? ''),
        messageType: 'file',
      );
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  // ---------------------------------------------------------------------------
  // UPLOAD AND SEND ATTACHMENT
  // ---------------------------------------------------------------------------

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
        otherUserId: widget.otherUser?.uid,
        recipientPhoneNumber: widget.recipientPhoneNumber,
        messageType: messageType,
        attachmentPath: uploadedPath,
        fileName: fileName,
        mimeType: mimeType,
        fileSize: bytes.length,
      );

      _activateMessageListeners();

      _showSuccess('Attachment sent.');
    } catch (e) {
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

  // ---------------------------------------------------------------------------
  // SECURE ATTACHMENT DOWNLOAD
  // ---------------------------------------------------------------------------

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

  Future<Uint8List> _downloadAttachment(MessageModel message) async {
    final data = await _getAttachmentData(message);
    final url = data['signedUrl'] as String?;

    if (url == null || url.isEmpty) {
      throw Exception('Attachment URL is unavailable.');
    }

    final response = await http.get(Uri.parse(url));

    if (response.statusCode != 200) {
      throw Exception(
        'Unable to download attachment. Status: ${response.statusCode}',
      );
    }

    if (response.bodyBytes.isEmpty) {
      throw Exception('The downloaded attachment is empty.');
    }

    return response.bodyBytes;
  }

  Future<File> _createTemporaryFile(
    MessageModel message,
    Uint8List bytes,
  ) async {
    Directory directory;

    try {
      directory = await getTemporaryDirectory();
    } catch (e) {
      debugPrint('getTemporaryDirectory failed, using systemTemp: $e');
      directory = Directory.systemTemp;
    }

    final fileName = (message.fileName ?? 'attachment').replaceAll(
      RegExp(r'[^a-zA-Z0-9._-]'),
      '_',
    );

    final file = File('${directory.path}/$fileName');

    await file.writeAsBytes(bytes, flush: true);

    return file;
  }

  // ---------------------------------------------------------------------------
  // ATTACHMENT ACTION MENU
  // ---------------------------------------------------------------------------

  Future<void> _showAttachmentActions(MessageModel message) async {
    if (_openingAttachmentIds.contains(message.id)) return;

    final isImage = message.isImageMessage;

    final selected = await showModalBottomSheet<String>(
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
                const SizedBox(height: 15),
                Text(
                  message.fileName ?? (isImage ? 'Image' : 'Document'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                ListTile(
                  leading: const Icon(Icons.visibility_rounded, color: accent),
                  title: const Text(
                    'View',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    isImage ? 'View image inside Cloud Chat' : 'Open document',
                    style: const TextStyle(color: Colors.white54),
                  ),
                  onTap: () => Navigator.pop(context, 'view'),
                ),
                ListTile(
                  leading: const Icon(Icons.download_rounded, color: accent),
                  title: const Text(
                    'Save to device',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    isImage ? 'Save to your Gallery' : 'Save to Downloads',
                    style: const TextStyle(color: Colors.white54),
                  ),
                  onTap: () => Navigator.pop(context, 'save'),
                ),
                ListTile(
                  leading: const Icon(Icons.share_rounded, color: accent),
                  title: const Text(
                    'Share',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Share using another application',
                    style: TextStyle(color: Colors.white54),
                  ),
                  onTap: () => Navigator.pop(context, 'share'),
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

    if (!mounted || selected == null) return;

    if (selected == 'view') {
      await _viewAttachment(message);
    } else if (selected == 'save') {
      await _saveAttachment(message);
    } else if (selected == 'share') {
      await _shareAttachment(message);
    }
  }

  Future<void> _startAttachmentAction(
    MessageModel message,
    Future<void> Function() action,
  ) async {
    if (_openingAttachmentIds.contains(message.id)) return;

    setState(() {
      _openingAttachmentIds.add(message.id);
    });

    try {
      await action();
    } catch (e, st) {
      debugPrint('ATTACHMENT ACTION ERROR: $e\n$st');
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _openingAttachmentIds.remove(message.id);
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // VIEW IMAGE / DOCUMENT
  // ---------------------------------------------------------------------------

  Future<void> _viewAttachment(MessageModel message) async {
    await _startAttachmentAction(message, () async {
      final bytes = await _downloadAttachment(message);

      if (!mounted) return;

      if (message.isImageMessage) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ImageViewerScreen(
              bytes: bytes,
              fileName: message.fileName ?? 'Image',
            ),
          ),
        );

        return;
      }

      final extension = _extensionOf(message.fileName);
      final file = await _createTemporaryFile(message, bytes);

      final result = await OpenFilex.open(
        file.path,
        type: message.mimeType ?? _getMimeType(extension),
      );

      if (result.type != ResultType.done) {
        throw Exception(
          result.message.isNotEmpty
              ? result.message
              : 'No app was found to open this file.',
        );
      }
    });
  }

  // ---------------------------------------------------------------------------
  // CONTACT INFORMATION
  // ---------------------------------------------------------------------------

  Future<void> _showContactInformation({
    required String? savedContactName,
  }) async {
    final phoneNumber = _recipientPhone;

    final isSaved =
        savedContactName != null && savedContactName.trim().isNotEmpty;

    final username = _chatUserDetails?['username']?.toString() ?? '';

    final shouldAddContact = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Center(
                  child: ProfileAvatar(
                    name: isSaved ? savedContactName : 'Unknown Contact',
                    photoPath: widget.otherUser?.photoPath,
                    radius: 36,
                    backgroundColor: accent,
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: Text(
                    isSaved ? savedContactName : 'Unknown Contact',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                const Divider(color: Colors.white12),
                const SizedBox(height: 12),
                if (phoneNumber != null)
                  _buildContactInfoRow(
                    Icons.phone_outlined,
                    'Mobile number',
                    phoneNumber,
                  ),
                if (username.isNotEmpty)
                  _buildContactInfoRow(
                    Icons.alternate_email_rounded,
                    'Username',
                    '@$username',
                  ),
                _buildContactInfoRow(
                  Icons.verified_user_outlined,
                  'Account status',
                  widget.otherUser != null
                      ? 'Registered Cloud Chat user'
                      : 'Not registered yet',
                ),
                const SizedBox(height: 22),
                if (!isSaved && phoneNumber != null)
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext, true);
                      },
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text('Add to Contacts'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || shouldAddContact != true || phoneNumber == null) {
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddContactScreen(initialPhoneNumber: phoneNumber),
      ),
    );
  }

  Widget _buildContactInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const SizedBox(width: 2),
          Icon(icon, color: accent, size: 21),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SAVE TO DEVICE
  // ---------------------------------------------------------------------------

  MimeType _getFileSaverMimeType(String extension) {
    switch (extension.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return MimeType.jpeg;
      case 'png':
        return MimeType.png;
      case 'webp':
        return MimeType.webp;
      case 'pdf':
        return MimeType.pdf;
      case 'doc':
      case 'docx':
        return MimeType.microsoftWord;
      case 'xls':
      case 'xlsx':
        return MimeType.microsoftExcel;
      case 'ppt':
      case 'pptx':
        return MimeType.microsoftPresentation;
      case 'txt':
        return MimeType.text;
      default:
        return MimeType.other;
    }
  }

  Future<void> _saveAttachment(MessageModel message) async {
    await _startAttachmentAction(message, () async {
      final bytes = await _downloadAttachment(message);
      final fileName = message.fileName ?? 'attachment';
      final extension = _extensionOf(fileName);

      if (message.isImageMessage) {
        await FileSaver.instance.saveToGallery(
          name: _fileNameWithoutExtension(fileName),
          bytes: bytes,
          fileExtension: extension,
          mimeType: _getFileSaverMimeType(extension),
          album: 'Cloud Chat',
        );

        _showSuccess('Image saved to Gallery.');
      } else {
        await FileSaver.instance.saveToDownloads(
          name: _fileNameWithoutExtension(fileName),
          bytes: bytes,
          fileExtension: extension,
          mimeType: _getFileSaverMimeType(extension),
          subfolder: 'Cloud Chat',
        );

        _showSuccess('Document saved to Downloads/Cloud Chat.');
      }
    });
  }

  // ---------------------------------------------------------------------------
  // SHARE ATTACHMENT
  // ---------------------------------------------------------------------------

  Future<void> _shareAttachment(MessageModel message) async {
    await _startAttachmentAction(message, () async {
      final bytes = await _downloadAttachment(message);
      final file = await _createTemporaryFile(message, bytes);

      if (!await file.exists()) {
        throw Exception('Unable to prepare the file for sharing.');
      }

      if (!mounted) return;

      final box = context.findRenderObject() as RenderBox?;
      final fileName = message.fileName ?? 'attachment';

      final result = await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              file.path,
              name: fileName,
              mimeType:
                  message.mimeType ?? _getMimeType(_extensionOf(fileName)),
            ),
          ],
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );

      debugPrint('SHARE RESULT: ${result.status}');
    });
  }

  // ---------------------------------------------------------------------------
  // MESSAGE DISPLAY HELPERS
  // ---------------------------------------------------------------------------

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

        return ChatAttachmentWidget(
          onTap: () => _showAttachmentActions(message),
          isOpening: _openingAttachmentIds.contains(message.id),
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
              errorBuilder: (context, error, stackTrace) => Container(
                width: 220,
                height: 130,
                alignment: Alignment.center,
                color: Colors.black12,
                child: const Text(
                  'Image unavailable',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFileAttachment(MessageModel message) {
    final isOpening = _openingAttachmentIds.contains(message.id);

    return ChatAttachmentWidget(
      onTap: () => _showAttachmentActions(message),
      isOpening: isOpening,
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
                  const SizedBox(height: 4),
                  const Text(
                    'Tap for options',
                    style: TextStyle(color: Colors.white54, fontSize: 10),
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
                    Icons.more_vert_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DELETE MESSAGE
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // MESSAGE BUBBLE
  // ---------------------------------------------------------------------------

  Widget _buildMessageBubble(MessageModel message, String currentUid) {
    final isMe = message.senderId == currentUid;
    final isDeleted = message.isDeletedForEveryone;
    final isDeleting = _deletingMessageIds.contains(message.id);

    final statusIcon = message.readAt != null || message.deliveredAt != null
        ? Icons.done_all_rounded
        : Icons.done_rounded;

    final statusColor = message.readAt != null
        ? Colors.lightBlueAccent
        : Colors.white70;

    Widget content;

    if (isDeleted) {
      content = Row(
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
      );
    } else if (message.isImageMessage) {
      content = _buildImageAttachment(message);
    } else if (message.isFileMessage) {
      content = _buildFileAttachment(message);
    } else {
      content = Text(
        message.text,
        style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
      );
    }

    return MessageBubble(
      isMe: isMe,
      isDeleted: isDeleted,
      isDeleting: isDeleting,
      content: content,
      time: _formatTime(message.createdAt),
      statusIcon: statusIcon,
      statusColor: statusColor,
      onLongPress: isDeleted || isDeleting
          ? null
          : () => _showDeleteOptions(message, currentUid),
    );
  }

  // ---------------------------------------------------------------------------
  // EMPTY CHAT
  // ---------------------------------------------------------------------------

  Widget _buildEmptyMessages(String recipientName) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.waving_hand_rounded, color: accent, size: 45),
          const SizedBox(height: 15),
          Text(
            'Say hello to $recipientName!',
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

  // ---------------------------------------------------------------------------
  // MESSAGES LIST
  // ---------------------------------------------------------------------------

  Widget _buildMessages(String currentUid, String recipientName) {
    if (_isChatLoading) {
      return _buildMessagesLoading();
    }

    if (!_conversationReady) {
      return _buildEmptyMessages(recipientName);
    }

    return AnimatedBuilder(
      animation: _paginationService,
      builder: (context, _) {
        final messages = _paginationService.messages.where((message) {
          return !message.deletedFor.contains(currentUid);
        }).toList();

        return ChatMessageList(
          messages: messages,
          scrollController: _messageScrollController,
          isLoading: _paginationService.isInitialLoading,
          isLoadingMore: _paginationService.isLoadingMore,
          hasMoreMessages: _paginationService.hasMoreMessages,
          error: _paginationService.error,
          emptyBuilder: (_) => _buildEmptyMessages(recipientName),
          onLoadMore: () => unawaited(_paginationService.loadOlderMessages()),
          itemBuilder: (message) => _buildMessageBubble(message, currentUid),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // DISPOSE
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    if (_listenersActivated) {
      _paginationService.removeListener(_onPaginatedMessagesChanged);
    }

    _paginationService.dispose();
    _messageScrollController.dispose();
    _messageController.dispose();

    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // SCREEN UI
  // ---------------------------------------------------------------------------

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

    return StreamBuilder<String?>(
      stream: _contactNameStream,
      builder: (context, snapshot) {
        final savedContactName = snapshot.data?.trim();

        final recipientName =
            savedContactName != null && savedContactName.isNotEmpty
            ? savedContactName
            : 'Unknown Contact';

        final phoneNumber = _recipientPhone;

        return Scaffold(
          backgroundColor: background,
          appBar: AppBar(
            backgroundColor: background,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            titleSpacing: 0,
            title: Row(
              children: [
                ProfileAvatar(
                  name: recipientName,
                  photoPath: widget.otherUser?.photoPath,
                  radius: 20,
                  backgroundColor: accent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        recipientName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        phoneNumber ??
                            (_isLoadingChatUserDetails
                                ? 'Loading number...'
                                : 'Phone number unavailable'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Contact information',
                  onPressed: () {
                    _showContactInformation(savedContactName: savedContactName);
                  },
                  icon: const Icon(Icons.info_outline_rounded, color: accent),
                ),
              ],
            ),
          ),
          body: Column(
            children: [
              Expanded(child: _buildMessages(currentUser.uid, recipientName)),
              SafeArea(
                top: false,
                child: ChatInputBar(
                  controller: _messageController,
                  isSending: _isSending,
                  onAttach: _showAttachmentOptions,
                  onSend: _sendMessage,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
