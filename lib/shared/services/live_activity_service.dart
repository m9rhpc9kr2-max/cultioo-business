import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:live_activities/live_activities.dart';

/// Wraps the live_activities plugin for Delvioo driver navigation.
///
/// Shows a Live Activity on the iOS lock screen / Dynamic Island with:
/// - Current phase (driving to pickup / at pickup / driving to delivery / at delivery)
/// - Distance and ETA to destination
/// - Waiting timer when the driver has arrived and is waiting for a QR scan
///
/// SETUP REQUIREMENTS (one-time, in Xcode):
/// 1. Add Widget Extension target named "DelviooWidget" (File → New → Target → Widget Extension).
/// 2. Add "App Groups" capability to BOTH Runner and DelviooWidget targets.
///    Use the identifier: group.cultioo.businessapp
/// 3. Add "Push Notifications" capability to the Runner target only.
/// 4. Copy the Swift files from ios/DelviooWidget/ into the new extension target.
/// 5. Set the DelviooWidget deployment target to iOS 16.1.
class DelviooLiveActivityService {
  static final LiveActivities _plugin = LiveActivities();
  static bool _activityCreated = false;
  static bool _initialized = false;
  static DateTime? _lastUpdate;

  /// Stable activity ID — must be consistent across create/update calls.
  static const String _activityKey = 'delvioo_navigation';

  /// App Group ID — must match Runner.entitlements and DelviooWidget.entitlements.
  static const String appGroupId = 'group.cultioo.businessapp';

  static Future<void> _init() async {
    if (_initialized) return;
    try {
      await _plugin.init(
        appGroupId: appGroupId,
        urlScheme: 'cultioo',
      );
      _initialized = true;

      // Clean up any stale activities left from a previous app session so they
      // don't interfere with a fresh createOrUpdateActivity call.
      try {
        final staleIds = await _plugin.getAllActivitiesIds();
        if (staleIds.isNotEmpty) {
          debugPrint('🏝️ DelviooLiveActivity: ending ${staleIds.length} stale activit(ies) from previous session');
          await _plugin.endAllActivities();
        }
      } catch (_) {
        // Non-critical — ignore if listing/ending stale activities fails.
      }

      debugPrint('✅ DelviooLiveActivity: initialized');
    } catch (e) {
      debugPrint('⚠️ DelviooLiveActivity: init failed – $e');
    }
  }

  /// Creates a new activity or resumes / updates an existing one.
  ///
  /// Uses [createOrUpdateActivity] which atomically checks whether an activity
  /// with [_activityKey] already exists (e.g. from the current session) and
  /// updates it, or creates a fresh one when none is found.
  ///
  /// Set [force] to `true` to bypass the 30-second throttle (use on phase
  /// changes, arrival, and waiting-timer start).
  static Future<void> update({
    required String orderNumber,
    required String phase,
    required String distanceText,
    required String etaText,
    required String destinationAddress,
    bool isWaitingTimerActive = false,
    int waitingElapsedSeconds = 0,
    bool force = false,
  }) async {
    if (!Platform.isIOS) return;
    await _init();
    debugPrint('🏝️ DelviooLiveActivity: update() – force=$force, created=$_activityCreated');

    // Throttle background navigation updates to ~30 s.
    // Exception: when the waiting timer is active we update every 5 s so the
    // Dynamic Island / Android notification shows a live countdown.
    final int throttleSeconds = isWaitingTimerActive ? 5 : 30;
    if (!force &&
        _lastUpdate != null &&
        DateTime.now().difference(_lastUpdate!).inSeconds < throttleSeconds) {
      return;
    }
    _lastUpdate = DateTime.now();

    final Map<String, dynamic> data = {
      'orderNumber': orderNumber,
      'phase': phase,
      'distanceText': distanceText,
      'etaText': etaText,
      'destinationAddress': destinationAddress,
      'isWaitingTimerActive': isWaitingTimerActive,
      'waitingElapsedSeconds': waitingElapsedSeconds,
    };

    try {
      final bool supported = await _plugin.areActivitiesEnabled();
      debugPrint('🏝️ DelviooLiveActivity: areActivitiesEnabled=$supported');
      if (!supported) return;

      // createOrUpdateActivity: creates if absent, updates if present.
      // iOSEnableRemoteUpdates=false: we don't use APNs push-to-update.
      await _plugin.createOrUpdateActivity(
        _activityKey,
        data,
        iOSEnableRemoteUpdates: false,
      );
      _activityCreated = true;
      debugPrint('✅ DelviooLiveActivity: createOrUpdate OK (phase=$phase)');
    } catch (e) {
      debugPrint('⚠️ DelviooLiveActivity: update failed – $e');
      _activityCreated = false; // reset so we attempt a fresh create next time
      _lastUpdate = null;       // allow immediate retry on next call
    }
  }

  /// Ends ALL live activities (call when navigation is fully completed or reset).
  static Future<void> end() async {
    if (!Platform.isIOS) return;
    try {
      await _plugin.endAllActivities();
      _activityCreated = false;
      debugPrint('✅ DelviooLiveActivity: ended all activities');
    } catch (e) {
      debugPrint('⚠️ DelviooLiveActivity: end failed – $e');
    }
  }
}
