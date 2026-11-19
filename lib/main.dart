import 'package:material_ui/material_ui.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firebase_options.dart';
import 'features/authentication/screens/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Keep existing Firestore configuration.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );

  // Initialize Supabase using the existing Firebase user token.
  await Supabase.initialize(
    url: 'https://nozhhkmkroguqszbrabk.supabase.co',
    publishableKey: 'sb_publishable_tKgIPG9bbbkdiurI6IlWkw_QCeivHqf',
    accessToken: () async {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        return null;
      }

      return await user.getIdToken();
    },
  );

  runApp(const CloudChatApp());
}

class CloudChatApp extends StatelessWidget {
  const CloudChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cloud Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101827),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7568F5),
          brightness: Brightness.dark,
        ),
        fontFamily: 'Roboto',
      ),
      home: const AuthGate(),
    );
  }
}
