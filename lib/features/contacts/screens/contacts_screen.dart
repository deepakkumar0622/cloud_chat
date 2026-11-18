import 'package:material_ui/material_ui.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/services/user_service.dart';
import '../../../shared/models/public_user_model.dart';
import '../../conversations/services/conversation_service.dart';
import '../../conversations/screens/chat_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  static const background = Color(0xFF101827);
  static const accent = Color(0xFF7568F5);

  final TextEditingController _searchController = TextEditingController();

  Future<List<PublicUserModel>>? _searchFuture;

  String _searchQuery = '';
  String? _openingUserId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value, String currentUid) {
    final query = value.trim();

    setState(() {
      _searchQuery = query;

      if (query.isEmpty) {
        _searchFuture = null;
      } else {
        _searchFuture = UserService.instance.searchUsers(
          query: query,
          currentUid: currentUid,
        );
      }
    });
  }

  String _getInitial(String name) {
    final trimmedName = name.trim();

    if (trimmedName.isEmpty) return '?';

    return trimmedName[0].toUpperCase();
  }

  Future<void> _openConversation(PublicUserModel contact) async {
    if (_openingUserId != null) return;

    setState(() {
      _openingUserId = contact.uid;
    });

    try {
      final currentUser = AuthService.instance.currentUser;

      if (currentUser == null) {
        throw Exception('Please sign in again.');
      }

      final conversationId = ConversationService.instance
          .generateConversationId(currentUser.uid, contact.uid);

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              ChatScreen(conversationId: conversationId, otherUser: contact),
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
          _openingUserId = null;
        });
      }
    }
  }

  Widget _buildContactTile(PublicUserModel contact) {
    final isOpening = _openingUserId == contact.uid;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2638),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        leading: CircleAvatar(
          radius: 25,
          backgroundColor: accent.withOpacity(0.2),
          child: Text(
            _getInitial(contact.displayName),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          contact.displayName.isNotEmpty ? contact.displayName : 'Unknown user',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            contact.username.isNotEmpty
                ? '@${contact.username}'
                : 'Username unavailable',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
        trailing: isOpening
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(color: accent, strokeWidth: 2),
              )
            : const Icon(
                Icons.chat_bubble_outline_rounded,
                color: accent,
                size: 21,
              ),
        onTap: _openingUserId != null ? null : () => _openConversation(contact),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1B2638),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(icon, size: 48, color: accent),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    return FutureBuilder<List<PublicUserModel>>(
      future: _searchFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: accent));
        }

        if (snapshot.hasError) {
          return _buildEmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Search failed',
            subtitle: 'Unable to search users. Please try again.',
          );
        }

        final contacts = snapshot.data ?? [];

        if (contacts.isEmpty) {
          return _buildEmptyState(
            icon: Icons.person_search_rounded,
            title: 'No users found',
            subtitle: 'Try searching with another username.',
          );
        }

        return ListView.builder(
          itemCount: contacts.length,
          itemBuilder: (context, index) {
            return _buildContactTile(contacts[index]);
          },
        );
      },
    );
  }

  Widget _buildAllContacts(String currentUid) {
    return StreamBuilder<List<PublicUserModel>>(
      stream: UserService.instance.watchContacts(currentUid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: accent));
        }

        if (snapshot.hasError) {
          return _buildEmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Unable to load contacts',
            subtitle: 'Please check your connection and try again.',
          );
        }

        final contacts = snapshot.data ?? [];

        if (contacts.isEmpty) {
          return _buildEmptyState(
            icon: Icons.people_outline_rounded,
            title: 'No contacts found',
            subtitle: 'There are no other registered users yet.',
          );
        }

        return ListView.builder(
          itemCount: contacts.length,
          itemBuilder: (context, index) {
            return _buildContactTile(contacts[index]);
          },
        );
      },
    );
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
            style: TextStyle(color: Colors.white70),
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
        title: const Text(
          'Contacts',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _searchController,
              onChanged: (value) {
                _onSearchChanged(value, currentUser.uid);
              },
              style: const TextStyle(color: Colors.white),
              cursorColor: accent,
              decoration: InputDecoration(
                hintText: 'Search by username...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Colors.white54,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('', currentUser.uid);
                        },
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white54,
                        ),
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF1B2638),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: const BorderSide(color: accent, width: 1),
                ),
              ),
            ),

            const SizedBox(height: 25),

            Text(
              _searchQuery.isEmpty ? 'All Users' : 'Search Results',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 18),

            Expanded(
              child: _searchQuery.isEmpty
                  ? _buildAllContacts(currentUser.uid)
                  : _buildSearchResults(),
            ),
          ],
        ),
      ),
    );
  }
}
