import 'package:cloud_chat/shared/models/user_model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/services/user_service.dart';

import 'phone_login_screen.dart';
import '../../profile/screens/profile_creation_screen.dart';
import '../../conversations/screens/home_screen.dart';
import '../../../core/services/storage_connection_test.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _testedUid;

  Future<void>? _setupFuture;
  String? _setupUid;

  Future<void> _ensureUserSetup(User user) {
    if (_setupUid != user.uid || _setupFuture == null) {
      _setupUid = user.uid;
      _setupFuture = UserService.instance.createUserIfNotExists(user);
    }

    return _setupFuture!;
  }

  void _testStorageOnce(String uid) {
    if (_testedUid == uid) return;

    _testedUid = uid;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        StorageConnectionTest.testConnection();
      }
    });
  }

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
          _setupUid = null;
          _setupFuture = null;
          return const PhoneLoginScreen();
        }

        return FutureBuilder<void>(
          key: ValueKey(user.uid),
          future: _ensureUserSetup(user),
          builder: (context, setupSnapshot) {
            if (setupSnapshot.connectionState == ConnectionState.waiting) {
              return const LoadingScreen();
            }

            if (setupSnapshot.hasError) {
              return _errorScreen(
                'Account initialization failed',
                setupSnapshot.error.toString(),
              );
            }

            return StreamBuilder<UserModel?>(
              key: ValueKey('profile_${user.uid}'),
              stream: UserService.instance.watchUser(user.uid),
              builder: (context, profileSnapshot) {
                if (profileSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const LoadingScreen();
                }

                if (profileSnapshot.hasError) {
                  return _errorScreen(
                    'Profile loading failed',
                    profileSnapshot.error.toString(),
                  );
                }

                final profile = profileSnapshot.data;

                if (profile == null || !profile.profileCompleted) {
                  return ProfileCreationScreen(user: user);
                }

                _testStorageOnce(user.uid);

                return const HomeScreen();
              },
            );
          },
        );
      },
    );
  }

  Widget _errorScreen(String title, String error) {
    return Scaffold(
      backgroundColor: const Color(0xFF101827),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF101827),
      body: Center(child: CircularProgressIndicator(color: Color(0xFF7568F5))),
    );
  }
}
