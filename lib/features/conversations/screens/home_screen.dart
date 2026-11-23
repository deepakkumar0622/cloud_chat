import 'package:material_ui/material_ui.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/services/user_service.dart';
import '../../../shared/models/public_user_model.dart';
import '../../conversations/services/conversation_service.dart';
import '../../conversations/models/conversation_model.dart';
import '../../contacts/screens/contacts_screen.dart';
import '../../contacts/services/contact_service.dart';
import '../../../shared/widgets/profile_avatar.dart';
import '../../profile/screens/edit_profile_screen.dart';
import 'chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const background = Color(0xFF101827);
  static const accent = Color(0xFF7568F5);

  late final Stream<List<ConversationModel>> _conversationStream;
  late final Stream<PublicUserModel?> _currentProfileStream;

  // Keep one (broadcast) profile stream per participant.
  final Map<String, Stream<PublicUserModel?>> _profileStreams = {};

  // Last known profile per participant.
  final Map<String, PublicUserModel?> _profileCache = {};

  @override
  void initState() {
    super.initState();

    final user = AuthService.instance.currentUser;

    if (user != null) {
      _conversationStream = ConversationService.instance.watchConversations();

      _currentProfileStream = UserService.instance.watchPublicProfile(user.uid);
    } else {
      _conversationStream = Stream.value([]);
      _currentProfileStream = Stream.value(null);
    }
  }

  // ---------------------------------------------------------------------------
  // PROFILE STREAM
  // ---------------------------------------------------------------------------

  Stream<PublicUserModel?> _getProfileStream(String uid) {
    return _profileStreams.putIfAbsent(
      uid,
      () => UserService.instance.watchPublicProfile(uid).map((profile) {
        _profileCache[uid] = profile;
        return profile;
      }).asBroadcastStream(),
    );
  }

  // ---------------------------------------------------------------------------
  // LOCAL CONTACT NAME STREAM
  // ---------------------------------------------------------------------------

  Stream<String?> _getContactNameStream({
    String? phoneNumber,
    String? matchedUid,
  }) {
    return ContactService.instance.watchContactName(
      phoneNumber: phoneNumber,
      matchedUid: matchedUid,
    );
  }

  String _resolveContactName(String? savedName) {
    final name = savedName?.trim();

    if (name != null && name.isNotEmpty) {
      return name;
    }

    return 'Unknown contact';
  }

  // ---------------------------------------------------------------------------
  // DATE FORMATTER
  // ---------------------------------------------------------------------------

  String _formatConversationDate(DateTime? date) {
    if (date == null) return 'New conversation';

    final localDate = date.toLocal();
    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);

    final conversationDay = DateTime(
      localDate.year,
      localDate.month,
      localDate.day,
    );

    if (conversationDay == today) {
      return 'Today';
    }

    if (conversationDay == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    }

    return '${localDate.day}/${localDate.month}/${localDate.year}';
  }

  // ---------------------------------------------------------------------------
  // OPEN CHAT
  // ---------------------------------------------------------------------------

  void _openChat({
    required ConversationModel conversation,
    PublicUserModel? otherUser,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          conversationId: conversation.id,
          otherUser: otherUser,
          recipientPhoneNumber: conversation.isPending
              ? conversation.recipientPhoneNumber
              : null,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PENDING CONVERSATION TILE
  // ---------------------------------------------------------------------------

  Widget _buildPendingConversationTile(ConversationModel conversation) {
    final conversationDate = _formatConversationDate(
      conversation.lastMessageAt ?? conversation.createdAt,
    );

    return StreamBuilder<String?>(
      stream: _getContactNameStream(
        phoneNumber: conversation.recipientPhoneNumber,
      ),
      builder: (context, snapshot) {
        final contactName = _resolveContactName(snapshot.data);

        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            _openChat(conversation: conversation);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Row(
              children: [
                ProfileAvatar(
                  name: contactName,
                  radius: 25,
                  backgroundColor: accent,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contactName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            color: Colors.orangeAccent,
                            size: 13,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'Not registered yet',
                            style: TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  conversationDate,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // REGISTERED CONVERSATION TILE
  // ---------------------------------------------------------------------------

  Widget _buildRegisteredConversationTile(
    ConversationModel conversation,
    String otherUserId,
  ) {
    return StreamBuilder<PublicUserModel?>(
      stream: _getProfileStream(otherUserId),
      initialData: _profileCache[otherUserId],
      builder: (context, profileSnapshot) {
        if (profileSnapshot.hasError) {
          debugPrint(
            'Profile loading error for $otherUserId: '
            '${profileSnapshot.error}',
          );

          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 15),
            child: Text(
              'Unable to load this user profile.',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        if (profileSnapshot.connectionState == ConnectionState.waiting &&
            !profileSnapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 15),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: accent, strokeWidth: 2),
              ),
            ),
          );
        }

        final profile = profileSnapshot.data;

        final conversationDate = _formatConversationDate(
          conversation.lastMessageAt ?? conversation.createdAt,
        );

        return StreamBuilder<String?>(
          stream: _getContactNameStream(matchedUid: otherUserId),
          builder: (context, contactSnapshot) {
            final contactName = _resolveContactName(contactSnapshot.data);

            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: profile == null
                  ? null
                  : () {
                      _openChat(conversation: conversation, otherUser: profile);
                    },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 4,
                ),
                child: Row(
                  children: [
                    ProfileAvatar(
                      name: contactName,
                      photoPath: profile?.photoPath,
                      radius: 25,
                      backgroundColor: accent,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        contactName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      conversationDate,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // CONVERSATION TILE SELECTOR
  // ---------------------------------------------------------------------------

  Widget _buildConversationTile(
    ConversationModel conversation,
    String currentUid,
  ) {
    if (conversation.isPending) {
      return _buildPendingConversationTile(conversation);
    }

    final otherUserId = conversation.participants.firstWhere(
      (uid) => uid != currentUid,
      orElse: () => '',
    );

    if (otherUserId.isEmpty) {
      return const SizedBox.shrink();
    }

    return _buildRegisteredConversationTile(conversation, otherUserId);
  }

  // ---------------------------------------------------------------------------
  // CONVERSATION LIST
  // ---------------------------------------------------------------------------

  Widget _buildConversationList(String currentUid) {
    return StreamBuilder<List<ConversationModel>>(
      stream: _conversationStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: accent));
        }

        if (snapshot.hasError && !snapshot.hasData) {
          return const Center(
            child: Text(
              'Unable to load conversations.',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        final conversations = snapshot.data ?? [];

        if (conversations.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(25),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B2638),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: const Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 55,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'No conversations yet',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Find people and start your first conversation.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: conversations.length,
          separatorBuilder: (context, index) => Divider(
            height: 1,
            thickness: 1,
            indent: 68,
            color: Colors.white.withValues(alpha: 0.07),
          ),
          itemBuilder: (context, index) {
            final conversation = conversations[index];

            return KeyedSubtree(
              key: ValueKey(conversation.id),
              child: _buildConversationTile(conversation, currentUid),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // MAIN SCREEN
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;

    if (user == null) {
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
        title: const Row(
          children: [
            Icon(Icons.cloud_rounded, color: accent),
            SizedBox(width: 10),
            Text(
              'Cloud Chat',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          StreamBuilder<PublicUserModel?>(
            stream: _currentProfileStream,
            builder: (context, snapshot) {
              final profile = snapshot.data;

              if (profile == null) {
                return const SizedBox.shrink();
              }

              return IconButton(
                tooltip: 'Edit Profile',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EditProfileScreen(profile: profile),
                    ),
                  );
                },
                icon: ProfileAvatar(
                  name: profile.displayName,
                  photoPath: profile.photoPath,
                  radius: 16,
                  backgroundColor: accent,
                ),
              );
            },
          ),
          IconButton(
            onPressed: () async {
              await AuthService.instance.signOut();
            },
            icon: const Icon(Icons.logout_rounded, color: Colors.white),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<PublicUserModel?>(
        stream: _currentProfileStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: accent),
            );
          }

          if (snapshot.hasError && !snapshot.hasData) {
            return const Center(
              child: Text(
                'Unable to load your profile.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          final profile = snapshot.data;

          final name = profile?.displayName.isNotEmpty == true
              ? profile!.displayName
              : 'User';

          return Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Text(
                  'Hello, $name 👋',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Stay connected with everyone.',
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                ),
                const SizedBox(height: 35),
                const Text(
                  'Messages',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(child: _buildConversationList(user.uid)),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ContactsScreen()),
          );
        },
        backgroundColor: accent,
        child: const Icon(Icons.add_comment_rounded, color: Colors.white),
      ),
    );
  }
}
