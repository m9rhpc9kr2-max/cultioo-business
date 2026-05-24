import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../widgets/trade_republic_bottom_sheet.dart';
import '../widgets/trade_republic_button.dart';
import '../widgets/trade_republic_text_field.dart';
import 'app_localizations.dart';

class BiometricAuthService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static final LocalAuthentication _localAuth = LocalAuthentication();

  // Storage keys
  static const String _biometricEnabledKey = 'biometric_enabled';
  static const String _twoFactorEnabledKey = 'two_factor_enabled';
  static const String _twoFactorCodeKey = 'two_factor_code';
  static const String _authBypassKey = 'auth_bypass';

  // Check if biometric authentication is available on device
  static Future<bool> isBiometricAvailable() async {
    try {
      final bool isAvailable = await _localAuth.canCheckBiometrics;
      final bool isDeviceSupported = await _localAuth.isDeviceSupported();
      final List<BiometricType> availableBiometrics = await _localAuth
          .getAvailableBiometrics();

      // Debug information
      print('🔍 Biometric Debug Info:');
      print('  - canCheckBiometrics: $isAvailable');
      print('  - isDeviceSupported: $isDeviceSupported');
      print('  - availableBiometrics: $availableBiometrics');
      print(
        '  - Final result: ${isAvailable && isDeviceSupported && availableBiometrics.isNotEmpty}');

      return isAvailable && isDeviceSupported && availableBiometrics.isNotEmpty;
    } catch (e) {
      print('❌ Error checking biometric availability: $e');
      return false;
    }
  }

  // Get available biometric types
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      print('Error getting available biometrics: $e');
      return [];
    }
  }

  // Enable biometric authentication
  static Future<bool> enableBiometric() async {
    try {
      // Check if biometric is available
      if (!await isBiometricAvailable()) {
        return false;
      }

      // Test biometric authentication
      final bool didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Please authenticate to enable biometric login',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true));

      if (didAuthenticate) {
        await _secureStorage.write(key: _biometricEnabledKey, value: 'true');
        return true;
      }

      return false;
    } catch (e) {
      print('Error enabling biometric: $e');
      return false;
    }
  }

  // Disable biometric authentication
  static Future<void> disableBiometric() async {
    await _secureStorage.delete(key: _biometricEnabledKey);
  }

  // Check if biometric is enabled
  static Future<bool> isBiometricEnabled() async {
    final String? isEnabled = await _secureStorage.read(
      key: _biometricEnabledKey);
    return isEnabled == 'true';
  }

  // Check if two-factor is enabled
  static Future<bool> isTwoFactorEnabled() async {
    final String? isEnabled = await _secureStorage.read(
      key: _twoFactorEnabledKey);
    return isEnabled == 'true';
  }

  // Set 2FA settings
  static Future<void> setTwoFactorSettings(bool enabled, String? code) async {
    await _secureStorage.write(
      key: _twoFactorEnabledKey,
      value: enabled.toString());
    if (enabled && code != null) {
      await _secureStorage.write(key: _twoFactorCodeKey, value: code);
    } else {
      await _secureStorage.delete(key: _twoFactorCodeKey);
    }
  }

  // Get 2FA settings
  static Future<Map<String, dynamic>> getTwoFactorSettings() async {
    final String? isEnabled = await _secureStorage.read(
      key: _twoFactorEnabledKey);
    final String? code = await _secureStorage.read(key: _twoFactorCodeKey);

    return {'enabled': isEnabled == 'true', 'code': code};
  }

  // Determine authentication method priority
  static Future<String> getAuthenticationMethod() async {
    final bool biometricEnabled = await isBiometricEnabled();
    final Map<String, dynamic> twoFactorSettings = await getTwoFactorSettings();

    // Priority: Biometric > 2FA > Password
    if (biometricEnabled && await isBiometricAvailable()) {
      return 'biometric';
    } else if (twoFactorSettings['enabled'] == true) {
      return 'two_factor';
    } else {
      return 'password';
    }
  }

  // Perform authentication based on method
  static Future<bool> authenticate(BuildContext context) async {
    final String method = await getAuthenticationMethod();

    switch (method) {
      case 'biometric':
        return await _authenticateWithBiometric();
      case 'two_factor':
        return await _authenticateWithTwoFactor(context);
      case 'password':
        return await _authenticateWithPassword(context);
      default:
        return false;
    }
  }

  // Biometric authentication
  static Future<bool> _authenticateWithBiometric() async {
    try {
      final bool didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Please authenticate to access the app',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true));

      return didAuthenticate;
    } catch (e) {
      print('Biometric authentication error: $e');
      return false;
    }
  }

  // Two-factor authentication
  static Future<bool> _authenticateWithTwoFactor(BuildContext context) async {
    final Map<String, dynamic> twoFactorSettings = await getTwoFactorSettings();
    final String? storedCode = twoFactorSettings['code'];

    if (storedCode == null) return false;

    return await TradeRepublicBottomSheet.show<bool>(
          context: context,
          isDismissible: false,
          enableDrag: false,
          child: _TwoFactorDialog(correctCode: storedCode)) ??
        false;
  }

  // Password authentication
  static Future<bool> _authenticateWithPassword(BuildContext context) async {
    return await TradeRepublicBottomSheet.show<bool>(
          context: context,
          isDismissible: false,
          enableDrag: false,
          child: const _PasswordDialog()) ??
        false;
  }

  // Set authentication bypass (for testing or after successful auth)
  static Future<void> setAuthBypass(bool bypass) async {
    if (bypass) {
      await _secureStorage.write(
        key: _authBypassKey,
        value: DateTime.now().millisecondsSinceEpoch.toString());
    } else {
      await _secureStorage.delete(key: _authBypassKey);
    }
  }

  // Check if auth bypass is active (within session)
  static Future<bool> isAuthBypassed() async {
    final String? bypassTime = await _secureStorage.read(key: _authBypassKey);
    if (bypassTime == null) return false;

    final int timestamp = int.tryParse(bypassTime) ?? 0;
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int sessionDuration = 30 * 60 * 1000; // 30 minutes in milliseconds

    // Check if bypass is still valid (within session time)
    if (now - timestamp < sessionDuration) {
      return true;
    } else {
      // Clear expired bypass
      await _secureStorage.delete(key: _authBypassKey);
      return false;
    }
  }

  // Clear all authentication data
  static Future<void> clearAll() async {
    await _secureStorage.deleteAll();
  }
}

// Two-Factor Authentication Dialog
class _TwoFactorDialog extends StatefulWidget {
  final String correctCode;

  const _TwoFactorDialog({required this.correctCode});

  @override
  State<_TwoFactorDialog> createState() => _TwoFactorDialogState();
}

class _TwoFactorDialogState extends State<_TwoFactorDialog> {
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        padding: EdgeInsets.all(24),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2))),
              Text(
                AppLocalizations.of(context)?.twoFactorAuthentication ?? 'Two-Factor Authentication',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
              SizedBox(height: 16),
              Text(
                AppLocalizations.of(context)?.enter8DigitVerificationCode ?? 'Enter your 8-digit verification code:',
                style: TextStyle(color: Colors.white70)),
              SizedBox(height: 16),
              TradeRepublicTextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                maxLength: 8,
                obscureText: true,
                hintText: '••••••••',
                onChanged: (value) {
                  if (_errorMessage.isNotEmpty) {
                    setState(() {
                      _errorMessage = '';
                    });
                  }
                }),
              if (_errorMessage.isNotEmpty) ...[
                SizedBox(height: 8),
                Text(
                  _errorMessage,
                  style: TextStyle(color: Colors.red, fontSize: 12)),
              ],
              SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TradeRepublicButton(
                      label: AppLocalizations.of(context)?.cancel ?? 'Cancel',
                      onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
                      isSecondary: true)),
                  SizedBox(width: 12),
                  Expanded(
                    child: TradeRepublicButton(
                      label: AppLocalizations.of(context)?.verify ?? 'Verify',
                      onPressed: _isLoading ? null : _verify)),
                ]),
            ]))));
  }

  void _verify() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    await Future.delayed(
      const Duration(milliseconds: 500)); // Simulate verification delay

    if (_codeController.text == widget.correctCode) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _errorMessage = 'Invalid code. Please try again.';
        _isLoading = false;
      });
      _codeController.clear();
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }
}

// Password Authentication Dialog
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  String _errorMessage = '';
  final bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        padding: EdgeInsets.all(24),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2))),
              Text(
                AppLocalizations.of(context)?.enterPassword ?? 'Enter Password',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
              SizedBox(height: 16),
              Text(
                AppLocalizations.of(context)?.enterYourAccountPassword ?? 'Enter your account password:',
                style: TextStyle(color: Colors.white70)),
              SizedBox(height: 16),
              TradeRepublicTextField(
                controller: _passwordController,
                obscureText: _obscureText,
                hintText: AppLocalizations.of(context)?.password ?? 'Password',
                onChanged: (value) {
                  if (_errorMessage.isNotEmpty) {
                    setState(() {
                      _errorMessage = '';
                    });
                  }
                }),
              if (_errorMessage.isNotEmpty) ...[
                SizedBox(height: 8),
                Text(
                  _errorMessage,
                  style: TextStyle(color: Colors.red, fontSize: 12)),
              ],
              SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TradeRepublicButton(
                      label: AppLocalizations.of(context)?.cancel ?? 'Cancel',
                      onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
                      isSecondary: true)),
                  SizedBox(width: 12),
                  Expanded(
                    child: TradeRepublicButton(
                      label: AppLocalizations.of(context)?.login ?? 'Login',
                      onPressed: _isLoading ? null : _authenticate)),
                ]),
            ]))));
  }

  void _authenticate() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    // Simulate password verification (in real app, this would call an API)
    await Future.delayed(const Duration(milliseconds: 1000));

    // Password verification - should be implemented with actual authentication
    if (_passwordController.text.isNotEmpty) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _errorMessage = 'Password cannot be empty';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }
}
