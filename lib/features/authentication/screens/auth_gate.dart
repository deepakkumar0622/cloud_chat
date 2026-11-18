
import 'package:material_ui/material_ui.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/services/user_service.dart';

import 'phone_login_screen.dart';
import '../../profile/screens/profile_creation_screen.dart';
import '../../conversations/screens/home_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.instance.authStateChanges,
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        }

        final user = authSnapshot.data;

        if (user == null) {
          return const PhoneLoginScreen();
        }

        return StreamBuilder(
          stream: UserService.instance.watchUser(user.uid),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState ==
                ConnectionState.waiting) {
              return const LoadingScreen();
            }

            if (profileSnapshot.hasError) {
              return const Scaffold(
                body: Center(
                  child: Text('Unable to load your profile.'),
                ),
              );
            }

            final profile = profileSnapshot.data;

            if (profile == null || !profile.profileCompleted) {
              return ProfileCreationScreen(user: user);
            }

            return const HomeScreen();
          },
        );
      },
    );
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF101827),
      body: Center(
        child: CircularProgressIndicator(
          color: Color(0xFF7568F5),
        ),
      ),
    );
  }
}
