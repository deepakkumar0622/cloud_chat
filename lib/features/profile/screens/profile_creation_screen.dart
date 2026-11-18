
import 'package:material_ui/material_ui.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/services/user_service.dart';

class ProfileCreationScreen extends StatefulWidget {
  final User user;

  const ProfileCreationScreen({
    super.key,
    required this.user,
  });

  @override
  State<ProfileCreationScreen> createState() =>
      _ProfileCreationScreenState();
}

class _ProfileCreationScreenState
    extends State<ProfileCreationScreen> {
  final nameController = TextEditingController();
  final usernameController = TextEditingController();

  bool loading = false;

  static const background = Color(0xFF101827);
  static const surface = Color(0xFF1B2638);
  static const accent = Color(0xFF7568F5);

  Future<void> saveProfile() async {
    final name = nameController.text.trim();
    final username = usernameController.text.trim().toLowerCase();

    if (name.isEmpty || username.isEmpty) {
      _showMessage('Please complete all fields.');
      return;
    }

    if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(username)) {
      _showMessage(
        'Username must be 3–20 characters and contain only letters, numbers or underscores.',
      );
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() => loading = true);

    try {
      await UserService.instance.createProfile(
        uid: widget.user.uid,
        displayName: name,
        username: username,
      );

      if (!mounted) return;

      _showMessage('Your profile has been created successfully.');
      
      // AuthGate listens to Firestore and automatically opens Home.
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 26,
              vertical: 30,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: Icon(
                      Icons.cloud_rounded,
                      color: accent,
                      size: 48,
                    ),
                  ),

                  const SizedBox(height: 32),

                  const Center(
                    child: Text(
                      'Create your profile',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  const Center(
                    child: Text(
                      'Let people know who you are.',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 15,
                      ),
                    ),
                  ),

                  const SizedBox(height: 38),

                  Center(
                    child: CircleAvatar(
                      radius: 55,
                      backgroundColor: surface,
                      child: const Icon(
                        Icons.person_rounded,
                        size: 55,
                        color: Colors.white54,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  const Center(
                    child: Text(
                      'Profile photo coming next',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ),

                  const SizedBox(height: 35),

                  const Text(
                    'Full name',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 10),

                  _buildField(
                    controller: nameController,
                    hint: 'Enter your name',
                    icon: Icons.person_outline,
                  ),

                  const SizedBox(height: 22),

                  const Text(
                    'Username',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 10),

                  _buildField(
                    controller: usernameController,
                    hint: 'Choose a username',
                    icon: Icons.alternate_email,
                  ),

                  const SizedBox(height: 12),

                  const Text(
                    'Your username will help others find you.',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                    ),
                  ),

                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: loading ? null : saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: loading
                          ? const CircularProgressIndicator(
                              color: Colors.white,
                            )
                          : const Text(
                              'Save & Continue',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      enabled: !loading,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(icon, color: accent),
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
