import 'package:material_ui/material_ui.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/contact_service.dart';

class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key});

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String? _normalizePhoneNumber(String value) {
    final input = value.trim();
    final cleaned = input.replaceAll(RegExp(r'[\s()-]'), '');

    if (cleaned.startsWith('+')) {
      if (RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(cleaned)) {
        return cleaned;
      }

      return null;
    }

    final digits = cleaned.replaceAll(RegExp(r'\D'), '');

    if (RegExp(r'^[6-9][0-9]{9}$').hasMatch(digits)) {
      return '+91$digits';
    }

    if (RegExp(r'^91[6-9][0-9]{9}$').hasMatch(digits)) {
      return '+$digits';
    }

    return null;
  }

  // Automatically match the saved contact with a registered Cloud Chat user.
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
      'CONTACT MATCH RESULT: '
      'matched=${data['matched']}, '
      'matchedUid=${data['matchedUid']}',
    );
  }

  Future<void> _saveContact() async {
    if (!_formKey.currentState!.validate()) return;

    final normalizedPhone = _normalizePhoneNumber(_phoneController.text);

    if (normalizedPhone == null) {
      _showMessage('Enter a valid phone number with country code.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Step 1: Save the contact in Firestore.
      final contactId = await ContactService.instance.addContact(
        contactName: _nameController.text,
        phoneNumber: normalizedPhone,
      );

      // Step 2: Automatically check whether this number is registered.
      try {
        await _matchContact(contactId);
      } catch (matchingError) {
        // Do not fail contact creation if matching fails.
        debugPrint('AUTOMATIC CONTACT MATCHING FAILED: $matchingError');
      }

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;

      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101827),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101827),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Add Contact'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                const Text(
                  'Create a new contact',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Save a name and phone number to start a conversation.',
                  style: TextStyle(color: Colors.white60, fontSize: 14),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Contact Name',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration(
                    hint: 'Enter contact name',
                    icon: Icons.person_outline,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a contact name';
                    }

                    if (value.trim().length > 80) {
                      return 'Name cannot exceed 80 characters';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 24),
                const Text(
                  'Phone Number',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration(
                    hint: '+91 98765 43210',
                    icon: Icons.phone_outlined,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a phone number';
                    }

                    if (_normalizePhoneNumber(value) == null) {
                      return 'Enter a valid phone number';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  'Indian mobile numbers can be entered with or without +91. '
                  'For other countries, include the country code.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveContact,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7568F5),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF7568F5)
                          .withValues(alpha: 0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Save Contact',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38),
      prefixIcon: Icon(icon, color: Colors.white54),
      filled: true,
      fillColor: const Color(0xFF1B2638),
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
        borderSide: const BorderSide(color: Color(0xFF7568F5)),
      ),
    );
  }
}
