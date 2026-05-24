// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

const int _kIntervalSeconds = 10;
const int _kForegroundNotificationId = 9001;
const String _kChannelId = 'driver_location_channel';
const String _kChannelName = 'Driver Location';
const String _kDriverActiveTitle = 'Delvioo – Active';
const String _kBackendUrl =
    'https://cultioo-business-app-78230737866.us-central1.run.app';

// ─────────────────────────────────────────────────────────────────────────────
// Foreground timer — main isolate, works on ALL platforms (Android, iOS, macOS)
// ─────────────────────────────────────────────────────────────────────────────

Timer? _foregroundTimer;

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

/// Call once from `main()` after `WidgetsFlutterBinding.ensureInitialized()`.
/// Only needed on Android/iOS to configure the background service.
Future<void> initDriverLocationService() async {
  if (!_isBackgroundSupported) return;

  // Create Android notification channel
  if (Platform.isAndroid) {
    final plugin = FlutterLocalNotificationsPlugin();
    const channel = AndroidNotificationChannel(
      _kChannelId,
      _kChannelName,
      description: 'Live location tracking for Delvioo deliveries',
      importance: Importance.low,
      playSound: false,
      enableVibration: false);
    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  final service = FlutterBackgroundService();

  await service.configure(
    // ── Android ──────────────────────────────────────────────────────────────
    androidConfiguration: AndroidConfiguration(
      onStart: _serviceEntryPoint,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: _kChannelId,
      initialNotificationTitle: 'Delvioo – Active',
      initialNotificationContent: 'Tracking your location…',
      foregroundServiceNotificationId: _kForegroundNotificationId,
      foregroundServiceTypes: [AndroidForegroundType.location]),
    // ── iOS ──────────────────────────────────────────────────────────────────
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: _serviceEntryPoint,
      onBackground: _iosBackgroundHandler));

  print('[DriverLocationService] Background service configured');
}

/// Start sending location pings every $_kIntervalSeconds seconds.
///
/// On ALL platforms (including macOS) a foreground [Timer] in the main isolate
/// is started so pings are sent while the app is open.
/// On Android/iOS the background service is also started so pings continue
/// when the app is moved to the background or closed.
Future<void> startDriverLocationService() async {
  final perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied ||
      perm == LocationPermission.deniedForever) {
    print('[DriverLocationService] Location permission not granted – not starting');
    return;
  }

  // ── Foreground timer (all platforms) ─────────────────────────────────────
  if (_foregroundTimer == null || !_foregroundTimer!.isActive) {
    await _sendDirectPing(); // immediate first ping
    _foregroundTimer = Timer.periodic(
      const Duration(seconds: _kIntervalSeconds),
      (_) => _sendDirectPing());
    print('[DriverLocationService] Foreground timer started');
  } else {
    print('[DriverLocationService] Foreground timer already running');
  }

  // ── Background service (Android / iOS only) ───────────────────────────────
  if (_isBackgroundSupported) {
    final service = FlutterBackgroundService();
    final running = await service.isRunning();
    if (!running) {
      final started = await service.startService();
      print('[DriverLocationService] Background service start → $started');
    } else {
      print('[DriverLocationService] Background service already running');
    }
  }
}

/// Stop all location pings. Call on logout or when Delvioo is exited.
Future<void> stopDriverLocationService() async {
  // ── Cancel foreground timer ───────────────────────────────────────────────
  _foregroundTimer?.cancel();
  _foregroundTimer = null;
  print('[DriverLocationService] Foreground timer stopped');

  // ── Stop background service (Android / iOS) ───────────────────────────────
  if (_isBackgroundSupported) {
    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      service.invoke('stop');
      print('[DriverLocationService] Background service stop requested');
    }
  }
}

/// Whether location pings are currently active.
Future<bool> isDriverLocationServiceRunning() async {
  if (_foregroundTimer != null && _foregroundTimer!.isActive) return true;
  if (!_isBackgroundSupported) return false;
  return FlutterBackgroundService().isRunning();
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Only Android/iOS support flutter_background_service.
/// macOS/Windows/Linux use the foreground timer only.
bool get _isBackgroundSupported => Platform.isAndroid || Platform.isIOS;

/// iOS background handler — must return quickly.
@pragma('vm:entry-point')
Future<bool> _iosBackgroundHandler(ServiceInstance service) async {
  return true;
}

/// Main background-service isolate entry-point (Android foreground + iOS background).
@pragma('vm:entry-point')
void _serviceEntryPoint(ServiceInstance service) async {
  // ── Listen for stop command from the main isolate ─────────────────────────
  service.on('stop').listen((_) {
    print('[DriverLocationService] Background service stopping');
    service.stopSelf();
  });

  // ── Send first ping immediately, then every 10 s ──────────────────────────
  await _sendPing(service);

  Timer.periodic(const Duration(seconds: _kIntervalSeconds), (_) async {
    await _sendPing(service);
  });
}

/// Direct ping from the main isolate (foreground timer path, all platforms).
Future<void> _sendDirectPing() async {
  await _sendPing(null);
}

/// Get GPS fix and PATCH it to the backend.
/// [service] is `null` when called from the foreground timer (main isolate).
Future<void> _sendPing(ServiceInstance? service) async {
  try {
    // ── Location ─────────────────────────────────────────────────────────────
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      print('[DriverLocationService] No location permission, skipping ping');
      return;
    }

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 7));

    // ── Auth token ───────────────────────────────────────────────────────────
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? prefs.getString('token');
    if (token == null || token.isEmpty) {
      print('[DriverLocationService] No auth token, skipping ping');
      return;
    }

    final baseUrl = prefs.getString('driver_location_base_url') ?? _kBackendUrl;

    // ── HTTP PATCH /api/driver/location ──────────────────────────────────────
    final response = await http
        .patch(
          Uri.parse('$baseUrl/api/driver/location'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'lat': pos.latitude,
            'lng': pos.longitude,
          }))
        .timeout(const Duration(seconds: 6));

    if (response.statusCode == 200) {
      final latStr = pos.latitude.toStringAsFixed(5);
      final lngStr = pos.longitude.toStringAsFixed(5);
      print('[DriverLocationService] ✓ Ping OK: $latStr, $lngStr');

      // ── Update Android foreground notification text ───────────────────────
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: _kDriverActiveTitle,
          content: '$latStr, $lngStr');
      }
    } else {
      print('[DriverLocationService] Ping failed: ${response.statusCode} ${response.body}');
    }
  } catch (e) {
    print('[DriverLocationService] Ping error: $e');
  }
}
