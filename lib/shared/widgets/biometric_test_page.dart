import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../services/app_localizations.dart';
import '../services/biometric_service.dart';
import '../widgets/top_notification.dart';
import '../widgets/trade_republic_button.dart';
import '../../shared/widgets/cultioo_spinner.dart';

class BiometricTestPage extends StatefulWidget {
  const BiometricTestPage({super.key});

  @override
  State<BiometricTestPage> createState() => _BiometricTestPageState();
}

class _BiometricTestPageState extends State<BiometricTestPage> {
  bool _isDeviceSupported = false;
  bool _isBiometricEnabled = false;
  bool _isLoading = false;
  List<BiometricType> _availableBiometrics = [];

  @override
  void initState() {
    super.initState();
    _checkBiometricCapabilities();
  }

  Future<void> _checkBiometricCapabilities() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final bool deviceSupported = await BiometricService.isDeviceSupported();
      final bool biometricEnabled =
          await BiometricService.isBiometricLoginAvailable();
      final List<BiometricType> availableBiometrics =
          await BiometricService.getAvailableBiometrics();

      setState(() {
        _isDeviceSupported = deviceSupported;
        _isBiometricEnabled = biometricEnabled;
        _availableBiometrics = availableBiometrics;
      });
    } catch (e) {
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.errorCheckingBiometricCapabilities ?? "Error checking biometric capabilities"}: $e',
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testEnableBiometric() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final bool success = await BiometricService.enableBiometric();

      if (success) {
        TopNotification.success(
          context,
          AppLocalizations.of(context)?.biometricAuthEnabledSuccessfully ?? 'Biometric authentication enabled successfully!',
        );
        await _checkBiometricCapabilities(); // Refresh status
      } else {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.failedToEnableBiometricAuth ?? 'Failed to enable biometric authentication',
        );
      }
    } catch (e) {
      TopNotification.error(context, '${AppLocalizations.of(context)?.errorEnablingBiometric ?? "Error enabling biometric"}: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testBiometricLogin() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final bool success = await BiometricService.authenticateForLogin();

      if (success) {
        TopNotification.success(context, AppLocalizations.of(context)?.biometricLoginSuccessful ?? 'Biometric login successful!');
      } else {
        TopNotification.error(context, AppLocalizations.of(context)?.biometricLoginFailed ?? 'Biometric login failed');
      }
    } catch (e) {
      TopNotification.error(context, '${AppLocalizations.of(context)?.errorDuringBiometricLogin ?? "Error during biometric login"}: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testDisableBiometric() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final bool success = await BiometricService.disableBiometric();

      if (success) {
        TopNotification.success(
          context,
          AppLocalizations.of(context)?.biometricAuthDisabledSuccessfully ?? 'Biometric authentication disabled successfully!',
        );
        await _checkBiometricCapabilities(); // Refresh status
      } else {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.failedToDisableBiometricAuth ?? 'Failed to disable biometric authentication',
        );
      }
    } catch (e) {
      TopNotification.error(context, '${AppLocalizations.of(context)?.errorDisablingBiometric ?? "Error disabling biometric"}: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)?.biometricTest ?? 'Biometric Test'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Information
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)?.biometricStatus ?? 'Biometric Status',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildStatusRow(AppLocalizations.of(context)?.deviceSupported ?? 'Device Supported', _isDeviceSupported),
                    _buildStatusRow(AppLocalizations.of(context)?.biometricEnabled ?? 'Biometric Enabled', _isBiometricEnabled),
                    const SizedBox(height: 8),
                    Text(
                      'Available Biometrics: ${_availableBiometrics.map((e) => e.toString().split('.').last).join(', ')}',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Test Buttons
            Text(
              AppLocalizations.of(context)?.testActions ?? 'Test Actions',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),

            // Refresh Status
            SizedBox(
              width: double.infinity,
              child: TradeRepublicButton(
                label: AppLocalizations.of(context)?.refreshStatus ?? 'Refresh Status',
                onPressed: _isLoading ? null : _checkBiometricCapabilities,
                icon: const Icon(Icons.refresh),
                isSecondary: true,
              ),
            ),
            const SizedBox(height: 8),

            // Enable Biometric
            SizedBox(
              width: double.infinity,
              child: TradeRepublicButton(
                label: AppLocalizations.of(context)?.enableBiometric ?? 'Enable Biometric',
                onPressed:
                    (_isLoading || !_isDeviceSupported || _isBiometricEnabled)
                    ? null
                    : _testEnableBiometric,
                icon: const Icon(Icons.fingerprint),
              ),
            ),
            const SizedBox(height: 8),

            // Test Biometric Login
            SizedBox(
              width: double.infinity,
              child: TradeRepublicButton(
                label: AppLocalizations.of(context)?.testBiometricLogin ?? 'Test Biometric Login',
                onPressed: (_isLoading || !_isBiometricEnabled)
                    ? null
                    : _testBiometricLogin,
                icon: const Icon(Icons.login),
              ),
            ),
            const SizedBox(height: 8),

            // Disable Biometric
            SizedBox(
              width: double.infinity,
              child: TradeRepublicButton(
                label: AppLocalizations.of(context)?.disableBiometric ?? 'Disable Biometric',
                onPressed: (_isLoading || !_isBiometricEnabled)
                    ? null
                    : _testDisableBiometric,
                icon: const Icon(Icons.fingerprint_outlined),
                isDestructive: true,
              ),
            ),

            const Spacer(),

            // Loading Indicator
            if (_isLoading) const Center(child: CultiooLoadingIndicator()),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, bool status) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Icon(
            status ? Icons.check_circle : Icons.cancel,
            color: status ? Colors.green : Colors.red,
            size: 20,
          ),
        ],
      ),
    );
  }
}
