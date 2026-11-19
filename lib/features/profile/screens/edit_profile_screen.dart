import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/user_service.dart';
import '../../../core/services/supabase_storage_service.dart';
import '../../../shared/models/public_user_model.dart';
import '../../../shared/widgets/profile_avatar.dart';

class EditProfileScreen extends StatefulWidget {
  final PublicUserModel profile;

  const EditProfileScreen({super.key, required this.profile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const background = Color(0xFF101827);
  static const surface = Color(0xFF1B2638);
  static const accent = Color(0xFF7568F5);

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _imagePicker = ImagePicker();

  Uint8List? _selectedImage;
  String? _selectedExtension;

  bool _removePhoto = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    _nameController.text = widget.profile.displayName;
    _usernameController.text = widget.profile.username;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
        maxHeight: 1200,
      );

      if (image == null) return;

      final extension = image.name.split('.').last.toLowerCase();

      if (!['jpg', 'jpeg', 'png', 'webp'].contains(extension)) {
        _showMessage('Please select a JPG, PNG or WEBP image.');
        return;
      }

      final bytes = await image.readAsBytes();

      if (!mounted) return;

      setState(() {
        _selectedImage = bytes;
        _selectedExtension = extension;
        _removePhoto = false;
      });
    } catch (e) {
      _showMessage('Unable to select image.');
    }
  }

  void _removeSelectedPhoto() {
    setState(() {
      _selectedImage = null;
      _selectedExtension = null;
      _removePhoto = true;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: surface));
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();

    setState(() => _isSaving = true);

    String? uploadedPath;
    final oldPhotoPath = widget.profile.photoPath;

    try {
      // Upload the new image if one was selected.
      if (_selectedImage != null && _selectedExtension != null) {
        uploadedPath = await SupabaseStorageService.instance.uploadProfilePhoto(
          uid: widget.profile.uid,
          bytes: _selectedImage!,
          extension: _selectedExtension!,
        );
      }

      // Update the public profile and username atomically.
      await UserService.instance.updateProfile(
        uid: widget.profile.uid,
        displayName: _nameController.text,
        username: _usernameController.text,
        photoPath: uploadedPath,
        removePhoto: _removePhoto,
      );

      // Delete the previous image only after Firestore succeeds.
      if (oldPhotoPath != null &&
          oldPhotoPath.isNotEmpty &&
          oldPhotoPath != uploadedPath &&
          (uploadedPath != null || _removePhoto)) {
        try {
          await SupabaseStorageService.instance.deleteProfilePhoto(
            oldPhotoPath,
          );
        } catch (_) {
          // Profile update succeeded. Old image cleanup can be retried later.
        }
      }

      if (!mounted) return;

      _showMessage('Profile updated successfully.');

      Navigator.pop(context, true);
    } catch (e) {
      // Clean up a newly uploaded image if the Firestore update failed.
      if (uploadedPath != null && uploadedPath != oldPhotoPath) {
        try {
          await SupabaseStorageService.instance.deleteProfilePhoto(
            uploadedPath,
          );
        } catch (_) {}
      }

      if (!mounted) return;

      _showMessage(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildPhotoPreview() {
    if (_selectedImage != null) {
      return CircleAvatar(
        radius: 55,
        backgroundImage: MemoryImage(_selectedImage!),
      );
    }

    if (_removePhoto) {
      return CircleAvatar(
        radius: 55,
        backgroundColor: accent.withValues(alpha: 0.2),
        child: const Icon(Icons.person_rounded, size: 55, color: Colors.white),
      );
    }

    return ProfileAvatar(
      name: widget.profile.displayName,
      photoPath: widget.profile.photoPath,
      radius: 55,
      backgroundColor: accent,
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54),
      filled: true,
      fillColor: surface,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        title: const Text(
          'Edit Profile',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 15),

                Center(
                  child: Column(
                    children: [
                      _buildPhotoPreview(),

                      const SizedBox(height: 15),

                      TextButton.icon(
                        onPressed: _isSaving ? null : _pickImage,
                        icon: const Icon(
                          Icons.camera_alt_outlined,
                          color: accent,
                        ),
                        label: const Text(
                          'Change Profile Photo',
                          style: TextStyle(color: accent),
                        ),
                      ),

                      if (widget.profile.photoPath != null ||
                          _selectedImage != null)
                        TextButton(
                          onPressed: _isSaving ? null : _removeSelectedPhoto,
                          child: const Text(
                            'Remove Photo',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 35),

                const Text(
                  'Personal Information',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 20),

                TextFormField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white),
                  textCapitalization: TextCapitalization.words,
                  decoration: _inputDecoration('Display Name'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your display name.';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 20),

                TextFormField(
                  controller: _usernameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('Username').copyWith(
                    prefixText: '@',
                    prefixStyle: const TextStyle(color: Colors.white70),
                  ),
                  validator: (value) {
                    final username = value?.trim() ?? '';

                    if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(username)) {
                      return 'Use 3-20 letters, numbers or underscores.';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 8),

                const Text(
                  'Other users can find you using your username.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),

                const SizedBox(height: 35),

                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      disabledBackgroundColor: accent.withValues(alpha: 0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Save Changes',
                            style: TextStyle(
                              color: Colors.white,
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
}
