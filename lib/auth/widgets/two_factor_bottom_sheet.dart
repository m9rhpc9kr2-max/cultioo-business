import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../shared/widgets/glass_effect.dart';
import '../../shared/widgets/trade_republic_text_field.dart';
import '../../shared/services/app_settings.dart';
import '../../shared/widgets/top_notification.dart';
import '../../shared/widgets/drag_handle.dart';
import '../../shared/services/app_localizations.dart';

import '../../shared/widgets/trade_republic_bottom_sheet.dart';

class TwoFactorBottomSheet extends StatefulWidget {
  final String userId;
  final String email;
  final String password;
  final Function(String) onVerify;

  const TwoFactorBottomSheet({
    super.key,
    required this.userId,
    required this.email,
    required this.password,
    required this.onVerify,
  });

  @override
  State<TwoFactorBottomSheet> createState() => _TwoFactorBottomSheetState();
}

class _TwoFactorBottomSheetState extends State<TwoFactorBottomSheet>
    with TickerProviderStateMixin {
  final _codeController = TextEditingController();
  final _focusNode = FocusNode();
  bool _isLoading = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _animationController.forward();

    // Auto-focus the input field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _codeController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onCodeChanged(String value) {
    if (value.length == 8) {
      // Auto-submit when 8 digits are entered
      _verifyCode();
    }
  }

  void _verifyCode() {
    if (_codeController.text.length != 8) {
      _showError(AppLocalizations.of(context)?.pleaseEnterValid8Digit ?? 'Please enter an 8-digit code');
      return;
    }

    setState(() => _isLoading = true);
    widget.onVerify(_codeController.text);
  }

  void _showError(String message) {
    TopNotification.error(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings appSettings = Provider.of<AppSettings>(context);
    final isLight = appSettings.isLightMode(context);

    return FadeTransition(
        opacity: _fadeAnimation,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Trade Republic style handle bar
              DragHandle(),

              // Header
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isLight
                          ? Colors.blue.withOpacity(0.1)
                          : Colors.blue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(Icons.security, color: Colors.blue, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context)?.twoFactorAuthentication ?? 'Two-Factor Authentication',
                          style: TextStyle(
                            color: isLight ? Colors.black : Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Enter your 8-digit verification code',
                          style: TextStyle(
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.5),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Code input field
              GlassContainer(
                width: double.infinity,

                child: Column(
                  children: [
                    TradeRepublicTextField(
                      controller: _codeController,
                      focusNode: _focusNode,
                      keyboardType: TextInputType.number,
                      maxLength: 8,
                      textAlign: TextAlign.center,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: _onCodeChanged,
                      hintText: '00000000',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Info text
              Center(
                child: Text(
                  AppLocalizations.of(context)?.checkYourAuthenticatorApp ?? 'Check your authenticator app for the code',
                  style: TextStyle(
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.5,
                    ),
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
    );
  }
}

// Helper function to show the 2FA bottom sheet
Future<void> show2FABottomSheet({
  required BuildContext context,
  required String userId,
  required String email,
  required String password,
  required Function(String) onVerify,
}) {
  return TradeRepublicBottomSheet.show(
    context: context,
    bottomPadding: 20.0,
    child: TwoFactorBottomSheet(
      userId: userId,
      email: email,
      password: password,
      onVerify: onVerify,
    ),
  );
}
