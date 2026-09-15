import 'package:flutter/material.dart';
import 'package:mboistats/services/logger_service.dart';
import 'package:mboistats/theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mboistats/services/recommendation_service.dart';
import 'package:mboistats/services/auth_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  @override
  void initState() {
    super.initState();
    LoggerService.logActivity(
      actionType: 'view_page',
      sectorCategory: 'auth',
      itemName: 'Halaman Login',
    );

    // Dengarkan perubahan state autentikasi (berguna untuk deep link callback)
    Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      final AuthChangeEvent event = data.event;
      if (event == AuthChangeEvent.signedIn) {
        RecommendationService.clearLocalCache();
        final currentUser = Supabase.instance.client.auth.currentUser;
        LoggerService.logActivity(
          actionType: 'login_success',
          sectorCategory: 'auth',
          itemName: 'Login Google Sukses',
          userId: currentUser?.email ?? currentUser?.id,
        );
        final hasProfile = await RecommendationService.checkProfileExists();
        if (mounted) {
          if (hasProfile) {
            Navigator.pushReplacementNamed(context, '/main');
          } else {
            Navigator.pushReplacementNamed(context, '/onboarding');
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // Background illustration at the bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Image.asset(
              'assets_v2/icons/login_bg.png',
              width: double.infinity,
              fit: BoxFit.fitWidth,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 40),

                  // Welcome Header Text
                  const Text(
                    'Selamat',
                    style: TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      fontWeight: FontWeight.w800,
                      fontSize: 44,
                      color: Color(0xFF29A9E0),
                      height: 1.1,
                    ),
                  ),
                  const Text(
                    'Datang',
                    style: TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      fontWeight: FontWeight.w800,
                      fontSize: 44,
                      color: Color(0xFF6DC4EB),
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'di MBOIStats+',
                    style: TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      fontWeight: FontWeight.bold,
                      fontSize: 28,
                      color: Color(0xFFE27D60),
                    ),
                  ),

                  const SizedBox(height: 44),

                  // Google SSO Login Button (Pill shape)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF29A9E0),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    onPressed: () async {
                      try {
                        final authResponse =
                            await AuthService.signInWithGoogle();
                        if (authResponse == null) {
                          return;
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Gagal masuk: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'assets_v2/icons/google_login.png',
                          width: 20,
                          height: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Masuk dengan Google',
                          style: pjsBold14.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // "atau" separator
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.0),
                    child: Center(
                      child: Text(
                        'atau',
                        style: TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF828282),
                        ),
                      ),
                    ),
                  ),

                  // Guest Mode Button (Outlined Pill shape)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF29A9E0), width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    onPressed: () {
                      LoggerService.logActivity(
                        actionType: 'login_as_guest',
                        sectorCategory: 'auth',
                        itemName: 'Masuk Mode Tamu',
                        userId: 'anonymous',
                      );
                      Navigator.pushReplacementNamed(context, '/main');
                    },
                    child: const Text(
                      'Masuk sebagai Tamu',
                      style: TextStyle(
                        fontFamily: 'PlusJakartaSans',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF29A9E0),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
