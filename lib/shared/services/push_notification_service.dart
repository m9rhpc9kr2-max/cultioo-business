import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cultioo_business/config/api_config.dart';

class PushNotificationService {
  static final FirebaseMessaging _firebaseMessaging =
      FirebaseMessaging.instance;
  static const String _notificationEnabledKey = 'push_notifications_enabled';

  // Initialize Firebase and request permissions
  static Future<void> initialize() async {
    try {
      // Check if Firebase is already initialized
      try {
        Firebase.app();
        print('🔥 Firebase already initialized');
      } catch (e) {
        print('🔥 Firebase not initialized yet, skipping FCM setup');
        return; // Skip Firebase initialization if not available
      }

      // Request notification permissions
      NotificationSettings settings = await _firebaseMessaging
          .requestPermission(
            alert: true,
            announcement: false,
            badge: true,
            carPlay: false,
            criticalAlert: false,
            provisional: false,
            sound: true);

      print(
        '🔔 Push notification permission status: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('✅ User granted permission for notifications');

        // Get FCM token
        String? token = await _firebaseMessaging.getToken();
        print('📱 FCM Token: $token');

        if (token != null) {
          await _sendTokenToServer(token);
        }

        // Listen for token refresh
        _firebaseMessaging.onTokenRefresh.listen((newToken) {
          _sendTokenToServer(newToken);
        });

        // Setup message handlers
        _setupMessageHandlers();
      } else {
        print('❌ User denied permission for notifications');
      }
    } catch (e) {
      print('💥 Error initializing push notifications: $e');
      print('ℹ️  Push notifications will not be available');
    }
  }

  // Setup message handlers for different states
  static void _setupMessageHandlers() {
    // Handle messages when app is in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📨 Received foreground message: ${message.messageId}');
      print('📨 Title: ${message.notification?.title}');
      print('📨 Body: ${message.notification?.body}');
      print('📨 Data: ${message.data}');

      _showLocalNotification(message);
    });

    // Handle notification taps when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('📱 Notification tapped: ${message.messageId}');
      _handleNotificationTap(message);
    });

    // Check if app was opened from a terminated state by tapping notification
    FirebaseMessaging.instance.getInitialMessage().then((
      RemoteMessage? message) {
      if (message != null) {
        print(
          '🚀 App opened from terminated state by notification: ${message.messageId}');
        _handleNotificationTap(message);
      }
    });
  }

  // Send FCM token to server
  static Future<void> _sendTokenToServer(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final authToken = prefs.getString('auth_token');
      if (authToken == null) {
        print('⚠️ No auth token, cannot send FCM token to server');
        return;
      }
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/fcm-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: json.encode({'fcmToken': token}));

      if (response.statusCode == 200) {
        print('✅ FCM token sent to server successfully');
      } else {
        print('❌ Failed to send FCM token: ${response.statusCode}');
      }
    } catch (e) {
      print('💥 Error sending FCM token to server: $e');
    }
  }

  // Show local notification when app is in foreground
  static void _showLocalNotification(RemoteMessage message) {
    // This would typically use flutter_local_notifications
    // For now, we'll just print the notification
    print('🔔 Local notification would be shown:');
    print('   Title: ${message.notification?.title}');
    print('   Body: ${message.notification?.body}');
  }

  // Handle notification tap
  static void _handleNotificationTap(RemoteMessage message) {
    print('👆 Notification tapped, navigating...');

    // Handle different notification types based on data
    final String? type = message.data['type'];
    final String? orderId = message.data['orderId'];

    switch (type) {
      case 'new_order':
        print('🛍️ Navigate to new order: $orderId');
        break;
      case 'order_update':
        print('📦 Navigate to order update: $orderId');
        break;
      case 'verification_update':
        print('✅ Navigate to verification center');
        break;
      case 'earnings_update':
        print('💰 Navigate to earnings page');
        break;
    }

    // Default fallback if no specific type
    if (type == null || type.isEmpty) {
      print('📱 Navigate to main dashboard');
    }
  }

  // Enable push notifications
  static Future<bool> enableNotifications() async {
    try {
      // Check if Firebase is initialized
      try {
        Firebase.app();
      } catch (e) {
        print('🔥 Firebase not initialized, cannot enable push notifications');
        return false;
      }

      NotificationSettings settings = await _firebaseMessaging
          .requestPermission(alert: true, badge: true, sound: true);

      bool enabled =
          settings.authorizationStatus == AuthorizationStatus.authorized;

      if (enabled) {
        // Get and send FCM token to server
        String? token = await _firebaseMessaging.getToken();
        if (token != null) {
          await _sendTokenToServer(token);
        }
      }

      // Save preference
      await _saveNotificationPreference(enabled);

      print('🔔 Push notifications ${enabled ? 'enabled' : 'disabled'}');
      return enabled;
    } catch (e) {
      print('💥 Error enabling push notifications: $e');
      return false;
    }
  }

  // Disable push notifications
  static Future<void> disableNotifications() async {
    try {
      // Check if Firebase is initialized
      try {
        Firebase.app();
      } catch (e) {
        print('🔥 Firebase not initialized, only saving preference');
        await _saveNotificationPreference(false);
        return;
      }

      // Delete FCM token from server
      await _deleteTokenFromServer();

      // Save preference
      await _saveNotificationPreference(false);

      print('🔕 Push notifications disabled');
    } catch (e) {
      print('💥 Error disabling push notifications: $e');
      // Still save the preference even if there's an error
      await _saveNotificationPreference(false);
    }
  }

  // Delete FCM token from server
  static Future<void> _deleteTokenFromServer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final authToken = prefs.getString('auth_token');
      if (authToken == null) return;
      String? fcmToken = await _firebaseMessaging.getToken();

      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/fcm-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: json.encode({'fcmToken': fcmToken}));

      if (response.statusCode == 200) {
        print('✅ FCM token deleted from server');
      } else {
        print('❌ Failed to delete FCM token: ${response.statusCode}');
      }
    } catch (e) {
      print('💥 Error deleting FCM token: $e');
    }
  }

  // Save notification preference
  static Future<void> _saveNotificationPreference(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationEnabledKey, enabled);
  }

  // Get notification preference
  static Future<bool> isNotificationEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notificationEnabledKey) ?? true; // Default enabled
  }

  // Check if notifications are actually allowed by system
  static Future<bool> areNotificationsAllowed() async {
    try {
      // Check if Firebase is initialized
      try {
        Firebase.app();
      } catch (e) {
        print('🔥 Firebase not initialized, returning false');
        return false;
      }

      NotificationSettings settings = await _firebaseMessaging
          .getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized;
    } catch (e) {
      print('💥 Error checking notification permissions: $e');
      return false;
    }
  }

  // Get notification permission status
  static Future<String> getPermissionStatus() async {
    try {
      // Check if Firebase is initialized
      try {
        Firebase.app();
      } catch (e) {
        return 'Firebase not initialized';
      }

      NotificationSettings settings = await _firebaseMessaging
          .getNotificationSettings();

      switch (settings.authorizationStatus) {
        case AuthorizationStatus.authorized:
          return 'Enabled';
        case AuthorizationStatus.denied:
          return 'Denied';
        case AuthorizationStatus.notDetermined:
          return 'Not determined';
        case AuthorizationStatus.provisional:
          return 'Provisional';
      }
    } catch (e) {
      print('💥 Error getting permission status: $e');
      return 'Error';
    }
  }

  // Send test notification (for debugging)
  static Future<void> sendTestNotification() async {
    try {
      // Check if Firebase is initialized
      try {
        Firebase.app();
      } catch (e) {
        print('🔥 Firebase not initialized, cannot send test notification');
        return;
      }

      String? token = await _firebaseMessaging.getToken();

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/test-notification'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'fcmToken': token,
          'title': 'Test Notification',
          'body': 'This is a test notification from Delvioo',
          'data': {
            'type': 'test',
            'timestamp': DateTime.now().toIso8601String(),
          },
        }));

      if (response.statusCode == 200) {
        print('✅ Test notification sent successfully');
      } else {
        print('❌ Failed to send test notification: ${response.statusCode}');
      }
    } catch (e) {
      print('💥 Error sending test notification: $e');
    }
  }
}

// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    // Try to initialize Firebase if not already done
    try {
      Firebase.app();
    } catch (e) {
      print('🔥 Firebase not initialized in background handler');
      return;
    }

    print('📱 Background message received: ${message.messageId}');
    print('📱 Title: ${message.notification?.title}');
    print('📱 Body: ${message.notification?.body}');
  } catch (e) {
    print('💥 Error in background message handler: $e');
  }
}
