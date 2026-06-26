import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'locker_vault.dart';
import 'traffic_agent.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ALERT BRIDGE — FCM + local notification orchestration
// ─────────────────────────────────────────────────────────────────────────────
// Boundary between Firebase Messaging and the rest of the app. Handles
// channel creation, foreground rendering with big-picture support, and
// the cold-start / warm-tap URL routing rules.
//
// URL routing rules:
//   1. App KILLED, user taps push → cold start → save URL to vault.
//      BootStage consumes it on the next launch.
//   2. App BACKGROUNDED, user taps push → onMessageOpenedApp → call the
//      registered live callback. Do NOT persist (one-shot only).
//   3. App FOREGROUNDED, push arrives → render local notification →
//      onDidReceiveNotificationResponse → live callback. Do NOT persist.
//
// Distinction: warm taps never persist because the spec says push URLs
// are single-use; on the *next* launch the app must honour the beacon
// reply, not the most recently tapped push.
// ─────────────────────────────────────────────────────────────────────────────

const String kFcmChannelId = 'dz_alerts_high';
const String kFcmChannelName = 'High Priority Alerts';
const String kFcmChannelDesc = 'Inbound updates and reminders';
const String kFcmIconRes = '@drawable/ic_notification';

@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage _) async {
  // Background isolate — no app state available. Intentionally empty.
}

class AlertBridge {
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  final LockerVault _vault;
  FirebaseMessaging? _fcm;
  String? _token;
  bool _wired = false;

  /// Live URL callback. Invoked when the user taps a push while the app
  /// is warm. ContentScreen / PortalStage wires this so it can reload the
  /// WebView in-place. Cold-start URLs go through the vault instead.
  void Function(String url)? onLiveUrl;

  /// Token rotation callback. The dispatcher re-POSTs to the beacon with
  /// the new token so the backend can keep targeting that install.
  void Function(String newToken)? onTokenRotated;

  AlertBridge(this._vault);

  String? get currentToken => _token;

  /// Initialises Firebase Messaging + the local plugin. Silent no-op if
  /// google-services.json is missing — the dispatcher continues without
  /// push capability.
  Future<void> wire() async {
    if (_wired) return;
    try {
      await Firebase.initializeApp();
      _fcm = FirebaseMessaging.instance;

      FirebaseMessaging.onBackgroundMessage(_bgHandler);

      await _wireLocalPlugin();

      _token = await _fcm!.getToken();

      _fcm!.onTokenRefresh.listen((rotated) {
        _token = rotated;
        onTokenRotated?.call(rotated);
      });

      FirebaseMessaging.onMessage.listen(_onForeground);
      FirebaseMessaging.onMessageOpenedApp.listen(_onBackgroundTap);

      final initial = await _fcm!.getInitialMessage();
      if (initial != null) {
        _onColdStartTap(initial);
      }

      _wired = true;
    } catch (_) {
      // Firebase plumbing not ready — proceed without push.
    }
  }

  /// Asks the OS for the notification permission. On Android 13+ this is
  /// the only way the system dialog appears.
  ///
  /// Persists either "granted" or the "OS-denied" flag — the latter
  /// prevents us from showing the in-app invite again, since once Android
  /// returns denied we cannot re-request via SDK.
  Future<bool> requestUserPermission() async {
    if (_fcm == null) return false;
    final settings = await _fcm!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    final accepted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;

    await _vault.markNotifGranted(accepted);
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      await _vault.markNotifOsDenied();
    }
    return accepted;
  }

  // ── internals ─────────────────────────────────────────────────────────

  Future<void> _wireLocalPlugin() async {
    const androidInit = AndroidInitializationSettings(kFcmIconRes);
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onLocalTap,
    );

    if (Platform.isAndroid) {
      final plugin = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await plugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          kFcmChannelId,
          kFcmChannelName,
          description: kFcmChannelDesc,
          importance: Importance.high,
        ),
      );
    }
  }

  void _onLocalTap(NotificationResponse response) {
    if (response.payload == null) return;
    try {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
      final url = (data['url'] ?? '').toString();
      if (url.isNotEmpty) onLiveUrl?.call(url);
    } catch (_) {}
  }

  Future<void> _onForeground(RemoteMessage message) async {
    if (!Platform.isAndroid) return; // iOS shows banners on its own.
    final notification = message.notification;
    if (notification == null) return;

    AndroidNotificationDetails details;
    final imageUrl = notification.android?.imageUrl;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final picture = await _downloadBytes(imageUrl);
      if (picture != null) {
        details = AndroidNotificationDetails(
          kFcmChannelId,
          kFcmChannelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: kFcmIconRes,
          styleInformation: BigPictureStyleInformation(
            ByteArrayAndroidBitmap(picture),
            largeIcon:
                const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          ),
        );
      } else {
        details = _plainDetails();
      }
    } else {
      details = _plainDetails();
    }

    final payload =
        message.data.isNotEmpty ? jsonEncode(message.data) : null;
    await _local.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(android: details),
      payload: payload,
    );
  }

  AndroidNotificationDetails _plainDetails() {
    return const AndroidNotificationDetails(
      kFcmChannelId,
      kFcmChannelName,
      importance: Importance.high,
      priority: Priority.high,
      icon: kFcmIconRes,
    );
  }

  void _onColdStartTap(RemoteMessage message) {
    final url = message.data['url'];
    if (url is String && url.isNotEmpty) {
      _vault.writePushTarget(url);
    }
  }

  void _onBackgroundTap(RemoteMessage message) {
    final url = message.data['url'];
    if (url is String && url.isNotEmpty) {
      onLiveUrl?.call(url);
    }
  }

  Future<Uint8List?> _downloadBytes(String url) async {
    try {
      final response = await trafficAgent
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return response.bodyBytes;
    } catch (_) {}
    return null;
  }
}
