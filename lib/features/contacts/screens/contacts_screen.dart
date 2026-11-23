import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/services/user_service.dart';
import '../../../shared/models/public_user_model.dart';
import '../../conversations/services/conversation_service.dart';
import '../../conversations/screens/chat_screen.dart';
import '../../../shared/widgets/profile_avatar.dart';

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
  Future<Map<String, dynamic>>? _phoneLookupFuture;
  Future<List<PublicUserModel>>? _phoneSearchFuture;
  bool _isOwnPhoneSearch = false;

  String _searchQuery = '';
  String? _openingUserId;
  String? _openingPhoneNumber;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _isPhoneQuery {
    final value = _searchQuery.trim();

    return value.isNotEmpty && RegExp(r'^[+0-9\s()-]+$').hasMatch(value);
  }

  String _normalizePhoneNumber(String value) {
    final cleaned = value.replaceAll(RegExp(r'[\s()-]'), '');

    if (RegExp(r'^[6-9]\d{9}$').hasMatch(cleaned)) {
      return '+91$cleaned';
    }

    if (RegExp(r'^91[6-9]\d{9}$').hasMatch(cleaned)) {
      return '+$cleaned';
    }

    if (RegExp(r'^\+91[6-9]\d{9}$').hasMatch(cleaned)) {
      return cleaned;
    }

    throw Exception('Enter a valid 10-digit Indian mobile number.');
  }

  String _digitsOnly(String value) => value.replaceAll(RegExp(r'\D'), '');

  void _onSearchChanged(String value, String currentUid) {
    final query = value.trim();
    final isPhone =
        query.isNotEmpty && RegExp(r'^[+0-9\s()-]+$').hasMatch(query);

    Future<Map<String, dynamic>>? lookupFuture;
    Future<List<PublicUserModel>>? phoneSearchFuture;
    var ownNumber = false;

    if (isPhone) {
      final digits = _digitsOnly(query);

      try {
        // A complete number keeps the existing exact lookup flow.
        final phoneNumber = _normalizePhoneNumber(query);
        final currentPhone =
            AuthService.instance.currentUser?.phoneNumber ?? '';
        ownNumber = _digitsOnly(currentPhone) == _digitsOnly(phoneNumber);

        if (!ownNumber) {
          lookupFuture = _lookupPhoneNumber(phoneNumber);
        }
      } catch (_) {
        // Partial phone search: match any part of a registered user's number.
        if (digits.length >= 2 && digits.length <= 10) {
          phoneSearchFuture = _searchPhoneUsers(digits);
        }
      }
    }

    setState(() {
      _searchQuery = query;
      _isOwnPhoneSearch = ownNumber;

      if (query.isEmpty) {
        _searchFuture = null;
        _phoneLookupFuture = null;
        _phoneSearchFuture = null;
      } else if (isPhone) {
        _searchFuture = null;
        _phoneLookupFuture = lookupFuture;
        _phoneSearchFuture = phoneSearchFuture;
      } else {
        _phoneLookupFuture = null;
        _phoneSearchFuture = null;
        _isOwnPhoneSearch = false;
        _searchFuture = UserService.instance.searchUsers(
          query: query,
          currentUid: currentUid,
        );
      }
    });
  }

  Future<List<PublicUserModel>> _searchPhoneUsers(String query) async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) throw Exception('Please sign in again.');

    final token = await currentUser.getIdToken();
    if (token == null || token.isEmpty) {
      throw Exception('Unable to authenticate. Please sign in again.');
    }

    final result = await Supabase.instance.client.functions.invoke(
      'create-or-find-phone-conversation',
      method: HttpMethod.post,
      headers: {'Authorization': 'Bearer $token'},
      body: {'action': 'searchPhone', 'query': query},
    );

    final data = result.data;
    if (data is! Map || data['success'] != true) {
      final message = data is Map ? data['error']?.toString() : null;
      throw Exception(message ?? 'Unable to search phone numbers.');
    }

    final users = data['users'];
    if (users is! List) return [];

    return users
        .whereType<Map>()
        .map((item) => PublicUserModel.fromMap(Map<String, dynamic>.from(item)))
        .where((user) => user.uid != currentUser.uid)
        .toList();
  }

  Future<Map<String, dynamic>> _lookupPhoneNumber(String phoneNumber) async {
    final currentUser = AuthService.instance.currentUser;

    if (currentUser == null) {
      throw Exception('Please sign in again.');
    }

    final firebaseToken = await currentUser.getIdToken();

    if (firebaseToken == null || firebaseToken.isEmpty) {
      throw Exception('Unable to authenticate. Please sign in again.');
    }

    final functionResponse = await Supabase.instance.client.functions.invoke(
      'create-or-find-phone-conversation',
      method: HttpMethod.post,
      headers: {'Authorization': 'Bearer $firebaseToken'},
      body: {'action': 'lookup', 'phoneNumber': phoneNumber},
    );

    final responseData = functionResponse.data;

    if (responseData is! Map) {
      throw Exception('Invalid response from server.');
    }

    final data = Map<String, dynamic>.from(responseData);

    if (data['success'] != true) {
      throw Exception(data['error'] ?? 'Unable to search this phone number.');
    }

    return data;
  }

  Future<void> _openConversation(PublicUserModel contact) async {
    if (_openingUserId != null || _openingPhoneNumber != null) {
      return;
    }

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

  Future<void> _openPhoneConversation() async {
    if (_openingUserId != null || _openingPhoneNumber != null) {
      return;
    }

    String phoneNumber;

    try {
      phoneNumber = _normalizePhoneNumber(_searchQuery);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
      return;
    }

    setState(() {
      _openingPhoneNumber = phoneNumber;
    });

    try {
      // We only look up the conversation ID here.
      // This must NOT create a pending Firestore document.
      final data = await _lookupPhoneNumber(phoneNumber);

      final conversationId = data['conversationId'] as String?;

      if (conversationId == null || conversationId.isEmpty) {
        throw Exception(
          'Conversation ID was not returned. Please update the Edge Function.',
        );
      }

      if (!mounted) return;

      if (data['alreadyRegistered'] == true) {
        // The phone number belongs to an existing Cloud Chat user.
        final recipientData = data['recipient'];

        if (recipientData is! Map) {
          throw Exception('Recipient profile could not be found.');
        }

        final recipient = Map<String, dynamic>.from(recipientData);

        final recipientUid = recipient['uid']?.toString();

        if (recipientUid == null || recipientUid.isEmpty) {
          throw Exception('Recipient information is missing.');
        }

        final contact = PublicUserModel.fromMap({
          ...recipient,
          'uid': recipientUid,
        });

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                ChatScreen(conversationId: conversationId, otherUser: contact),
          ),
        );
      } else {
        // The recipient is not registered.
        // Open the chat using the deterministic pending ID.
        // No pending conversation document is created at this point.
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              conversationId: conversationId,
              otherUser: null,
              recipientPhoneNumber: phoneNumber,
            ),
          ),
        );
      }
    } on FunctionException catch (e) {
      if (!mounted) return;

      final details = e.details;
      final message = details is Map ? details['error']?.toString() : null;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message ?? 'Unable to open conversation. Please try again.',
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
          _openingPhoneNumber = null;
        });
      }
    }
  }

  Widget _buildPhoneSearchResult() {
    if (_isOwnPhoneSearch) {
      return _buildEmptyState(
        icon: Icons.block_rounded,
        title: 'Cannot search your own number',
        subtitle: 'You cannot add or start a conversation with your own phone number.',
      );
    }

    String? normalizedPhone;
    try {
      normalizedPhone = _normalizePhoneNumber(_searchQuery);
    } catch (_) {
      normalizedPhone = null;
    }

    // Complete phone number: preserve exact lookup and unregistered-user flow.
    if (normalizedPhone != null) {
      final lookupFuture = _phoneLookupFuture;
      if (lookupFuture == null) {
        return _buildEmptyState(
          icon: Icons.phone_android_rounded,
          title: 'Searching...',
          subtitle: 'Checking the phone number.',
        );
      }

      return FutureBuilder<Map<String, dynamic>>(
        future: lookupFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: accent),
            );
          }
          if (snapshot.hasError) {
            return _buildEmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Search failed',
              subtitle: _friendlyError(snapshot.error),
            );
          }

          final data = snapshot.data;
          if (data == null) {
            return _buildEmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Something went wrong',
              subtitle: 'Please try searching again.',
            );
          }

          if (data['alreadyRegistered'] == true) {
            final recipientData = data['recipient'];
            if (recipientData is! Map) {
              return _buildEmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Profile unavailable',
                subtitle: 'Could not retrieve this user profile.',
              );
            }
            final recipient = Map<String, dynamic>.from(recipientData);
            final contact = PublicUserModel.fromMap({
              ...recipient,
              'uid': recipient['uid'],
            });
            return ListView(children: [_buildContactTile(contact)]);
          }

          final isOpening = _openingPhoneNumber == normalizedPhone;
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B2638),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: const Icon(
                        Icons.phone_android_rounded,
                        color: accent,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Not on Cloud Chat yet',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      normalizedPhone!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'You can still start a conversation. Your messages will be available when they register.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed:
                            _openingPhoneNumber != null ||
                                _openingUserId != null
                            ? null
                            : _openPhoneConversation,
                        icon: isOpening
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.chat_rounded),
                        label: Text(
                          isOpening
                              ? 'Opening conversation...'
                              : 'Chat with this number',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: accent.withValues(
                            alpha: 0.5,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    // Partial number: match registered users whose number starts with OR contains it.
    final digits = _digitsOnly(_searchQuery);
    if (digits.length < 2) {
      return _buildEmptyState(
        icon: Icons.phone_android_rounded,
        title: 'Search phone number',
        subtitle: 'Enter at least 2 digits to find matching users.',
      );
    }
    if (digits.length > 10) {
      return _buildEmptyState(
        icon: Icons.phone_android_rounded,
        title: 'Invalid phone number',
        subtitle: 'Enter a 10-digit Indian mobile number, optionally with +91.',
      );
    }

    final searchFuture = _phoneSearchFuture;
    if (searchFuture == null) {
      return const Center(child: CircularProgressIndicator(color: accent));
    }

    return FutureBuilder<List<PublicUserModel>>(
      future: searchFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: accent));
        }
        if (snapshot.hasError) {
          return _buildEmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Search failed',
            subtitle: _friendlyError(snapshot.error),
          );
        }
        final contacts = snapshot.data ?? [];
        if (contacts.isEmpty) {
          return _buildEmptyState(
            icon: Icons.person_search_rounded,
            title: 'No matching users',
            subtitle:
                'No registered users have a phone number containing "$digits".',
          );
        }
        return ListView.builder(
          itemCount: contacts.length,
          itemBuilder: (context, index) => _buildContactTile(contacts[index]),
        );
      },
    );
  }

  String _friendlyError(Object? error) {
    if (error is FunctionException) {
      final details = error.details;
      if (details is Map && details['error'] != null) {
        return details['error'].toString();
      }
    }

    final text = error?.toString() ?? '';
    if (text.contains('You cannot start a conversation with your own number')) {
      return 'You cannot add or start a conversation with your own phone number.';
    }
    return text
        .replaceFirst('Exception: ', '')
        .replaceFirst('FunctionException: ', '');
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
        leading: ProfileAvatar(
          name: contact.displayName,
          photoPath: contact.photoPath,
          radius: 25,
          backgroundColor: accent,
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
        onTap: _openingUserId != null || _openingPhoneNumber != null
            ? null
            : () => _openConversation(contact),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                textAlign: TextAlign.center,
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
        ),
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
              keyboardType: TextInputType.text,
              decoration: InputDecoration(
                hintText: 'Search username or phone number...',
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
              _searchQuery.isEmpty
                  ? 'All Users'
                  : _isPhoneQuery
                  ? 'Phone Number Results'
                  : 'Search Results',
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
                  : _isPhoneQuery
                  ? _buildPhoneSearchResult()
                  : _buildSearchResults(),
            ),
          ],
        ),
      ),
    );
  }
}
