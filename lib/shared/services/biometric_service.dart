import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

class BiometricService {
  static final LocalAuthentication _localAuth = LocalAuthentication();

  /// Check if biometric authentication is available and enabled
  static Future<bool> isBiometricLoginAvailable() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool isBiometricEnabled =
          prefs.getBool('biometric_enabled') ?? false;

      if (!isBiometricEnabled) {
        return false;
      }

      final bool isAvailable = await _localAuth.canCheckBiometrics;
      final bool isDeviceSupported = await _localAuth.isDeviceSupported();

      return isAvailable && isDeviceSupported;
    } on PlatformException catch (e) {
      if (e.code == 'no_fragment_activity') {
        print(
          'FragmentActivity error - MainActivity needs to extend FlutterFragmentActivity',
        );
      }
      print(
        'PlatformException checking biometric availability: ${e.code} - ${e.message}',
      );
      return false;
    } catch (e) {
      print('Error checking biometric availability: $e');
      return false;
    }
  }

  /// Authenticate with biometric for login
  static Future<bool> authenticateForLogin() async {
    try {
      final bool isAvailable = await isBiometricLoginAvailable();
      if (!isAvailable) {
        return false;
      }

      final bool didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Use your biometric to sign in to your account',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      return didAuthenticate;
    } on PlatformException catch (e) {
      if (e.code == 'no_fragment_activity') {
        print(
          'FragmentActivity error - this should be fixed by updating MainActivity',
        );
      }
      print(
        'PlatformException during biometric login: ${e.code} - ${e.message}',
      );
      return false;
    } catch (e) {
      print('Biometric authentication error: $e');
      return false;
    }
  }

  /// Enable biometric authentication with verification (DO NOT USE - use setLocalBiometricEnabled instead)
  @Deprecated(
    'Use setLocalBiometricEnabled method instead to avoid double storage',
  )
  static Future<bool> enableBiometric() async {
    try {
      final bool isAvailable = await _localAuth.canCheckBiometrics;
      final bool isDeviceSupported = await _localAuth.isDeviceSupported();

      if (!isAvailable || !isDeviceSupported) {
        print(
          'Biometric not available: isAvailable=$isAvailable, isDeviceSupported=$isDeviceSupported',
        );
        return false;
      }

      final bool didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Please verify your biometric to enable this feature',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (didAuthenticate) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('biometric_enabled', true);
        return true;
      }

      return false;
    } on PlatformException catch (e) {
      if (e.code == 'no_fragment_activity') {
        print(
          'FragmentActivity error - this should be fixed by updating MainActivity',
        );
      }
      print('PlatformException enabling biometric: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      print('Error enabling biometric: $e');
      return false;
    }
  }

  /// Disable biometric authentication with verification
  static Future<bool> disableBiometric() async {
    try {
      final bool didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Please verify your biometric to disable this feature',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (didAuthenticate) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('biometric_enabled', false);
        return true;
      }

      return false;
    } catch (e) {
      print('Error disabling biometric: $e');
      return false;
    }
  }

  /// Test biometric authentication
  static Future<bool> testBiometric() async {
    try {
      final bool didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Test your biometric authentication',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      return didAuthenticate;
    } catch (e) {
      print('Error during biometric test: $e');
      return false;
    }
  }

  /// Get available biometric types
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }

  /// Check if device supports biometrics
  static Future<bool> isDeviceSupported() async {
    try {
      return await _localAuth.isDeviceSupported();
    } catch (e) {
      return false;
    }
  }

  /// Set local biometric enabled state (for synchronization with database)
  static Future<void> setLocalBiometricEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('biometric_enabled', enabled);
      print('🔧 Local biometric setting updated to: $enabled');
    } catch (e) {
      print('Error setting local biometric enabled: $e');
    }
  }

  /// Get local biometric enabled state
  static Future<bool> getLocalBiometricEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('biometric_enabled') ?? false;
    } catch (e) {
      print('Error getting local biometric enabled: $e');
      return false;
    }
  }
}
