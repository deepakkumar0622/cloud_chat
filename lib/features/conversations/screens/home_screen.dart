
import 'package:material_ui/material_ui.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/services/user_service.dart';
import '../../../shared/models/public_user_model.dart';
import '../../conversations/services/conversation_service.dart';
import '../../conversations/models/conversation_model.dart';
import '../../contacts/screens/contacts_screen.dart';
import 'chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const background = Color(0xFF101827);
  static const accent = Color(0xFF7568F5);

  // Keep one profile stream per participant.
  final Map<String, Stream<PublicUserModel?>> _profileStreams = {};

  Stream<PublicUserModel?> _getProfileStream(String uid) {
    return _profileStreams.putIfAbsent(
      uid,
      () => UserService.instance.watchPublicProfile(uid),
    );
  }

  String _getInitial(String name) {
    final trimmedName = name.trim();

    if (trimmedName.isEmpty) return '?';

    return trimmedName[0].toUpperCase();
  }

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

  Widget _buildConversationTile(
    ConversationModel conversation,
    String currentUid,
  ) {
    final otherUserId = conversation.participants.firstWhere(
      (uid) => uid != currentUid,
      orElse: () => '',
    );

    if (otherUserId.isEmpty) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<PublicUserModel?>(
      stream: _getProfileStream(otherUserId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 15),
            child: Center(
              child: CircularProgressIndicator(
                color: accent,
                strokeWidth: 2,
              ),
            ),
          );
        }

        final profile = snapshot.data;

        final displayName =
            profile?.displayName.isNotEmpty == true
                ? profile!.displayName
                : 'Unknown user';

        final username =
            profile?.username.isNotEmpty == true
                ? '@${profile!.username}'
                : 'Profile unavailable';

        final conversationDate = _formatConversationDate(
          conversation.lastMessageAt ?? conversation.createdAt,
        );

        return InkWell(
  borderRadius: BorderRadius.circular(16),
  onTap: profile == null
      ? null
      : () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(
                conversationId: conversation.id,
                otherUser: profile,
              ),
            ),
          );
        },
          child: Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: accent.withOpacity(0.2),
                child: Text(
                  _getInitial(displayName),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                  ],
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
        );
      },
    );
  }

  Widget _buildConversationList(String currentUid) {
    return StreamBuilder<List<ConversationModel>>(
      stream: ConversationService.instance.watchConversations(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: accent),
          );
        }

        if (snapshot.hasError) {
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
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: conversations.length,
          itemBuilder: (context, index) {
            return _buildConversationTile(
              conversations[index],
              currentUid,
            );
          },
        );
      },
    );
  }

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
          IconButton(
            onPressed: () {},
            icon: const Icon(
              Icons.search_rounded,
              color: Colors.white,
            ),
          ),
          IconButton(
            onPressed: () async {
              await AuthService.instance.signOut();
            },
            icon: const Icon(
              Icons.logout_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),

      body: StreamBuilder<PublicUserModel?>(
        stream: UserService.instance.watchPublicProfile(user.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: accent),
            );
          }

          if (snapshot.hasError) {
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
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                  ),
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

                Expanded(
                  child: _buildConversationList(user.uid),
                ),
              ],
            ),
          );
        },
      ),

     floatingActionButton: FloatingActionButton(
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ContactsScreen(),
      ),
    );
  },
  backgroundColor: accent,
  child: const Icon(
    Icons.add_comment_rounded,
    color: Colors.white,
  ),
),
    );
  }
}
