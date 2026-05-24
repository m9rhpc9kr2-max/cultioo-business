import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service for macOS native better functionality
/// Provides access to native macOS UI elements and effects
class MacOSNativeService {
  static const MethodChannel _channel = MethodChannel(
    'cupertino_native_better/macos');

  /// Check if platform is macOS
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;

  /// Check if native better is supported on this platform
  static Future<bool> isSupported() async {
    if (!isMacOS) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isSupported');
      return result ?? false;
    } catch (e) {
      debugPrint('Error checking native support: $e');
      return false;
    }
  }

  /// Get the current platform version
  static Future<String?> getPlatformVersion() async {
    if (!isMacOS) return null;
    try {
      return await _channel.invokeMethod<String>('getPlatformVersion');
    } catch (e) {
      debugPrint('Error getting platform version: $e');
      return null;
    }
  }

  /// Get the current system theme (light/dark)
  static Future<String?> getSystemTheme() async {
    if (!isMacOS) return null;
    try {
      return await _channel.invokeMethod<String>('getSystemTheme');
    } catch (e) {
      debugPrint('Error getting system theme: $e');
      return null;
    }
  }

  /// Enable or disable window vibrancy effect
  static Future<bool> setVibrancy({required bool enabled}) async {
    if (!isMacOS) return false;
    try {
      final result = await _channel.invokeMethod<bool>('enableVibrancy', {
        'enabled': enabled,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error setting vibrancy: $e');
      return false;
    }
  }

  /// Set window visual effect
  /// Available effects: titlebar, selection, menu, popover, sidebar, header,
  /// sheet, window, hud, fullscreen, tooltip, content, underwindow, underpage
  static Future<bool> setWindowEffect(String effect) async {
    if (!isMacOS) return false;
    try {
      final result = await _channel.invokeMethod<bool>('setWindowEffect', {
        'effect': effect,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error setting window effect: $e');
      return false;
    }
  }
}

/// Material types for blur effects
enum BlurMaterial {
  titlebar,
  selection,
  menu,
  popover,
  sidebar,
  header,
  sheet,
  window,
  hud,
  fullscreen,
  tooltip,
  content,
  underwindow,
  underpage;

  String get name {
    switch (this) {
      case BlurMaterial.titlebar:
        return 'titlebar';
      case BlurMaterial.selection:
        return 'selection';
      case BlurMaterial.menu:
        return 'menu';
      case BlurMaterial.popover:
        return 'popover';
      case BlurMaterial.sidebar:
        return 'sidebar';
      case BlurMaterial.header:
        return 'header';
      case BlurMaterial.sheet:
        return 'sheet';
      case BlurMaterial.window:
        return 'window';
      case BlurMaterial.hud:
        return 'hud';
      case BlurMaterial.fullscreen:
        return 'fullscreen';
      case BlurMaterial.tooltip:
        return 'tooltip';
      case BlurMaterial.content:
        return 'content';
      case BlurMaterial.underwindow:
        return 'underwindow';
      case BlurMaterial.underpage:
        return 'underpage';
    }
  }
}

/// Blending mode for blur effects
enum BlurBlendingMode {
  behindWindow,
  withinWindow;

  String get name {
    switch (this) {
      case BlurBlendingMode.behindWindow:
        return 'behindWindow';
      case BlurBlendingMode.withinWindow:
        return 'withinWindow';
    }
  }
}
