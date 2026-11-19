import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StorageConnectionTest {
  static Future<void> testConnection() async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        debugPrint('TEST FAILED: No Firebase user is signed in.');
        return;
      }

      debugPrint('Firebase UID: ${user.uid}');

      final token = await user.getIdToken();

      if (token == null || token.isEmpty) {
        debugPrint('TEST FAILED: Firebase ID token unavailable.');
        return;
      }

      debugPrint('Firebase ID token obtained successfully.');

      final files = await Supabase.instance.client.storage
          .from('profile-photos')
          .list(path: user.uid);

      debugPrint('SUPABASE STORAGE CONNECTION SUCCESSFUL');
      debugPrint('Files found: ${files.length}');
    } catch (error, stackTrace) {
      debugPrint('SUPABASE STORAGE TEST FAILED: $error');
      debugPrint('Stack trace: $stackTrace');
    }
  }
}
