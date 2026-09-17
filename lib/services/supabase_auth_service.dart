import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mboistats/services/auth_service.dart';

class SupabaseAuthService {
  Future<bool> signInWithGoogle(BuildContext context) async {
    try {
      final res = await AuthService.signInWithGoogle();
      return res != null;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
      return false;
    }
  }

  Future<void> signOut() async {
    await AuthService.signOut();
  }

  bool isLoggedIn() {
    return Supabase.instance.client.auth.currentUser != null;
  }

  Stream<AuthState> get authStateChanges => Supabase.instance.client.auth.onAuthStateChange;
  User? get currentUser => Supabase.instance.client.auth.currentUser;

  String? getUsername() {
    return Supabase.instance.client.auth.currentUser?.userMetadata?['full_name'];
  }

  String? getEmail() {
    return Supabase.instance.client.auth.currentUser?.email;
  }
}