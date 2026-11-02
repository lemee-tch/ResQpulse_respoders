import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'api_service.dart';
import 'auth_wrapper.dart';
import 'incident_alert_service.dart';

void main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // The phone's splash screen (navy with the logo — flutter_native_splash,
  // see pubspec.yaml) stays up until AuthWrapper knows whether to open
  // Login or Home (item 51).
  FlutterNativeSplash.preserve(widgetsBinding: binding);
  await Firebase.initializeApp();
  await IncidentAlertService.initialize();
  ApiService.listenForTokenRefresh();
  runApp(const ResponderApp());
}

class ResponderApp extends StatelessWidget {
  const ResponderApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // The app's name (item 51) — also under the icon on the phone
      // (android:label in AndroidManifest.xml).
      title: 'Resqponder',
      debugShowCheckedModeBanner: false,
      navigatorKey: IncidentAlertService.navigatorKey,
      navigatorObservers: [IncidentAlertService.routeObserver],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0D1B4C)),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}
