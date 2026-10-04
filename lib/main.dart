import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'auth_wrapper.dart';
import 'incident_alert_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await IncidentAlertService.initialize();
  runApp(const ResponderApp());
}

class ResponderApp extends StatelessWidget {
  const ResponderApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ResQPulse Responder',
      debugShowCheckedModeBanner: false,
      navigatorKey: IncidentAlertService.navigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0D1B4C)),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}
