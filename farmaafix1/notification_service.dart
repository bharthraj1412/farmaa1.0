import 'dart:async';
import 'dart:developer';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Background message handler — must be top-level function.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  log('[FCM] Background message received: ${message.notification?.title}');
}

/// Full notification service — local notifications + Firebase Cloud Messaging.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  bool _initialized = false;
  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  final StreamController<RemoteMessage> messageStreamController =
      StreamController<RemoteMessage>.broadcast();

  // ── Notification channels ─────────────────────────────────────────────────
  static const String _ordersChannelId = 'farmaa_orders';
  static const String _ordersChannelName = 'Order Updates';
  static const String _pricesChannelId = 'farmaa_prices';
  static const String _pricesChannelName = 'Market Price Alerts';
  static const String _generalChannelId = 'farmaa_general';
  static const String _generalChannelName = 'Farmaa Notifications';

  // ── Initialize ────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await _setupLocalNotifications();
    await _setupFCM();
  }

  Future<void> _setupLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('[Notification] Tapped: ${response.payload}');
        // Navigation based on payload can be added here
      },
    );

    // Create all notification channels
    final androidPlugin = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      // Orders channel — highest priority
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _ordersChannelId,
          _ordersChannelName,
          description: 'Notifications for order placements and status updates',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          enableLights: true,
          ledColor: Color(0xFF1A5E20),
        ),
      );

      // Price alerts channel
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _pricesChannelId,
          _pricesChannelName,
          description: 'Market price movement alerts',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );

      // General channel
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _generalChannelId,
          _generalChannelName,
          description: 'General Farmaa notifications',
          importance: Importance.defaultImportance,
          playSound: true,
        ),
      );

      // Request notification permission (Android 13+)
      final granted = await androidPlugin.requestNotificationsPermission();
      debugPrint('[Notification] Android permission granted: $granted');
    }
  }

  Future<void> _setupFCM() async {
    // Request FCM permission
    final settings = await _fcm.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    debugPrint('[FCM] Authorization status: ${settings.authorizationStatus}');

    // Configure foreground notification presentation (iOS)
    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Get FCM token
    try {
      _fcmToken = await _fcm.getToken().timeout(const Duration(seconds: 10));
      debugPrint('[FCM] Token obtained: ${_fcmToken?.substring(0, 20)}...');
    } catch (e) {
      debugPrint('[FCM] Token fetch failed (emulator/no Play Services): $e');
    }

    // Register background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    // Foreground messages → show local notification
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('[FCM] Foreground message: ${message.notification?.title}');
      final notification = message.notification;
      if (notification != null) {
        final isOrder = message.data['type'] == 'order';
        showLocal(
          title: notification.title ?? 'Farmaa',
          body: notification.body ?? '',
          channelId: isOrder ? _ordersChannelId : _generalChannelId,
          channelName: isOrder ? _ordersChannelName : _generalChannelName,
        );
        messageStreamController.add(message);
      }
    });

    // App opened from background notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('[FCM] App opened from notification: ${message.data}');
      messageStreamController.add(message);
    });

    // App launched from terminated state via notification
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('[FCM] Launch from terminated: ${initialMessage.data}');
      // Slight delay to let app initialize
      await Future.delayed(const Duration(milliseconds: 500));
      messageStreamController.add(initialMessage);
    }

    // Token refresh
    _fcm.onTokenRefresh.listen((String newToken) {
      debugPrint('[FCM] Token refreshed');
      _fcmToken = newToken;
      // TODO: Send updated token to backend
    });
  }

  // ── Show local notification ───────────────────────────────────────────────

  Future<void> showLocal({
    required String title,
    required String body,
    String? payload,
    String channelId = _ordersChannelId,
    String channelName = _ordersChannelName,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFF1A5E20),
      enableLights: true,
      enableVibration: true,
      playSound: true,
      styleInformation: BigTextStyleInformation(body),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );

    debugPrint('[Notification] Showed: $title');
  }

  /// Show order-specific notification with green styling
  Future<void> showOrderNotification({
    required String title,
    required String body,
    String? orderId,
  }) async {
    await showLocal(
      title: title,
      body: body,
      payload: orderId,
      channelId: _ordersChannelId,
      channelName: _ordersChannelName,
    );
  }

  /// Show market price alert notification
  Future<void> showPriceAlert({
    required String cropName,
    required String message,
  }) async {
    await showLocal(
      title: '📊 Price Alert: $cropName',
      body: message,
      channelId: _pricesChannelId,
      channelName: _pricesChannelName,
    );
  }

  /// Cancel all notifications
  Future<void> cancelAll() async {
    await _local.cancelAll();
  }
}
