import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_service.dart';
import 'incoming_incident_overlay.dart';

/// Makes a new incident/SOS push "ring" on the responder's phone the way
/// an incoming call would — a looping alarm plus a full-screen,
/// non-dismissible alert — instead of a quiet one-shot notification
/// that's easy to miss while the phone is in a pocket or on a desk.
///
/// Only incident pushes ring. The server says what each push is about in
/// its data (PushNotificationService on the admin side):
///
///   type=incident  a report or SOS sent to the team (incident_id says
///                  which) — rings, with the full-screen alert
///   type=report    MDRRMO accepted or sent back the team's Final report
///   type=alert     a disaster alert from Alerts & Broadcast
///
/// The last two show as a normal notification. Before, every push rang as
/// "INCOMING INCIDENT", disaster alerts included.
///
/// While the app is open, Firebase hands every push to onMessage and shows
/// nothing itself, so this shows it. When the app is in the background or
/// closed, Firebase shows the notification: incident pushes go on the
/// ringing channel (_incidentAlertsChannel — the server names it), so they
/// ring with the same alarm sound, just once.
///
/// View on the ringing screen, or tapping an incident notification, opens
/// that incident ([incidentToOpen], handled by Home). Each incident push
/// also makes Home reload its list ([incidentPushes]).
///
/// The sound: assets/sounds/alarm-sound.mp3 in the app (the ring that
/// loops while the app is open) and android/app/src/main/res/raw/
/// alarm_sound.mp3 (the same file, for the notification channel; raw
/// resource names can't have a "-"). The app used to look for
/// incident_ring.mp3, which it didn't have, so the ring fell back to
/// vibration only.
///
/// SOUND TROUBLESHOOTING (the in-app ring):
///   1. The ring plays on Android's ALARM volume, not the media/ringer
///      volume. If the alarm volume is 0 you'll hear nothing even though
///      everything is working — raise it in Settings → Sound → Alarm volume.
///   2. If the mp3 can't be loaded, the reason is printed to the debug
///      console as "[IncidentAlert] ..." — and a vibration fallback takes
///      over so the alert is never silent.
///   3. After adding/changing an asset, STOP the app and run it again
///      (hot reload does not pick up new assets).
class IncidentAlertService {
  IncidentAlertService._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Tells Home when a screen on top of it closes, so it reloads the
  /// incident list (a mission accepted or a report sent elsewhere shows
  /// right away). Registered in main.dart.
  static final RouteObserver<ModalRoute<void>> routeObserver =
      RouteObserver<ModalRoute<void>>();

  /// Goes up by one for every incident push that comes in while the app is
  /// open — Home reloads its list.
  static final ValueNotifier<int> incidentPushes = ValueNotifier<int>(0);

  /// The incident the responder asked to see: View on the ringing screen,
  /// or tapping an incident notification. Home opens it and sets this back
  /// to null ([anyIncident]: the push didn't say which one — Home opens
  /// Active Incidents). Set before Home is up (the app was opened from the
  /// notification), it waits here until it is.
  static final ValueNotifier<int?> incidentToOpen = ValueNotifier<int?>(null);
  static const int anyIncident = 0;

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static final AudioPlayer _ringPlayer = AudioPlayer();

  /// Incident pushes ring on this channel, on the alarm volume. "_v2":
  /// Android keeps a channel's sound once it's made, and the first one
  /// ("incident_alerts") pointed at a sound file the app didn't have.
  static const AndroidNotificationChannel
  _incidentAlertsChannel = AndroidNotificationChannel(
    'incident_alerts_v2',
    'Incoming Incident Alerts',
    description:
        'Rings like an incoming call when a report or SOS is sent to your team.',
    importance: Importance.max,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('alarm_sound'),
    audioAttributesUsage: AudioAttributesUsage.alarm,
  );

  /// Disaster alerts and MDRRMO's updates on your reports — a normal
  /// notification, no ringing.
  static const AndroidNotificationChannel _updatesChannel =
      AndroidNotificationChannel(
        'responder_updates',
        'Alerts and Updates',
        description: 'Disaster alerts and MDRRMO updates about your reports.',
        importance: Importance.high,
      );

  static bool _ringing = false;
  static bool _overlayShowing = false;
  static Timer? _fallbackTimer;
  static int _notificationId = 0;

  /// Call once at app startup, right after Firebase.initializeApp().
  static Future<void> initialize() async {
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.deleteNotificationChannel('incident_alerts');
    await androidPlugin?.createNotificationChannel(_incidentAlertsChannel);
    await androidPlugin?.createNotificationChannel(_updatesChannel);
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

    FirebaseMessaging.onMessage.listen(_handleMessage);

    // Tapping a notification while the app was in the background, or
    // opening the app from one: show that incident.
    FirebaseMessaging.onMessageOpenedApp.listen(_openFromNotification);
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _openFromNotification(initial);
  }

  /// Incident pushes ring; everything else is a normal notification. A
  /// push from before the server said its type counts as an incident when
  /// its title starts with 🚨 or 🆘, like every incident push's does.
  static bool _isIncident(RemoteMessage message) {
    final type = message.data['type']?.toString() ?? '';
    if (type.isNotEmpty) return type == 'incident';
    final title = message.notification?.title ?? '';
    return title.startsWith('🚨') || title.startsWith('🆘');
  }

  static int _incidentIdOf(RemoteMessage message) =>
      int.tryParse('${message.data['incident_id'] ?? ''}') ?? anyIncident;

  static Future<void> _handleMessage(RemoteMessage message) async {
    // A phone that's signed out doesn't ring or show anything.
    if (!await ApiService.isResponderLoggedIn()) return;

    final title = message.notification?.title ?? 'New Incident';
    final body = message.notification?.body ?? 'A new incident was reported.';

    if (!_isIncident(message)) {
      await _localNotifications.show(
        _notificationId++,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _updatesChannel.id,
            _updatesChannel.name,
            channelDescription: _updatesChannel.description,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
      return;
    }

    incidentPushes.value++;
    _startRinging();

    // One ringing screen at a time — a second report while it's up keeps
    // it ringing, and Home's list shows them all.
    if (_overlayShowing) return;
    final context = navigatorKey.currentState?.overlay?.context;
    if (context == null) return;

    final incidentId = _incidentIdOf(message);
    _overlayShowing = true;
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
          incidentToOpen.value = incidentId;
        },
      ),
    ).whenComplete(() => _overlayShowing = false);
  }

  static void _openFromNotification(RemoteMessage message) {
    _stopRinging();
    if (_isIncident(message)) {
      incidentToOpen.value = _incidentIdOf(message);
    }
  }

  static Future<void> _startRinging() async {
    if (_ringing) return;
    _ringing = true;

    try {
      await _ringPlayer.setReleaseMode(ReleaseMode.loop);
      await _ringPlayer.setVolume(1.0);
      await _ringPlayer.play(
        AssetSource('sounds/alarm-sound.mp3'),
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
      // Don't stay silent: say why, and fall back to vibration.
      debugPrint(
        '[IncidentAlert] Could not play assets/sounds/alarm-sound.mp3: $e',
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
