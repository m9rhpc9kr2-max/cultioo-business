import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../../shared/services/app_settings.dart';
import '../../shared/services/api_service.dart';
import '../../shared/widgets/trade_republic_button.dart';
import '../../shared/widgets/trade_republic_text_field.dart';
import '../../shared/widgets/trade_republic_bottom_sheet.dart';
import '../../shared/services/app_localizations.dart';

class TwoFactorPage extends StatefulWidget {
  final String userId;
  final String email;
  final String password;

  const TwoFactorPage({
    super.key,
    required this.userId,
    required this.email,
    required this.password,
  });

  @override
  State<TwoFactorPage> createState() => _TwoFactorPageState();
}

class _TwoFactorPageState extends State<TwoFactorPage> {
  final _codeController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify2FA() async {
    if (_codeController.text.isEmpty) {
      _showErrorDialog(AppLocalizations.of(context)?.pleaseEnterThe2faCode ?? 'Please enter the 2FA code');
      return;
    }

    if (_codeController.text.length != 6) {
      _showErrorDialog(AppLocalizations.of(context)?.twoFaCodeMust6Digits ?? '2FA code must be 6 digits');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await ApiService.login(
        email: widget.email,
        password: widget.password,
        twoFACode: _codeController.text,
      );

      if (mounted) {
        setState(() => _isLoading = false);

        if (result['success']) {
          // Save user data
          final AppSettings appSettings = AppSettings();
          await appSettings.setIsLoggedIn(true);
          await appSettings.setUserType(AppLocalizations.of(context)?.businessLabel ?? 'Business');
          await appSettings.setUserData(
            userId: result['user']['username'], // username als ID
            name:
                '${result['user']['firstname'] ?? ''} ${result['user']['lastname'] ?? ''}',
            email: result['user']['email'],
          );

          // Navigate to main app
          if (mounted) {
            Navigator.pushReplacementNamed(context, '/main');
          }
        } else {
          _showErrorDialog(result['message'] ?? AppLocalizations.of(context)?.twoFaVerificationFailed ?? '2FA verification failed');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorDialog('${AppLocalizations.of(context)?.connectionError ?? 'Connection error'}: ${e.toString()}');
      }
    }
  }

  void _showErrorDialog(String message) {
    final appSettings = AppSettings();
    final isLight = appSettings.isLightMode(context);
    final title = AppLocalizations.of(context)?.verificationError ?? 'Verification Error';

    TradeRepublicBottomSheet.show(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(CupertinoIcons.exclamationmark_circle, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: TradeRepublicButton(
              label: AppLocalizations.of(context)?.ok ?? 'OK',
              onPressed: () => Navigator.of(context).pop(),
              isSecondary: true,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings appSettings = AppSettings();
    final isLight = appSettings.isLightMode(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    return Scaffold(
      backgroundColor: isLight ? Colors.white : Colors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: Platform.isIOS || Platform.isAndroid
                ? const BouncingScrollPhysics()
                : const ClampingScrollPhysics(),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: isDesktop ? 380 : double.infinity,
              ),
              padding: EdgeInsets.symmetric(horizontal: isDesktop ? 0 : 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(height: screenHeight * 0.08),

                  // Icon
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: isLight ? Colors.black : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      CupertinoIcons.lock_shield_fill,
                      size: 32,
                      color: isLight ? Colors.white : Colors.black,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Title
                  Text(
                    AppLocalizations.of(context)?.twoFactorAuthentication ?? 'Two-Factor Authentication',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: isLight ? Colors.black : Colors.white,
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 8),

                  // Subtitle
                  Text(
                    AppLocalizations.of(context)?.enterThe6DigitCode ?? 'Enter the 6-digit code from your authenticator app',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5),
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 48),

                  // Code Input
                  Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.04),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: TradeRepublicTextField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      hintText: '000000',
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Verify Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: TradeRepublicButton(
                      label: AppLocalizations.of(context)?.verify ?? 'Verify',
                      onPressed: _isLoading ? null : _verify2FA,
                      isLoading: _isLoading,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Back Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: TradeRepublicButton(
                      label: AppLocalizations.of(context)?.backToLogin ?? 'Back to Login',
                      onPressed: () => Navigator.of(context).pop(),
                      isSecondary: true,
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Info Text
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.info_circle,
                        size: 16,
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.4),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        AppLocalizations.of(context)?.havingTroubleContactSupport ?? 'Having trouble? Contact support',
                        style: TextStyle(
                          fontSize: 13,
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.4),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: screenHeight * 0.1),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
