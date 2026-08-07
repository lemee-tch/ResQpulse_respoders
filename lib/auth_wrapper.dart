import 'package:flutter/material.dart';
import 'api_service.dart';
import 'responder_login.dart';
import 'responder_home.dart';

/// Shown briefly on every app launch. Decides whether to send the
/// responder straight to Home (still logged in) or to Login (logged
/// out, or their session/token is no longer valid on the server).
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
  @override
  void initState() {
    super.initState();
    _checkSession();
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
    } else {
      _goTo(const ResponderLoginScreen());
    }
  }

  void _goTo(Widget screen) {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(child: CircularProgressIndicator(color: Color(0xFF0D1B4C))),
    );
  }
}
