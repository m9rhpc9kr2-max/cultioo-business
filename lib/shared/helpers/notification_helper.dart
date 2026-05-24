import 'package:flutter/material.dart';
import '../services/app_localizations.dart';
import '../widgets/animated_notification.dart';

class NotificationHelper {
  static void showSuccess(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    AnimatedNotification.show(
      context,
      message: message,
      type: NotificationType.success,
      duration: duration ?? const Duration(seconds: 3));
  }

  static void showError(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    AnimatedNotification.show(
      context,
      message: message,
      type: NotificationType.error,
      duration: duration ?? const Duration(seconds: 4));
  }

  static void showWarning(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    AnimatedNotification.show(
      context,
      message: message,
      type: NotificationType.warning,
      duration: duration ?? const Duration(seconds: 3));
  }

  static void showInfo(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    AnimatedNotification.show(
      context,
      message: message,
      type: NotificationType.info,
      duration: duration ?? const Duration(seconds: 2));
  }

  // Business-specific notifications
  static void showBusinessUpgradeSuccess(BuildContext context) {
    showSuccess(
      context,
      '🎉 Business upgrade completed successfully!',
      duration: const Duration(seconds: 4));
  }

  static void showBusinessUpgradeError(BuildContext context, String? error) {
    showError(
      context,
      '❌ Business upgrade failed: ${error ?? AppLocalizations.of(context)!.tr('Unknown error')}',
      duration: const Duration(seconds: 5));
  }

  static void showImageUploadSuccess(BuildContext context, String source) {
    showSuccess(
      context,
      '📸 Image from $source selected successfully!',
      duration: const Duration(seconds: 2));
  }

  static void showImageUploadError(BuildContext context, String source) {
    showError(
      context,
      '🚫 Error selecting image from $source',
      duration: const Duration(seconds: 3));
  }

  static void showAddressSearchInfo(BuildContext context, int count) {
    if (count > 0) {
      showInfo(
        context,
        '📍 Found $count address suggestion${count == 1 ? '' : 's'}',
        duration: const Duration(seconds: 2));
    }
  }

  static void showValidationWarning(BuildContext context, String field) {
    showWarning(
      context,
      '⚠️ Please fill in your $field',
      duration: const Duration(seconds: 3));
  }

  static void showNetworkError(BuildContext context) {
    showError(
      context,
      '🌐 Network error. Please check your connection.',
      duration: const Duration(seconds: 4));
  }

  static void showFormIncomplete(BuildContext context) {
    showWarning(
      context,
      '📝 Please fill in all required fields',
      duration: const Duration(seconds: 3));
  }
}
