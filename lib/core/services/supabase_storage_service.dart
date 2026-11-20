import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseStorageService {
  SupabaseStorageService._();

  static final SupabaseStorageService instance = SupabaseStorageService._();

  final SupabaseClient _supabase = Supabase.instance.client;

  static const String _profileBucket = 'profile-photos';
  static const String _chatBucket = 'chat-attachments';

  Future<String> uploadProfilePhoto({
    required String uid,
    required Uint8List bytes,
    required String extension,
  }) async {
    final normalizedExtension = extension.toLowerCase();

    const allowedExtensions = ['jpg', 'jpeg', 'png', 'webp'];

    if (!allowedExtensions.contains(normalizedExtension)) {
      throw Exception('Please select a JPG, PNG or WEBP image.');
    }

    final contentType = switch (normalizedExtension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => throw Exception('Unsupported image format.'),
    };

    final path = '$uid/profile.$normalizedExtension';

    await _supabase.storage
        .from(_profileBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );

    return path;
  }

  Future<void> deleteProfilePhoto(String path) async {
    await _supabase.storage.from(_profileBucket).remove([path]);
  }

  Future<String> getProfilePhotoUrl(String path) async {
    return _supabase.storage.from(_profileBucket).createSignedUrl(path, 3600);
  }

  Future<String> uploadChatAttachment({
    required String uid,
    required String conversationId,
    required Uint8List bytes,
    required String extension,
    required String mimeType,
  }) async {
    if (bytes.isEmpty) {
      throw Exception('Attachment is empty.');
    }

    // Match the existing Firestore security rules.
    const maxSize = 20 * 1024 * 1024;
    const minSize = 1 * 1024; // 1 KB

    if (bytes.length < minSize || bytes.length > maxSize) {
      throw Exception('Attachment size must be between 1 KB and 20 MB.');
    }

    const allowedTypes = {
      'image/jpeg',
      'image/png',
      'image/webp',
      'application/pdf',
      'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.ms-excel',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.ms-powerpoint',
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'text/plain',
    };

    if (!allowedTypes.contains(mimeType)) {
      throw Exception('Unsupported attachment type.');
    }

    final normalizedExtension = extension.toLowerCase().replaceAll('.', '');

    const allowedExtensions = {
      'jpg',
      'jpeg',
      'png',
      'webp',
      'pdf',
      'doc',
      'docx',
      'xls',
      'xlsx',
      'ppt',
      'pptx',
      'txt',
    };

    if (!allowedExtensions.contains(normalizedExtension)) {
      throw Exception('Unsupported file extension.');
    }

    final fileId = DateTime.now().microsecondsSinceEpoch;

    final path = '$uid/$conversationId/$fileId.$normalizedExtension';

    await _supabase.storage
        .from(_chatBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );

    return path;
  }

  Future<void> deleteChatAttachment(String path) async {
    await _supabase.storage.from(_chatBucket).remove([path]);
  }
}
