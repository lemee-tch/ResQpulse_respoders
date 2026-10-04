import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
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
/// the same sound — just played by the OS rather than by this code. If a
/// real always-on ring is wanted later even when the app is killed, the
/// actual fix is upstream: have the backend send a `data` payload instead
/// of (or alongside) the notification payload.
///
/// Setup this file depends on (see the pubspec/manifest notes given
/// alongside it):
///   - assets/sounds/incident_ring.mp3  (Flutter asset — the in-app loop)
///   - android/app/src/main/res/raw/incident_ring.mp3  (Android raw
///     resource, same file — the OS-level channel sound)
/// Both should be the SAME sound, just placed in two different folders
/// because Flutter assets and Android raw resources are separate systems.
///
/// Gotcha: Android locks a notification channel's sound the first time
/// that channel is created on a given install. If this app was already
/// run once before this sound was added, creating the channel again with
/// a `sound:` set here will NOT retroactively change it — uninstall the
/// app from the test device first so Android creates the channel fresh.
class IncidentAlertService {
  IncidentAlertService._();

  /// Lets code outside the widget tree (the FCM listener below) push the
  /// full-screen alert on top of whatever screen the responder is
  /// currently on. Wire this into the app's MaterialApp(navigatorKey: ...).
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Dedicated player for the in-app ring, kept separate from any other
  /// sound the app might ever play.
  static final AudioPlayer _ringPlayer = AudioPlayer();

  /// Kept as its own channel so a responder could still override just
  /// this sound from Android's notification settings if they wanted
  /// something different from incident_ring.mp3.
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
          // TODO: deep-link straight to this incident once the push
          // payload carries an incident id — see the scope note above.
          // For now this just clears the alert; the incident still shows
          // up on the home screen's list right away.
        },
      ),
    );
  }

  static Future<void> _startRinging() async {
    if (_ringing) return;
    _ringing = true;

    try {
      await _ringPlayer.setReleaseMode(ReleaseMode.loop);
      await _ringPlayer.play(
        AssetSource('sounds/alarm_sound.mp3'),
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
    } catch (_) {
      // Missing/undeclared asset, codec issue, etc. The full-screen
      // overlay still shows either way — the ring is on top of that, not
      // instead of it.
    }
  }

  static Future<void> _stopRinging() async {
    _ringing = false;
    try {
      await _ringPlayer.stop();
    } catch (_) {
      // Already stopped/released — fine to ignore.
    }
  }
}
