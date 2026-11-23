import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/services/user_service.dart';

import '../../../core/services/auth_service.dart';
import '../../../shared/models/public_user_model.dart';
import '../../../shared/widgets/profile_avatar.dart';

import '../models/contact_model.dart';
import '../services/contact_service.dart';
import 'add_contact_screen.dart';

import '../../conversations/screens/chat_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  static const background = Color(0xFF101827);
  static const accent = Color(0xFF7568F5);
  static const surface = Color(0xFF1B2638);

  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String? _openingContactId;

  final Map<String, Stream<PublicUserModel?>> _profileStreams = {};

  Stream<PublicUserModel?> _getPublicProfileStream(String uid) {
    return _profileStreams.putIfAbsent(
      uid,
      () => UserService.instance.watchPublicProfile(uid),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _digitsOnly(String value) {
    return value.replaceAll(RegExp(r'\D'), '');
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // Add a contact.
  Future<void> _addContact() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddContactScreen()),
    );

    if (!mounted) return;

    if (result == true) {
      _showMessage('Contact added successfully.');
    }
  }

  // Edit an existing contact.

  Future<void> _editContact(ContactModel contact) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _EditContactDialog(contact: contact),
    );

    if (result == null || !mounted) return;

    try {
      await ContactService.instance.updateContact(
        contactId: contact.id,
        contactName: result['name']!,
        phoneNumber: result['phone']!,
      );

      try {
        await _matchContact(contact.id);

        _showMessage('Contact updated successfully.');
      } catch (matchingError) {
        debugPrint('CONTACT MATCH REFRESH FAILED: $matchingError');

        _showMessage('Contact updated, but matching could not be refreshed.');
      }
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  // Delete a contact.
  Future<void> _deleteContact(ContactModel contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: surface,
          title: const Text(
            'Delete Contact?',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            'Are you sure you want to delete ${contact.contactName}?',
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

    if (confirmed != true || !mounted) return;

    try {
      await ContactService.instance.deleteContact(contact.id);
      _showMessage('Contact deleted successfully.');
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  // Existing Edge Function lookup.
  Future<Map<String, dynamic>> _lookupPhoneNumber(String phoneNumber) async {
    final currentUser = AuthService.instance.currentUser;

    if (currentUser == null) {
      throw Exception('Please sign in again.');
    }

    final firebaseToken = await currentUser.getIdToken();

    if (firebaseToken == null || firebaseToken.isEmpty) {
      throw Exception('Unable to authenticate. Please sign in again.');
    }

    final response = await Supabase.instance.client.functions.invoke(
      'create-or-find-phone-conversation',
      method: HttpMethod.post,
      headers: {'Authorization': 'Bearer $firebaseToken'},
      body: {'action': 'lookup', 'phoneNumber': phoneNumber},
    );

    final responseData = response.data;

    if (responseData is! Map) {
      throw Exception('Invalid response from server.');
    }

    final data = Map<String, dynamic>.from(responseData);

    if (data['success'] != true) {
      throw Exception(
        data['error']?.toString() ?? 'Unable to find this contact.',
      );
    }

    return data;
  }

  Future<void> _matchContact(String contactId) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception('User is not authenticated.');
    }

    final firebaseToken = await user.getIdToken(true);

    if (firebaseToken == null || firebaseToken.isEmpty) {
      throw Exception('Unable to get Firebase authentication token.');
    }

    final response = await Supabase.instance.client.functions.invoke(
      'create-or-find-phone-conversation',
      method: HttpMethod.post,
      headers: {'Authorization': 'Bearer $firebaseToken'},
      body: {'action': 'matchContact', 'contactId': contactId},
    );

    if (response.data is! Map) {
      throw Exception('Invalid matching response.');
    }

    final data = Map<String, dynamic>.from(response.data as Map);

    if (data['success'] != true) {
      throw Exception(data['error']?.toString() ?? 'Contact matching failed.');
    }

    debugPrint(
      'CONTACT MATCH REFRESHED: '
      'matched=${data['matched']}, '
      'matchedUid=${data['matchedUid']}',
    );
  }

  // Open a conversation using the saved contact's phone number.
  Future<void> _openConversation(ContactModel contact) async {
    if (_openingContactId != null) return;

    final currentUser = AuthService.instance.currentUser;

    if (currentUser == null) {
      _showMessage('Please sign in again.');
      return;
    }

    if (_digitsOnly(currentUser.phoneNumber ?? '') ==
        _digitsOnly(contact.phoneNumber)) {
      _showMessage('You cannot start a conversation with yourself.');
      return;
    }

    setState(() {
      _openingContactId = contact.id;
    });

    try {
      final data = await _lookupPhoneNumber(contact.phoneNumber);

      final conversationId = data['conversationId']?.toString();

      if (conversationId == null || conversationId.isEmpty) {
        throw Exception('Conversation ID was not returned by the server.');
      }

      if (!mounted) return;

      if (data['alreadyRegistered'] == true) {
        final recipientData = data['recipient'];

        if (recipientData is! Map) {
          throw Exception('Recipient profile could not be found.');
        }

        final recipient = Map<String, dynamic>.from(recipientData);

        final recipientUid = recipient['uid']?.toString();

        if (recipientUid == null || recipientUid.isEmpty) {
          throw Exception('Recipient information is missing.');
        }

        final publicUser = PublicUserModel.fromMap({
          ...recipient,
          'uid': recipientUid,
        });

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              conversationId: conversationId,
              otherUser: publicUser,
            ),
          ),
        );
      } else {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              conversationId: conversationId,
              otherUser: null,
              recipientPhoneNumber: contact.phoneNumber,
            ),
          ),
        );
      }
    } on FunctionException catch (error) {
      if (!mounted) return;

      final details = error.details;
      final message = details is Map ? details['error']?.toString() : null;

      _showMessage(message ?? 'Unable to open conversation. Please try again.');
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _openingContactId = null;
        });
      }
    }
  }

  // Contact list with local search.
  Widget _buildContactsList() {
    return StreamBuilder<List<ContactModel>>(
      stream: ContactService.instance.watchContacts(),
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

        final allContacts = snapshot.data ?? [];

        final query = _searchQuery.toLowerCase();
        final queryDigits = _digitsOnly(query);

        final contacts = allContacts.where((contact) {
          if (query.isEmpty) return true;

          final nameMatches = contact.contactName.toLowerCase().contains(query);

          final phoneMatches =
              queryDigits.isNotEmpty &&
              _digitsOnly(contact.phoneNumber).contains(queryDigits);

          return nameMatches || phoneMatches;
        }).toList();

        if (allContacts.isEmpty) {
          return _buildEmptyState(
            icon: Icons.people_outline_rounded,
            title: 'No contacts yet',
            subtitle: 'Add your first contact to start a conversation.',
            showAddButton: true,
          );
        }

        if (contacts.isEmpty) {
          return _buildEmptyState(
            icon: Icons.search_off_rounded,
            title: 'No matching contacts',
            subtitle: 'Try another contact name or phone number.',
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

  Widget _buildContactTile(ContactModel contact) {
    final matchedUid = contact.matchedUid;

    // Unregistered contact: show saved name and phone number.
    if (matchedUid == null || matchedUid.isEmpty) {
      return _buildContactTileContent(contact);
    }

    // Registered contact: listen to their public profile.
    return StreamBuilder<PublicUserModel?>(
      stream: _getPublicProfileStream(matchedUid),
      builder: (context, snapshot) {
        final publicUser = snapshot.data;

        return _buildContactTileContent(contact, publicUser: publicUser);
      },
    );
  }

  Widget _buildContactTileContent(
    ContactModel contact, {
    PublicUserModel? publicUser,
  }) {
    final isOpening = _openingContactId == contact.id;

    final username = publicUser?.username.trim() ?? '';

    final subtitle = username.isNotEmpty ? '@$username' : contact.phoneNumber;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 7,
          ),
          leading: ProfileAvatar(
            name: contact.contactName,
            photoPath: publicUser?.photoPath,
            radius: 25,
            backgroundColor: accent,
          ),
          title: Text(
            contact.contactName,
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
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isOpening)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: accent,
                    strokeWidth: 2,
                  ),
                )
              else
                const Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: accent,
                  size: 21,
                ),
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: Colors.white54,
                ),
                color: surface,
                onSelected: (value) {
                  if (value == 'edit') {
                    _editContact(contact);
                  } else if (value == 'delete') {
                    _deleteContact(contact);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, color: Colors.white70),
                        SizedBox(width: 10),
                        Text('Edit', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: Colors.redAccent),
                        SizedBox(width: 10),
                        Text('Delete', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          onTap: _openingContactId != null
              ? null
              : () => _openConversation(contact),
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    bool showAddButton = false,
  }) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: surface,
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
              if (showAddButton) ...[
                const SizedBox(height: 22),
                ElevatedButton.icon(
                  onPressed: _addContact,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Add Contact'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
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
        actions: [
          IconButton(
            tooltip: 'Add Contact',
            onPressed: _addContact,
            icon: const Icon(Icons.person_add_alt_1_rounded, color: accent),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.trim();
                });
              },
              style: const TextStyle(color: Colors.white),
              cursorColor: accent,
              decoration: InputDecoration(
                hintText: 'Search your contacts...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Colors.white54,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white54,
                        ),
                      )
                    : null,
                filled: true,
                fillColor: surface,
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
            const Text(
              'My Contacts',
              style: TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 18),
            Expanded(child: _buildContactsList()),
          ],
        ),
      ),
    );
  }
}

class _EditContactDialog extends StatefulWidget {
  final ContactModel contact;

  const _EditContactDialog({required this.contact});

  @override
  State<_EditContactDialog> createState() => _EditContactDialogState();
}

class _EditContactDialogState extends State<_EditContactDialog> {
  static const surface = Color(0xFF1B2638);
  static const background = Color(0xFF101827);
  static const accent = Color(0xFF7568F5);

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();

    _nameController = TextEditingController(text: widget.contact.contactName);

    _phoneController = TextEditingController(text: widget.contact.phoneNumber);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String? _normalizePhoneNumber(String value) {
    final cleaned = value.trim().replaceAll(RegExp(r'[\s()-]'), '');

    if (cleaned.startsWith('+')) {
      return RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(cleaned) ? cleaned : null;
    }

    final digits = cleaned.replaceAll(RegExp(r'\D'), '');

    if (RegExp(r'^[6-9]\d{9}$').hasMatch(digits)) {
      return '+91$digits';
    }

    if (RegExp(r'^91[6-9]\d{9}$').hasMatch(digits)) {
      return '+$digits';
    }

    return null;
  }

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38),
      filled: true,
      fillColor: background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: accent),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final phone = _normalizePhoneNumber(_phoneController.text);

    if (phone == null) return;

    Navigator.pop(context, {
      'name': _nameController.text.trim(),
      'phone': phone,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: surface,
      title: const Text('Edit Contact', style: TextStyle(color: Colors.white)),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: _decoration('Contact name'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter a contact name';
                }

                if (value.trim().length > 80) {
                  return 'Name cannot exceed 80 characters';
                }

                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Colors.white),
              decoration: _decoration('Phone number'),
              validator: (value) {
                if (value == null || _normalizePhoneNumber(value) == null) {
                  return 'Enter a valid phone number';
                }

                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
          ),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
