import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'api_service.dart';
import 'responder_login.dart';
import 'responder_home.dart';

/// Shown briefly on every app launch. Decides whether to send the
/// responder straight to Home (still logged in) or to Login (logged
/// out, or their session/token is no longer valid on the server).
///
/// Meanwhile the phone's splash screen stays up (item 51: navy with the
/// logo, made by flutter_native_splash — see pubspec.yaml and main.dart),
/// and Login or Home comes straight after it. On a weak signal the check
/// can take a while, so the splash screen goes after 3 seconds at most;
/// then this screen shows the logo on the same navy, with a spinner. It
/// used to be a white screen with a spinner.
///
/// Mirrors the citizen app's AuthWrapper — without this, the app would
/// always open on the login screen even for an already-logged-in
/// responder, and the FCM token would never get re-registered on
/// ordinary app relaunches (only right after a fresh login).
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  /// The splash screen's navy (pubspec.yaml → flutter_native_splash).
  static const Color _navy = Color(0xFF0D1B4C);

  /// Takes the splash screen down after 3 seconds if the check isn't done.
  Timer? _slowCheck;

  @override
  void initState() {
    super.initState();
    _slowCheck = Timer(const Duration(seconds: 3), FlutterNativeSplash.remove);
    _checkSession();
  }

  @override
  void dispose() {
    _slowCheck?.cancel();
    super.dispose();
  }

  Future<void> _checkSession() async {
    final hasToken = await ApiService.isResponderLoggedIn();

    if (!hasToken) {
      _goTo(const ResponderLoginScreen());
      return;
    }

    // Token exists locally — confirm it's still valid server-side.
    final result = await ApiService.getResponderMe();

    if (!mounted) return;

    if (result.success) {
      // Session confirmed valid — re-register the FCM token in case it
      // rotated since the last time the app was opened, then go
      // straight to Home without asking for a password again.
      await ApiService.registerPushToken();
      _goTo(const ResponderHomeScreen());
    } else if (result.sessionExpired) {
      _goTo(const ResponderLoginScreen());
    } else {
      // No signal, or a server error: the sign-in is still good, so open
      // Home with what's saved on the phone — it shows what it can and
      // tries again. Before, a weak signal meant the login screen.
      _goTo(const ResponderHomeScreen());
    }
  }

  /// Login or Home, straight from the splash screen (no slide), then the
  /// splash screen goes.
  void _goTo(Widget screen) {
    if (!mounted) return;
    _slowCheck?.cancel();
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => screen,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
    FlutterNativeSplash.remove();
  }

  /// Only seen when the check takes more than 3 seconds.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/logo.png', width: 97),
            const SizedBox(height: 40),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
