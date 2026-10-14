import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'incoming_incident_overlay.dart';

/// Makes a new incident/SOS push "ring" on the responder's phone the way
/// an incoming call would — a looping custom ringtone plus a full-screen,
/// non-dismissible alert — instead of a quiet one-shot notification
/// that's easy to miss while the phone is in a pocket or on a desk.
///
/// Scope note: PushNotificationService.php (backend) currently sends a
/// plain FCM *notification* payload — just a title/body, no `data` block.
/// That means Dart code only ever sees the push via
/// FirebaseMessaging.onMessage, which fires ONLY while the app is in the
/// foreground. When the app is backgrounded or fully closed, Firebase
/// auto-displays the push as a normal system notification without
/// running any Dart code at all, so the ring+overlay below can't trigger
/// in that case. That's handled instead by giving these pushes their own
/// high-importance Android channel (_incidentAlertsChannel) with the same
/// custom sound baked in, so the background/closed case still rings with
/// the same sound — just played by the OS rather than by this code.
///
/// Setup this file depends on:
///   - assets/sounds/incident_ring.mp3  (Flutter asset — the in-app loop;
///     must be declared in pubspec.yaml under flutter: assets:)
///   - android/app/src/main/res/raw/incident_ring.mp3  (Android raw
///     resource, same file — the OS-level channel sound)
///
/// SOUND TROUBLESHOOTING (the in-app ring):
///   1. The ring plays on Android's ALARM volume, not the media/ringer
///      volume. If the alarm volume is 0 you'll hear nothing even though
///      everything is working — raise it in Settings → Sound → Alarm volume.
///   2. If the mp3 can't be loaded, the reason is printed to the debug
///      console as "[IncidentAlert] ..." — and a built-in beep + vibration
///      fallback takes over so the alert is never silent.
///   3. After adding/changing an asset, STOP the app and run it again
///      (hot reload does not pick up new assets).
class IncidentAlertService {
  IncidentAlertService._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static final AudioPlayer _ringPlayer = AudioPlayer();

  static const AndroidNotificationChannel
  _incidentAlertsChannel = AndroidNotificationChannel(
    'incident_alerts',
    'Incoming Incident Alerts',
    description:
        'Rings like an incoming call when a new incident or SOS is dispatched to you.',
    importance: Importance.max,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('incident_ring'),
  );

  static bool _ringing = false;
  static Timer? _fallbackTimer;

  /// Call once at app startup, right after Firebase.initializeApp().
  static Future<void> initialize() async {
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(_incidentAlertsChannel);
    await androidPlugin?.requestNotificationsPermission();

    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (_) => _stopRinging(),
    );

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen(_handleIncomingIncident);
  }

  static void _handleIncomingIncident(RemoteMessage message) {
    final title = message.notification?.title ?? 'New Incident';
    final body = message.notification?.body ?? 'A new incident was reported.';

    _startRinging();

    final context = navigatorKey.currentState?.overlay?.context;
    if (context == null) return;

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      pageBuilder: (dialogContext, _, __) => IncomingIncidentOverlay(
        title: title,
        body: body,
        onDismiss: () {
          _stopRinging();
          Navigator.of(dialogContext).pop();
        },
        onView: () {
          _stopRinging();
          Navigator.of(dialogContext).pop();
        },
      ),
    );
  }

  static Future<void> _startRinging() async {
    if (_ringing) return;
    _ringing = true;

    try {
      await _ringPlayer.setReleaseMode(ReleaseMode.loop);
      await _ringPlayer.setVolume(1.0);
      await _ringPlayer.play(
        AssetSource('sounds/incident_ring.mp3'),
        volume: 1.0,
        ctx: AudioContext(
          android: AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.alarm,
          ),
        ),
      );
    } catch (e) {
      // Missing/undeclared asset, corrupt file, codec issue, etc.
      // Don't stay silent: say why, and fall back to a beep + vibration.
      debugPrint(
        '[IncidentAlert] Could not play assets/sounds/incident_ring.mp3: $e',
      );
      _startFallbackAlert();
    }
  }

  /// Built-in beep + vibration, repeated until the alert is dismissed.
  /// Used only when the custom ringtone couldn't be played.
  static void _startFallbackAlert() {
    _fallbackTimer?.cancel();
    void pulse() {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.vibrate();
    }

    pulse();
    _fallbackTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!_ringing) return;
      pulse();
    });
  }

  static Future<void> _stopRinging() async {
    _ringing = false;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    try {
      await _ringPlayer.stop();
    } catch (_) {
      // Already stopped/released — fine to ignore.
    }
  }
}
