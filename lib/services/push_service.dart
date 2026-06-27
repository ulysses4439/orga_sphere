import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../app_globals.dart';
import 'api_service.dart';
import 'notification_center.dart';
import 'task_service.dart';

/// Hintergrund-Handler (App terminiert/Hintergrund): FCM zeigt die Notification
/// automatisch an, da die Nachricht eine `notification`-Payload trägt – hier ist
/// nichts zu tun. Muss eine Top-Level-Funktion mit vm:entry-point sein.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {}

/// Zentrale Stelle für Push (FCM) und OS-Toasts (flutter_local_notifications).
///
/// - Android/iOS: volles FCM-Push (auch bei geschlossener App). Vordergrund-
///   Nachrichten werden als lokaler Toast angezeigt.
/// - Windows/macOS/Linux: kein FCM – OS-Toasts werden vom [EventPollService]
///   über das 30s-Polling angestoßen (siehe [usesPollingToasts]).
class PushService {
  static final PushService _instance = PushService._internal();
  factory PushService() => _instance;
  PushService._internal();

  final FlutterLocalNotificationsPlugin _localNotif =
      FlutterLocalNotificationsPlugin();
  bool _localReady = false;
  bool _fcmInitialized = false;
  String? _fcmToken;

  static const _androidChannelId = 'orga_events';
  static const _androidChannelName = 'Team-Aktivitäten';

  bool get _isFcmPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _supportsLocalToast =>
      !kIsWeb && defaultTargetPlatform != TargetPlatform.fuchsia;

  /// Plattform muss OS-Toasts selbst per Polling zeigen (kein FCM).
  bool get usesPollingToasts => _supportsLocalToast && !_isFcmPlatform;

  String get _platformName {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.linux:
        return 'linux';
      default:
        return 'unknown';
    }
  }

  /// Einmal nach Login / beim App-Start (falls eingeloggt) aufrufen.
  Future<void> init() async {
    await _initLocalNotifications();
    if (_isFcmPlatform) await _initFcm();
  }

  Future<void> _initLocalNotifications() async {
    if (_localReady || !_supportsLocalToast) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
    const linux = LinuxInitializationSettings(defaultActionName: 'Öffnen');
    final windows = WindowsInitializationSettings(
      appName: 'OrgaSphere',
      appUserModelId: 'com.coateseventsystems.orgasphere',
      guid: '3f2504e0-4f89-41d3-9a0c-0305e82c3301',
    );
    final settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
      linux: linux,
      windows: windows,
    );
    await _localNotif.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    await _localNotif
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _androidChannelId,
          _androidChannelName,
          description: 'Benachrichtigungen über Änderungen im Team',
          importance: Importance.high,
        ));
    _localReady = true;
  }

  Future<void> _initFcm() async {
    if (_fcmInitialized) return;
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('Firebase init failed – push disabled: $e');
      return;
    }
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    _fcmToken = await messaging.getToken();
    await _registerToken();
    messaging.onTokenRefresh.listen((t) {
      _fcmToken = t;
      _registerToken();
    });
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(
        (m) => _navigateToSphere(m.data['sphereId'] as String?));
    _fcmInitialized = true;
  }

  Future<void> _registerToken() async {
    final token = _fcmToken;
    if (token == null) return;
    try {
      await ApiService.registerDevice(token, _platformName);
    } catch (_) {/* Registrierung beim nächsten Start erneut versucht */}
  }

  /// Vordergrund-FCM (Android/iOS): Toast zeigen + Glocke/Liste & Aufgaben aktualisieren.
  Future<void> _onForegroundMessage(RemoteMessage m) async {
    final body = m.notification?.body;
    if (body != null && body.isNotEmpty) {
      await showLocal(body, payload: m.data['sphereId'] as String?);
    }
    try {
      final events =
          await ApiService.getEvents(since: NotificationCenter().latestEventTime);
      await NotificationCenter().addEvents(events);
    } catch (_) {}
    try {
      await TaskService().refresh();
    } catch (_) {}
  }

  /// Zeigt einen OS-Toast. Wird von FCM (Vordergrund) und vom EventPollService
  /// (Windows/Desktop) genutzt.
  Future<void> showLocal(String body, {String? payload}) async {
    if (!_localReady) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _androidChannelId,
        _androidChannelName,
        channelDescription: 'Benachrichtigungen über Änderungen im Team',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
      linux: LinuxNotificationDetails(),
      windows: WindowsNotificationDetails(),
    );
    await _localNotif.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: 'OrgaSphere',
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }

  void _onNotificationTap(NotificationResponse r) =>
      _navigateToSphere(r.payload);

  void _navigateToSphere(String? sphereId) {
    if (sphereId == null || sphereId.isEmpty) return;
    navigatorKey.currentState?.pushNamed('/task-detail', arguments: sphereId);
  }

  /// Beim Logout: Token serverseitig entfernen, damit das Gerät keine Pushes
  /// für den abgemeldeten Account mehr bekommt.
  Future<void> unregister() async {
    final token = _fcmToken;
    if (token == null) return;
    try {
      await ApiService.deleteDevice(token);
    } catch (_) {}
  }
}
