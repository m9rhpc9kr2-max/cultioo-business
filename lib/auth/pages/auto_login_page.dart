import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../shared/services/app_settings.dart';
import '../../shared/services/biometric_service.dart';
import '../../config/api_config.dart';
import '../../shared/widgets/top_notification.dart';
import '../../shared/widgets/trade_republic_button.dart';
import '../../shared/widgets/trade_republic_text_field.dart';
import '../../shared/widgets/drag_handle.dart';

import 'dart:convert';
import '../../shared/widgets/trade_republic_bottom_sheet.dart';

import 'dart:io' show Platform;
import 'package:http/http.dart' as http;
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../../shared/services/app_localizations.dart';
import '../../shared/widgets/cultioo_spinner.dart';
import '../../shared/widgets/trade_republic_tap.dart';
import 'package:cultioo_business/shared/widgets/desktop_app_wrapper.dart';
import 'package:cultioo_business/shared/widgets/desktop_optimized_widgets.dart';

Widget _autoLoginSheetTopChrome() {
  final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  return isDesktop ? const SizedBox.shrink() : DragHandle();
}

class AutoLoginPage extends StatefulWidget {
  const AutoLoginPage({super.key});

  @override
  State<AutoLoginPage> createState() => _AutoLoginPageState();
}

class _AutoLoginPageState extends State<AutoLoginPage> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _twoFactorController = TextEditingController();
  bool _isLoading = false;
  Map<String, dynamic>? _userSecuritySettings;
  bool _autoLoginAuthCompleted = false;

  @override
  void initState() {
    super.initState();
    print(
      '🔍🔍🔍 AUTO-LOGIN PAGE INITIATED - This should ONLY appear when app starts with existing token',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkSilentLogin();
    });
  }

  Future<void> _checkSilentLogin() async {
    // Outer safety net — if anything goes wrong we always navigate away
    // instead of leaving the user stuck on a blank screen.
    try {
      await _doCheckSilentLogin();
    } catch (e, stack) {
      print('[ERROR] _checkSilentLogin unhandled exception: $e\n$stack');
      if (mounted) {
        final appSettings = Provider.of<AppSettings>(context, listen: false);
        final isDriver = appSettings.userType == 'Driver';
        Navigator.of(context).pushReplacementNamed(
          isDriver ? '/delvioo-main' : '/main',
        );
      }
    }
  }

  Future<void> _doCheckSilentLogin() async {
    // ✅ IMPORTANT: Load user data from SharedPreferences FIRST
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    await appSettings.loadUserData();

    print('[SUCCESS] User data loaded - userType: ${appSettings.userType}');
    print('[SUCCESS] Token found - proceeding with silent login check');

    // ✅ Use local biometric settings only (no need for backend profile check)
    final bool localBiometricEnabled =
        await BiometricService.getLocalBiometricEnabled();

    print(
      '🔍 Auto-login security check: localBiometric=$localBiometricEnabled',
    );

    // Check if 2FA is enabled by querying the backend.
    // Use a short timeout so a slow network never blocks navigation.
    bool has2FAEnabled = false;
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/auth/check-2fa'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': appSettings.userEmail ?? appSettings.userName ?? '',
              'isDelviooMode': appSettings.userType == 'Driver',
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        has2FAEnabled = data['requiresTwoFA'] == true;
        print('🔍 2FA enabled status: $has2FAEnabled');
        print('🔍 Full response: $data');
      } else {
        print('[ERROR] 2FA check failed with status: ${response.statusCode}');
        print('[ERROR] Response body: ${response.body}');
      }
    } catch (e) {
      // Network error or timeout — assume 2FA is off, proceed silently
      print('[WARN] 2FA check failed ($e) — assuming disabled, continuing');
    }

    // Set minimal security settings based on local storage and backend check
    _userSecuritySettings = {
      'biometric_enabled': localBiometricEnabled ? 1 : 0,
      'has_2fa_enabled': has2FAEnabled ? 1 : 0,
      'twofa': null,
    };

    if (mounted) {
      final currentUserType = appSettings.userType;

      // ✅ SILENT AUTO-LOGIN: no security features enabled → skip the modal
      // The stored token is sufficient to restore the session without re-authentication.
      if (!localBiometricEnabled && !has2FAEnabled) {
        print('✅ No security features enabled → silent auto-login, skipping re-auth modal');
        if (currentUserType == 'Driver') {
          Navigator.of(context).pushReplacementNamed('/delvioo-main');
        } else {
          Navigator.of(context).pushReplacementNamed('/main');
        }
        return;
      }

      // Security features are enabled → show auth modal first.
      // After successful auth we navigate to the correct home route.
      print('🔐 Security features enabled (biometric=$localBiometricEnabled, 2FA=$has2FAEnabled) → showing auth modal');

      await _showLoginModalFromContext(context, appSettings);
      if (!mounted) return;

      if (_autoLoginAuthCompleted) {
        if (currentUserType == 'Driver') {
          Navigator.of(context).pushReplacementNamed('/delvioo-main');
        } else {
          Navigator.of(context).pushReplacementNamed('/main');
        }
      }
    }
  }

  Future<void> _showLoginModalFromContext(
    BuildContext ctx,
    AppSettings appSettings,
  ) async {
    final isLight = appSettings.isLightMode(ctx);
    _autoLoginAuthCompleted = false;

    // Show as bottom sheet that doesn't go all the way to top
    await TradeRepublicBottomSheet.show(
      context: ctx,
      maxHeight: 820,
      backgroundColor: isLight ? Colors.white : const Color(0xFF0B0B0D),
      useRootNavigator: true,
      isDismissible: false,
      enableDrag: false,
      child: _AutoLoginModalContent(
        appSettings: appSettings,
        isLight: isLight,
        userSecuritySettings: _userSecuritySettings,
        onAuthenticated: () {
          _autoLoginAuthCompleted = true;
        },
      ),
    );

    if (!_autoLoginAuthCompleted) {
      await _forceLogoutAndClearLocalData();
    }
  }

  Future<void> _forceLogoutAndClearLocalData() async {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    await appSettings.logout();

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    // Best effort: remove temporary/cache files created by the app.
    try {
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        for (final entity in tempDir.listSync(recursive: false)) {
          try {
            entity.deleteSync(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  void _handleAuthenticationFailure() {
    // User failed authentication or cancelled - go to login page
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  Widget _buildLoginModal(AppSettings appSettings, {bool fullScreen = false}) {
    final isLight = appSettings.isLightMode(context);

    // When fullScreen is true we remove the rounded top and outer padding so
    // the content can occupy the entire vertical space (no top/bottom gap)
    final EdgeInsets outerPadding = fullScreen
        ? const EdgeInsets.symmetric(horizontal: 20, vertical: 8)
        : const EdgeInsets.all(24);

    final Widget content = Padding(
      padding: outerPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Modern Handle bar - same as settings
          _autoLoginSheetTopChrome(),

          // Welcome header
          Row(
            children: [
              Icon(
                appSettings.userType == 'Driver'
                    ? CupertinoIcons.car_detailed
                    : CupertinoIcons.briefcase_fill,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Flexible(child: Text(
                AppLocalizations.of(context)?.welcomeBack ?? 'Welcome back!',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white, letterSpacing: -0.4),
              )),
            ],
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

          // Subtitle with Account Type
          Text(
            appSettings.userId != null
                ? 'Hello, ${appSettings.userId}'
                : AppLocalizations.of(context)?.continueToYourAccount ?? 'Continue to your account',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 4),

          // Account Type Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: appSettings.userType == 'Driver'
                    ? [const Color(0xFF34C759), const Color(0xFF30D158)]
                    : [
                        const Color(0xFF007AFF).withOpacity(0.2),
                        const Color(0xFF5AC8FA).withOpacity(0.2),
                      ],
              ),
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  appSettings.userType == 'Driver'
                      ? CupertinoIcons.car_detailed
                      : CupertinoIcons.briefcase_fill,
                  size: 16,
                  color: appSettings.userType == 'Driver'
                      ? Colors.white
                      : const Color(0xFF007AFF),
                ),
                const SizedBox(width: 8),
                Text(
                  '${appSettings.userType == 'Driver' ? AppLocalizations.of(context)?.delviooLabel ?? 'Delvioo' : 'Business'} Account',
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w600,
                    color: appSettings.userType == 'Driver'
                        ? Colors.white
                        : const Color(0xFF007AFF),
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Authentication options
          Column(
            children: [
              // Biometric authentication
              if (_userSecuritySettings?['biometric_enabled'] == 1)
                _buildAuthOption(
                  icon: CupertinoIcons.hand_raised_fill,
                  title: AppLocalizations.of(context)?.useBiometric ?? 'Use Biometric',
                  subtitle: AppLocalizations.of(context)?.quickAndSecureAccess ?? 'Quick and secure access',
                  onTap: _authenticateWithBiometric,
                  isLight: isLight,
                ),

              // 2FA authentication
              if (_userSecuritySettings?['has_2fa_enabled'] == 1)
                _buildAuthOption(
                  icon: CupertinoIcons.shield_fill,
                  title: AppLocalizations.of(context)?.twoFactorAuthentication ?? 'Two-Factor Authentication',
                  subtitle: AppLocalizations.of(context)?.useYour8DigitCode ?? 'Use your 8-digit code',
                  onTap: _showTwoFactorInput,
                  isLight: isLight,
                ),

              // Password authentication
              _buildAuthOption(
                icon: CupertinoIcons.lock_fill,
                title: AppLocalizations.of(context)?.usePassword ?? 'Use Password',
                subtitle: AppLocalizations.of(context)?.enterYourPassword ?? 'Enter your password',
                onTap: _showPasswordInput,
                isLight: isLight,
              ),
            ],
          ),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

          // Action buttons - Uber/Trade Republic Style
          Row(
            children: [
              Expanded(
                child: TradeRepublicTap(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context).pushReplacementNamed('/login');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(isLight ? 0.05 : 0.8),
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                    ),
                    child: Center(
                      child: Text(
                        AppLocalizations.of(context)?.cancel ?? 'Cancel',
                        style: TextStyle(
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFFF3B30),
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TradeRepublicTap(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _switchAccount();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(isLight ? 0.05 : 0.8),
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                    ),
                    child: Center(
                      child: Text(
                        AppLocalizations.of(context)?.switchAccount ?? 'Switch Account',
                        style: TextStyle(
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                          fontWeight: FontWeight.w600,
                          color: isLight ? Colors.black : Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
        ],
      ),
    );

    if (fullScreen) {
      // For fullscreen we return the column directly so the caller's Scaffold/SafeArea
      // controls the full-screen layout and there are no additional rounded corners/padding.
      return SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        child: content,
      );
    }

    return content;
  }

  Widget _buildAuthOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isLight,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: TradeRepublicTap(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isLight
                  ? [Colors.white, Colors.transparent]
                  : [Colors.transparent, const Color(0xFF000000)],
            ),
            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isLight
                        ? [
                            const Color(0xFF007AFF).withOpacity(0.15),
                            const Color(0xFF5AC8FA).withOpacity(0.1),
                          ]
                        : [
                            const Color(0xFF0A84FF).withOpacity(0.25),
                            const Color(0xFF5AC8FA).withOpacity(0.15),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: (isLight ? Colors.black : Colors.white).withOpacity(
                    0.85,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                        fontWeight: FontWeight.w600,
                        color: isLight ? Colors.black : Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.5),
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: (isLight ? Colors.black : Colors.white).withOpacity(
                  0.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _authenticateWithBiometric() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final result = await BiometricService.authenticateForLogin();
      if (result) {
        // Navigate directly to home
        await _navigateToHome();
      }
    } catch (e) {
      if (mounted) {
        TopNotification.show(
          context,
          message: '${AppLocalizations.of(context)?.biometricAuthFailed ?? 'Biometric authentication failed'}: $e',
          type: NotificationType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showPasswordInput() {
    if (!mounted) return;

    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final isLight = appSettings.isLightMode(context);
    bool showPassword = false;
    bool hasError = false;

    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: 700,
      backgroundColor: isLight ? Colors.white : const Color(0xFF0B0B0D),
      bottomPadding: 20.0,
      child: StatefulBuilder(
        // ✅ Wrap with StatefulBuilder
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Modern Handle bar
              _autoLoginSheetTopChrome(),

              Row(
                children: [
                  Icon(CupertinoIcons.lock, size: 22, color: isLight ? Colors.black : Colors.white),
                  const SizedBox(width: 12),
                  Flexible(child: Text(
                    AppLocalizations.of(context)?.enterPassword ?? 'Enter Password',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                      color: isLight ? Colors.black : Colors.white, letterSpacing: -0.4),
                  )),
                ],
              ),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

              Text(
                AppLocalizations.of(context)?.authenticateWithPassword ?? 'Authenticate with your password',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: (isLight ? Colors.black : Colors.white).withOpacity(
                    0.5,
                  ),
                ),
              ),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

              TradeRepublicTextField.password(
                controller: _passwordController,
                hintText: AppLocalizations.of(context)?.password ?? 'Password',
                autofocus: true,
                prefixIcon: const Icon(CupertinoIcons.lock_fill),
                onChanged: (value) {
                  if (hasError) {
                    setModalState(() => hasError = false);
                  }
                },
              ),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

              Row(
                children: [
                  Expanded(
                    child: TradeRepublicButton(
                      label: AppLocalizations.of(context)?.cancel ?? 'Cancel',
                      isSecondary: true,
                      onPressed: () {
                        Navigator.of(context).pop();
                        _handleAuthenticationFailure();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TradeRepublicButton(
                      label: AppLocalizations.of(context)?.login ?? 'Login',
                      backgroundColor: const Color(0xFF34C759),
                      isLoading: _isLoading,
                      onPressed: _isLoading
                          ? null
                          : () async {
                              final password = _passwordController.text;
                              if (password.isEmpty) {
                                setModalState(() => hasError = true);
                                return;
                              }
                              setModalState(() => hasError = false);
                              final success = await _authenticateWithPassword();
                              if (success &&
                                  mounted &&
                                  Navigator.canPop(context)) {
                                Navigator.of(context).pop();
                              } else if (mounted) {
                                setModalState(() => hasError = true);
                              }
                            },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showTwoFactorInput() {
    if (!mounted) return;

    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final isLight = appSettings.isLightMode(context);

    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: 700,
      backgroundColor: isLight ? Colors.white : const Color(0xFF0B0B0D),
      bottomPadding: 20.0,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Modern Handle bar
            _autoLoginSheetTopChrome(),

            Row(
              children: [
                Icon(CupertinoIcons.shield, size: 22, color: isLight ? Colors.black : Colors.white),
                const SizedBox(width: 12),
                Flexible(child: Text(
                  AppLocalizations.of(context)?.twoFactorAuthentication ?? 'Two-Factor Authentication',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white, letterSpacing: -0.4),
                )),
              ],
            ),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

            Text(
              AppLocalizations.of(context)?.enterYour8Digit2faCode ?? 'Enter your 8-digit 2FA code',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
              ),
            ),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

            TradeRepublicTextField.code(
              controller: _twoFactorController,
              hintText: '12345678',
              maxLength: 8,
              autofocus: true,
            ),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

            Row(
              children: [
                Expanded(
                  child: (Platform.isIOS)
                      ? TradeRepublicButton(
                          label: AppLocalizations.of(context)?.cancel ?? 'Cancel',
                          onPressed: () {
                            Navigator.of(context).pop();
                            _handleAuthenticationFailure();
                          },
                        )
                      : TradeRepublicTap(
                          onTap: () {
                            Navigator.of(context).pop();
                            _handleAuthenticationFailure();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(isLight ? 0.1 : 0.7),
                              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                            ),
                            child: Center(
                              child: Text(
                                AppLocalizations.of(context)?.cancel ?? 'Cancel',
                                style: TextStyle(
                                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                                  fontWeight: FontWeight.w600,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: (Platform.isIOS)
                      ? TradeRepublicButton(
                          label: AppLocalizations.of(context)?.verify ?? 'Verify',
                          onPressed: _isLoading
                              ? null
                              : () {
                                  Navigator.of(context).pop();
                                  _authenticateWithTwoFactor();
                                },
                        )
                      : TradeRepublicTap(
                          onTap: _isLoading
                              ? null
                              : () {
                                  Navigator.of(context).pop();
                                  _authenticateWithTwoFactor();
                                },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF34C759), Color(0xFF30D158)],
                              ),
                              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF34C759,
                                  ).withOpacity(0.3),
                                  offset: const Offset(0, 4),
                                  blurRadius: 12,
                                ),
                              ],
                            ),
                            child: Center(
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CultiooLoadingIndicator(size: 24),
                                    )
                                  : Text(
                                      AppLocalizations.of(context)?.verify ?? 'Verify',
                                      style: TextStyle(
                                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<bool> _authenticateWithPassword() async {
    if (_passwordController.text.isEmpty) {
      return false;
    }

    if (mounted) setState(() => _isLoading = true);

    try {
      final appSettings = Provider.of<AppSettings>(context, listen: false);

      print(
        '🔍 Available credentials: email=${appSettings.userEmail}, userId=${appSettings.userId}, userName=${appSettings.userName}',
      );

      http.Response? successResponse;

      // Try multiple login approaches
      final loginAttempts = [
        // Attempt 1: Email field with actual email
        if (appSettings.userEmail != null) {'email': appSettings.userEmail!},
        // Attempt 2: Email field with userName (backend checks both email and username in DB)
        if (appSettings.userName != null) {'email': appSettings.userName!},
        // Attempt 3: Email field with userId as string
        if (appSettings.userId != null)
          {'email': appSettings.userId.toString()},
      ];

      for (int i = 0; i < loginAttempts.length; i++) {
        final credentials = loginAttempts[i];
        final credentialType = credentials.keys.first;
        final credentialValue = credentials.values.first;

        print(
          '[LOGIN] Attempt ${i + 1}: Trying login with $credentialType = $credentialValue',
        );

        // Build the request body with dynamic key
        final requestBody = <String, dynamic>{
          'password': _passwordController.text,
          'isDelviooMode':
              appSettings.userType == 'Driver', // Add Delvioo mode flag
        };
        requestBody[credentialType] = credentialValue; // Add dynamic key

        print('🔍 Request body: ${jsonEncode(requestBody)}');

        final response = await http.post(
          Uri.parse('${ApiConfig.baseUrl}/api/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(requestBody),
        );

        print('🔍 Response: ${response.statusCode}');
        if (response.statusCode != 200) {
          print('🔍 Response body: ${response.body}');
        }

        // Accept both 200 (success) and 202 (requires 2FA)
        if (response.statusCode == 200 || response.statusCode == 202) {
          successResponse = response;
          print(
            '[SUCCESS] Login successful with $credentialType = $credentialValue',
          );
          break;
        }
      }

      if (successResponse != null) {
        print(
          '[DEBUG] Auto-login password response body: ${successResponse.body}',
        );

        final data = jsonDecode(successResponse.body);

        // Check if 2FA is required
        if (data['requiresTwoFA'] == true) {
          if (mounted) {
            // Store user ID for 2FA verification
            _userSecuritySettings = {
              ..._userSecuritySettings ?? {},
              'userId': data['userId']?.toString() ?? '',
              'requires_2fa': true,
            };
            if (Navigator.canPop(context)) {
              if (Navigator.canPop(context)) {
                Navigator.of(context).pop(); // Close password modal
              }
            }
            _showTwoFactorInput();
          }
          return true; // Consider 2FA prompt as success
        }

        if (data['success'] == true && data['token'] != null) {
          // Save the token and user data to SharedPreferences and AppSettings
          if (!mounted) return false;
          final appSettings = Provider.of<AppSettings>(context, listen: false);

          final userData = data['user'];

          // Determine userType based on login mode
          final userType = appSettings.userType == 'Driver'
              ? 'Driver'
              : AppLocalizations.of(context)?.businessLabel ?? 'Business';

          await appSettings.setUserData(
            userId:
                (userData['id'] ??
                        userData['username'] ??
                        appSettings.userId ??
                        'user')
                    .toString(), // ✅ Convert to String
            name:
              userData['name'] ??
              appSettings.userName ??
              (AppLocalizations.of(context)?.userFallback ?? ''),
            email:
                userData['email'] ??
                appSettings.userEmail ??
                'user@example.com',
            token: data['token'],
            userType: userType, // Pass userType
          );

          print('[SUCCESS] Token and user data saved successfully');
          print('  - Token: ${data['token']}');
          print('  - User: ${userData['name']} (${userData['email']})');
          print('  - UserType: $userType');

          // Navigate directly to home
          await _navigateToHome();
          return true;
        } else {
          return false;
        }
      } else {
        // All login attempts failed - just do nothing, user can try again
        return false;
      }
    } catch (e) {
      // Login error - just do nothing, user can try again
      return false;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _authenticateWithTwoFactor() async {
    if (_twoFactorController.text.isEmpty ||
        _twoFactorController.text.length != 8) {
      if (mounted) {
        TopNotification.show(
          context,
          message: AppLocalizations.of(context)?.pleaseEnterValid8DigitCode ?? 'Please enter a valid 8-digit 2FA code',
          type: NotificationType.error,
        );
      }
      return;
    }

    if (mounted) setState(() => _isLoading = true);

    try {
      final appSettings = Provider.of<AppSettings>(context, listen: false);

      // Build login request with 2FA code
      final requestBody = {
        'email': appSettings.userEmail ?? appSettings.userName ?? '',
        'password': _passwordController.text,
        'twoFACode': _twoFactorController.text,
        'isDelviooMode': appSettings.userType == 'Driver',
      };

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true && data['token'] != null) {
          // Save the token and user data
          final userData = data['user'];
          final userType = appSettings.userType == 'Driver'
              ? 'Driver'
              : AppLocalizations.of(context)?.businessLabel ?? 'Business';

          await appSettings.setUserData(
            userId: userData['id']?.toString() ?? '',
            name:
                userData['name'] ??
                '${userData['first_name']} ${userData['last_name']}',
            email: userData['email'] ?? '',
            token: data['token'],
            userType: userType,
          );

          await _navigateToHome();
        } else {
          if (mounted) {
            TopNotification.show(
              context,
              message: data['message'] ?? AppLocalizations.of(context)?.invalid2faCode ?? 'Invalid 2FA code',
              type: NotificationType.error,
            );
          }
        }
      } else {
        if (mounted) {
          TopNotification.show(
            context,
            message: AppLocalizations.of(context)?.invalid2faCode ?? 'Invalid 2FA code',
            type: NotificationType.error,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        TopNotification.show(
          context,
            message:
              '${AppLocalizations.of(context)?.twoFaVerificationFailed ?? ''}: $e',
          type: NotificationType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _navigateToHome() async {
    if (!mounted) return;

    // Close all modals (password/2FA modal AND auto-login modal)
    Navigator.of(context).popUntil((route) => route.isFirst);

    // Home page is already visible behind, so we're done!
  }

  void _switchAccount() async {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    await appSettings.logout();
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _twoFactorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show a fullscreen loading screen while _checkSilentLogin runs.
    // This avoids the blank/dark window on macOS during the async check.
    // Use the app theme brightness, not the system platform brightness, so the
    // background follows the user's selected light/dark theme.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: const Center(
        child: CultiooLoadingIndicator(size: 36),
      ),
    );
  }
}

// Auto-Login Modal Content Widget (separate from page to avoid context issues)
class _AutoLoginModalContent extends StatefulWidget {
  final AppSettings appSettings;
  final bool isLight;
  final Map<String, dynamic>? userSecuritySettings;
  final VoidCallback onAuthenticated;

  const _AutoLoginModalContent({
    required this.appSettings,
    required this.isLight,
    required this.userSecuritySettings,
    required this.onAuthenticated,
  });

  @override
  State<_AutoLoginModalContent> createState() => _AutoLoginModalContentState();
}

class _AutoLoginModalContentState extends State<_AutoLoginModalContent> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _twoFactorController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Automatically start biometric authentication if enabled
    if (widget.userSecuritySettings?['biometric_enabled'] == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _authenticateWithBiometric();
      });
    }
  }

  @override
  void dispose() {
    // Don't dispose controllers - they might still be used in open modals
    // They will be garbage collected when no longer referenced
    super.dispose();
  }

  Future<void> _navigateToHome() async {
    if (!mounted) return;
    widget.onAuthenticated();

    // Close all open modals until we reach a named route (the home page)
    Navigator.of(context).popUntil((route) {
      // Stop when we reach a route with a name (like /main or /delvioo-main)
      return route.settings.name != null;
    });

    // Home page is now visible with all its navigation!
  }

  Future<void> _authenticateWithBiometric() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final result = await BiometricService.authenticateForLogin();
      if (result) {
        await _navigateToHome();
      }
    } catch (e) {
      if (mounted) {
        TopNotification.show(
          context,
          message: AppLocalizations.of(context)?.biometricAuthFailed ?? 'Biometric authentication failed',
          type: NotificationType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showPasswordInput() {
    if (!mounted) return;

    bool showPassword = false;
    bool hasError = false;

    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: 700,
      backgroundColor:
          widget.isLight ? Colors.white : const Color(0xFF0B0B0D),
      bottomPadding: 20.0,
      child: StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _autoLoginSheetTopChrome(),
              Row(
                children: [
                  Icon(CupertinoIcons.lock, size: 22, color: widget.isLight ? Colors.black : Colors.white),
                  const SizedBox(width: 12),
                  Flexible(child: Text(
                    AppLocalizations.of(context)?.enterPassword ?? 'Enter Password',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                      color: widget.isLight ? Colors.black : Colors.white, letterSpacing: -0.4),
                  )),
                ],
              ),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
              Text(
                AppLocalizations.of(context)?.authenticateWithPassword ?? 'Authenticate with your password',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: (widget.isLight ? Colors.black : Colors.white)
                      .withOpacity(0.5),
                ),
              ),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
              TradeRepublicTextField.password(
                controller: _passwordController,
                hintText: AppLocalizations.of(context)?.password ?? 'Password',
                autofocus: true,
                prefixIcon: const Icon(CupertinoIcons.lock_fill),
                onChanged: (value) {
                  if (hasError) {
                    setModalState(() => hasError = false);
                  }
                },
              ),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
              Row(
                children: [
                  Expanded(
                    child: TradeRepublicButton(
                      label: AppLocalizations.of(context)?.cancel ?? 'Cancel',
                      isSecondary: true,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TradeRepublicButton(
                      label: AppLocalizations.of(context)?.login ?? 'Login',
                      backgroundColor: const Color(0xFF34C759),
                      isLoading: _isLoading,
                      onPressed: _isLoading
                          ? null
                          : () async {
                              final password = _passwordController.text;
                              if (password.isEmpty) {
                                setModalState(() => hasError = true);
                                return;
                              }
                              setModalState(() => hasError = false);
                              final success = await _authenticateWithPassword();
                              if (success &&
                                  mounted &&
                                  Navigator.canPop(context)) {
                                Navigator.of(context).pop();
                              } else if (mounted) {
                                setModalState(() => hasError = true);
                              }
                            },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _authenticateWithPassword() async {
    if (_passwordController.text.isEmpty) {
      return false;
    }

    if (mounted) setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': widget.appSettings.userEmail,
          'password': _passwordController.text,
          'isDelviooMode': widget.appSettings.userType == 'Driver',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true && data['token'] != null) {
          final userData = data['user'];
          final userType = widget.appSettings.userType == 'Driver'
              ? 'Driver'
              : AppLocalizations.of(context)?.businessLabel ?? 'Business';

          await widget.appSettings.setUserData(
            userId: (userData['id'] ?? widget.appSettings.userId ?? 'user')
                .toString(),
            name:
              userData['name'] ??
              widget.appSettings.userName ??
              (AppLocalizations.of(context)?.userFallback ?? ''),
            email:
                userData['email'] ??
                widget.appSettings.userEmail ??
                'user@example.com',
            token: data['token'],
            userType: userType,
          );

          await _navigateToHome();
          return true;
        } else {
          if (mounted) {
            TopNotification.show(
              context,
              message: data['message'] ?? AppLocalizations.of(context)?.incorrectPassword ?? 'Invalid password',
              type: NotificationType.error,
            );
          }
          return false;
        }
      } else if (response.statusCode == 202) {
        // 2FA required
        final data = jsonDecode(response.body);
        if (data['requiresTwoFA'] == true) {
          if (mounted) {
            if (Navigator.canPop(context)) {
              Navigator.of(context).pop(); // Close password modal
            }
            _show2FAInput();
          }
          return true; // Consider 2FA prompt as success
        }
        return false;
      } else {
        if (mounted) {
          String errorMsg = AppLocalizations.of(context)?.incorrectPassword ?? 'Invalid password';
          try {
            final errorData = jsonDecode(response.body);
            errorMsg = errorData['message'] ?? errorMsg;
          } catch (_) {}
          TopNotification.show(
            context,
            message: errorMsg,
            type: NotificationType.error,
          );
        }
        return false;
      }
    } catch (e) {
      if (mounted) {
        TopNotification.show(
          context,
          message: '${AppLocalizations.of(context)?.loginFailed ?? 'Login failed'}: $e',
          type: NotificationType.error,
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _show2FAInput() {
    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: 700,
      backgroundColor:
          widget.isLight ? Colors.white : const Color(0xFF0B0B0D),
      bottomPadding: 20.0,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _autoLoginSheetTopChrome(),
            Row(
              children: [
                Icon(CupertinoIcons.shield, size: 22, color: widget.isLight ? Colors.black : Colors.white),
                const SizedBox(width: 12),
                Flexible(child: Text(
                  AppLocalizations.of(context)?.twoFactorAuthentication ?? 'Two-Factor Authentication',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                    color: widget.isLight ? Colors.black : Colors.white, letterSpacing: -0.4),
                )),
              ],
            ),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
            Text(
              AppLocalizations.of(context)?.pleaseEnterValid8DigitCode ?? 'Please enter your 8-digit 2FA code',
            ),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
            Row(
              children: [
                Expanded(
                    child: TradeRepublicButton(
                      label: AppLocalizations.of(context)?.cancel ?? 'Abbrechen',
                      isSecondary: true,
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: TradeRepublicButton(
                      label: AppLocalizations.of(context)?.verify ?? 'Verify',
                      backgroundColor: const Color(0xFF34C759),
                      isLoading: _isLoading,
                      onPressed: _isLoading
                          ? null
                          : () async {
                              await _verify2FA();
                            },
                    ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _show2FAWithPasswordInput() {
    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: 760,
      backgroundColor:
          widget.isLight ? Colors.white : const Color(0xFF0B0B0D),
      bottomPadding: 20.0,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _autoLoginSheetTopChrome(),
            Row(
              children: [
                Icon(CupertinoIcons.shield, size: 22, color: widget.isLight ? Colors.black : Colors.white),
                const SizedBox(width: 12),
                Flexible(child: Text(
                  '2FA Authentication',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                    color: widget.isLight ? Colors.black : Colors.white, letterSpacing: -0.4),
                )),
              ],
            ),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
            Text(
              AppLocalizations.of(context)?.pleaseEnterValid8DigitCode ?? 'Please enter your 8-digit 2FA code',
            ),
            TradeRepublicTap(
              onTap: () {
                // Make sure keyboard appears
                FocusScope.of(context).requestFocus(FocusNode());
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _twoFactorController,
                  builder: (context, value, child) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(8, (index) {
                        final bool isFilled = value.text.length > index;
                        final bool isActive = value.text.length == index;

                        return Container(
                          margin: EdgeInsets.only(
                            left: index == 0 ? 0 : 3,
                            right: index == 3 ? 8 : 3,
                          ),
                          child: Container(
                            width: 34,
                            height: 52,
                            decoration: BoxDecoration(
                              color: isActive
                                  ? const Color(0xFF007AFF).withOpacity(0.10)
                                  : isFilled
                                  ? (widget.isLight
                                            ? Colors.black
                                            : Colors.white)
                                        .withOpacity(0.08)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                isFilled ? value.text[index] : '',
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w300,
                                  color: widget.isLight
                                      ? Colors.black
                                      : Colors.white,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    );
                  },
                ),
              ),
            ),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
            // Hidden TextField for input
            Opacity(
              opacity: 0.0,
              child: SizedBox(
                height: 48,
                width: 200,
                child: TradeRepublicTextField(
                  controller: _twoFactorController,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  onChanged: (value) {
                    // Only allow numbers
                    final filtered = value.replaceAll(RegExp(r'[^0-9]'), '');
                    if (filtered != value) {
                      _twoFactorController.text = filtered;
                      _twoFactorController.selection =
                          TextSelection.fromPosition(
                            TextPosition(offset: filtered.length),
                          );
                    }
                    // No setState needed - ValueListenableBuilder handles updates
                    if (filtered.length == 8) {
                      // Small delay to show last digit before verifying
                      Future.delayed(const Duration(milliseconds: 150), () {
                        if (mounted) _verify2FAOnly();
                      });
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TradeRepublicButton(
                    label: AppLocalizations.of(context)?.cancel ?? 'Cancel',
                    isSecondary: true,
                    onPressed: () {
                      Navigator.of(context).pop();
                      _twoFactorController.clear();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TradeRepublicButton(
                    label: AppLocalizations.of(context)?.verify ?? 'Verify',
                    backgroundColor: const Color(0xFF34C759),
                    isLoading: _isLoading,
                    onPressed: _isLoading ? null : _verify2FAOnly,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _verify2FAOnly() async {
    if (_twoFactorController.text.isEmpty ||
        _twoFactorController.text.length != 8) {
      if (mounted) {
        TopNotification.show(
          context,
          message: AppLocalizations.of(context)?.pleaseEnterValid8Digit ?? 'Please enter a valid 8-digit code',
          type: NotificationType.error,
        );
      }
      return;
    }

    if (mounted) setState(() => _isLoading = true);

    try {
      // Check if user signed in with Google/Apple (OAuth) - they don't have a password
      final authMethod = widget.appSettings.authMethod;
      final isOAuthUser = authMethod == 'google' || authMethod == 'apple';

      print('🔐 Auto-login 2FA: authMethod=$authMethod, isOAuth=$isOAuthUser');

      // For OAuth users (Google/Apple), we already have a valid token
      // Just verify the 2FA code and proceed
      if (isOAuthUser) {
        print('🔐 OAuth user - using existing token, just verifying 2FA');

        // For OAuth users, we can verify the token is still valid
        // and proceed directly (the token was set during OAuth sign-in)
        final token = widget.appSettings.authToken;

        if (token != null && token.isNotEmpty) {
          // Token exists, 2FA verified (user proved they have the device)
          // Navigate to home directly
          if (mounted) {
            Navigator.of(context).pop(); // Close 2FA modal
            await _navigateToHome();
          }
          return;
        } else {
          // No valid token, need to re-authenticate
          if (mounted) {
            TopNotification.show(
              context,
              message: AppLocalizations.of(context)?.sessionExpiredPleaseLogin ?? 'Session expired. Please login again.',
              type: NotificationType.error,
            );
            Navigator.of(context).popUntil((route) => route.isFirst);
            Navigator.of(context).pushReplacementNamed('/login');
          }
          return;
        }
      }

      // For email/password users in auto-login: verify the static 2FA code
      // via /check-2fa (which now accepts an optional 'code' field).
      // We do NOT need a password here — the stored token is still valid;
      // we just need to confirm the user has their 2FA device.
      print('🔐 Email user - verifying 2FA code via check-2fa (no password needed)');

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/check-2fa'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': widget.appSettings.userEmail ??
              widget.appSettings.userName ?? '',
          'code': _twoFactorController.text,
          'isDelviooMode': widget.appSettings.userType == 'Driver',
        }),
      );

      print('🔐 check-2fa Response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // /check-2fa returns codeVerified: true when the code matches
        if (data['success'] == true && data['codeVerified'] == true) {
          // Code is correct — the existing stored token is still valid,
          // no need to refresh it. Just navigate home.
          if (mounted) {
            Navigator.of(context).pop(); // Close 2FA modal
            await _navigateToHome();
          }
        } else {
          if (mounted) {
            TopNotification.show(
              context,
              message: AppLocalizations.of(context)?.invalid2faCode ?? 'Invalid 2FA code',
              type: NotificationType.error,
            );
          }
        }
      } else {
        try {
          final errorData = jsonDecode(response.body);
          final errorMessage = errorData['message'] ?? AppLocalizations.of(context)?.invalid2faCode ?? 'Invalid 2FA code';
          print('[ERROR] 2FA Error: ${response.statusCode} - $errorMessage');

          if (mounted) {
            TopNotification.show(
              context,
              message: errorMessage,
              type: NotificationType.error,
            );
          }
        } catch (e) {
          print('[ERROR] Failed to parse error response: $e');
          if (mounted) {
            TopNotification.show(
              context,
              message: AppLocalizations.of(context)?.invalid2faCode ?? 'Invalid 2FA code',
              type: NotificationType.error,
            );
          }
        }
      }
    } catch (e) {
      print('[ERROR] 2FA Exception: $e');
      if (mounted) {
        TopNotification.show(
          context,
            message:
              '${AppLocalizations.of(context)?.twoFaVerificationFailed ?? ''}: $e',
          type: NotificationType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verify2FA() async {
    if (_twoFactorController.text.isEmpty ||
        _twoFactorController.text.length != 8) {
      if (mounted) {
        TopNotification.show(
          context,
          message: AppLocalizations.of(context)?.pleaseEnterValid8Digit ?? 'Please enter a valid 8-digit code',
          type: NotificationType.error,
        );
      }
      return;
    }

    if (mounted) setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': widget.appSettings.userEmail,
          'password': _passwordController.text,
          'twoFACode': _twoFactorController.text,
          'isDelviooMode': widget.appSettings.userType == 'Driver',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true && data['token'] != null) {
          final userData = data['user'];
          final userType = widget.appSettings.userType == 'Driver'
              ? 'Driver'
              : AppLocalizations.of(context)?.businessLabel ?? 'Business';

          await widget.appSettings.setUserData(
            userId: (userData['id'] ?? widget.appSettings.userId ?? 'user')
                .toString(),
            name:
              userData['name'] ??
              widget.appSettings.userName ??
              (AppLocalizations.of(context)?.userFallback ?? ''),
            email:
                userData['email'] ??
                widget.appSettings.userEmail ??
                'user@example.com',
            token: data['token'],
            userType: userType,
          );

          if (mounted) {
            Navigator.of(context).pop(); // Close 2FA modal
            await _navigateToHome();
          }
        } else {
          if (mounted) {
            TopNotification.show(
              context,
              message: data['message'] ?? AppLocalizations.of(context)?.invalid2faCode ?? 'Invalid 2FA code',
              type: NotificationType.error,
            );
          }
        }
      } else {
        if (mounted) {
          TopNotification.show(
            context,
            message: AppLocalizations.of(context)?.invalid2faCode ?? 'Invalid 2FA code',
            type: NotificationType.error,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        TopNotification.show(
          context,
            message:
              '${AppLocalizations.of(context)?.twoFaVerificationFailed ?? ''}: $e',
          type: NotificationType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.55,
      child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Modern Handle bar - minimalistic
              _autoLoginSheetTopChrome(),
              // Welcome header
              Row(
                children: [
                  Icon(
                    widget.appSettings.userType == 'Driver'
                        ? CupertinoIcons.car_detailed
                        : CupertinoIcons.briefcase_fill,
                    size: 22,
                    color: widget.isLight ? Colors.black : Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Flexible(child: Text(
                    AppLocalizations.of(context)?.welcomeBack ?? 'Welcome back',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                      color: widget.isLight ? Colors.black : Colors.white, letterSpacing: -0.4),
                  )),
                ],
              ),
              const SizedBox(height: 6),
              // Account type indicator
              Text(
                widget.appSettings.userType == 'Driver'
                    ? AppLocalizations.of(context)?.delviooLabel ?? 'Delvioo'
                    : AppLocalizations.of(context)?.business ?? 'Business',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: widget.appSettings.userType == 'Driver'
                      ? const Color(0xFF34C759)
                      : const Color(0xFF007AFF),
                ),
              ),
              const SizedBox(height: 4),
              // Subtitle - simplified
              if (widget.appSettings.userId != null)
                Text(
                  '@${widget.appSettings.userId!.length > 30 ? widget.appSettings.userId!.substring(0, 30) : widget.appSettings.userId!}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: (widget.isLight ? Colors.black : Colors.white)
                        .withOpacity(0.5),
                  ),
                ),
              const SizedBox(height: 28),
              // Authentication options
              Column(
                children: [
                  // Biometric authentication
                  if (widget.userSecuritySettings?['biometric_enabled'] == 1)
                    _buildAuthOption(
                      icon: CupertinoIcons.hand_raised_fill,
                      title: AppLocalizations.of(context)?.useBiometric ?? 'Use Biometric',
                      subtitle: AppLocalizations.of(context)?.quickAndSecureAccess ?? 'Quick and secure access',
                      onTap: _authenticateWithBiometric,
                    ),
                  // 2FA authentication - only show if 2FA is enabled
                  if (widget.userSecuritySettings?['has_2fa_enabled'] == 1)
                    _buildAuthOption(
                      icon: CupertinoIcons.shield_fill,
                      title: AppLocalizations.of(context)?.twoFactorCode ?? 'Two-Factor Code',
                      subtitle: AppLocalizations.of(context)?.enterYour8Digit2faCode ?? 'Enter your 8-digit 2FA code',
                      onTap: () {
                        // Show 2FA input directly (no password needed for auto-login)
                        TradeRepublicBottomSheet.show(
                          context: context,
                          maxHeight: 700,
                          backgroundColor: widget.isLight
                              ? Colors.white
                              : const Color(0xFF0B0B0D),
                          bottomPadding: 20.0,
                          child: Padding(
                            padding: EdgeInsets.only(
                              bottom: MediaQuery.of(context).viewInsets.bottom,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _autoLoginSheetTopChrome(),
                                Row(
                                  children: [
                                    Icon(CupertinoIcons.shield, size: 22, color: widget.isLight ? Colors.black : Colors.white),
                                    const SizedBox(width: 12),
                                    Flexible(child: Text(
                                      AppLocalizations.of(context)?.twoFactorAuthentication ?? 'Two-Factor Authentication',
                                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                                        color: widget.isLight ? Colors.black : Colors.white, letterSpacing: -0.4),
                                    )),
                                  ],
                                ),
                                SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                                Text(
                                  AppLocalizations.of(context)?.enterYour8Digit2faCode ?? 'Enter your 8-digit 2FA code',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color:
                                        (widget.isLight
                                                ? Colors.black
                                                : Colors.white)
                                            .withOpacity(0.5),
                                  ),
                                ),
                                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
                                TradeRepublicTextField.code(
                                  controller: _twoFactorController,
                                  hintText: '12345678',
                                  maxLength: 8,
                                  autofocus: true,
                                ),
                                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
                                Row(
                                  children: [
                                    Expanded(
                                      child: (Platform.isIOS)
                                          ? TradeRepublicButton(
                                              label: AppLocalizations.of(context)?.cancel ?? 'Cancel',
                                              onPressed: () {
                                                HapticFeedback.lightImpact();
                                                Navigator.of(context).pop();
                                              },
                                            )
                                          : TradeRepublicButton(
                                              label: AppLocalizations.of(context)?.cancel ?? 'Cancel',
                                              isSecondary: true,
                                              onPressed: () {
                                                HapticFeedback.lightImpact();
                                                Navigator.of(context).pop();
                                              },
                                            ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: (Platform.isIOS)
                                          ? TradeRepublicButton(
                                              label: AppLocalizations.of(context)?.verify ?? 'Verify',
                                              onPressed: _isLoading
                                                  ? null
                                                  : () {
                                                      HapticFeedback.lightImpact();
                                                      _verify2FAOnly();
                                                    },
                                            )
                                          : TradeRepublicButton(
                                              label: AppLocalizations.of(context)?.verify ?? 'Verify',
                                              onPressed: _isLoading
                                                  ? null
                                                  : () {
                                                      HapticFeedback.lightImpact();
                                                      _verify2FAOnly();
                                                    },
                                            ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  // Password authentication
                  _buildAuthOption(
                    icon: CupertinoIcons.lock_fill,
                    title: AppLocalizations.of(context)?.usePassword ?? 'Use Password',
                    subtitle: AppLocalizations.of(context)?.enterYourPassword ?? 'Enter your password',
                    onTap: _showPasswordInput,
                  ),
                ],
              ),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
              // Action buttons - Trade Republic Style (text only)
              Row(
                children: [
                  Expanded(
                    child: (Platform.isIOS)
                        ? TradeRepublicButton(
                            label: AppLocalizations.of(context)?.cancel ?? 'Cancel',
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              Navigator.of(
                                context,
                              ).pushReplacementNamed('/login');
                            },
                          )
                        : TradeRepublicButton(
                            label: AppLocalizations.of(context)?.cancel ?? 'Cancel',
                            isSecondary: true,
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              Navigator.of(
                                context,
                              ).pushReplacementNamed('/login');
                            },
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: (Platform.isIOS)
                        ? TradeRepublicButton(
                            label: AppLocalizations.of(context)?.switchAccount ?? 'Switch Account',
                            onPressed: () async {
                              HapticFeedback.lightImpact();
                              final appSettings = widget.appSettings;
                              await appSettings.logout();
                              if (mounted) {
                                Navigator.of(
                                  context,
                                ).pushReplacementNamed('/login');
                              }
                            },
                          )
                        : TradeRepublicButton(
                            label: AppLocalizations.of(context)?.switchAccount ?? 'Switch Account',
                            onPressed: () async {
                              HapticFeedback.lightImpact();
                              final appSettings = widget.appSettings;
                              await appSettings.logout();
                              if (mounted) {
                                Navigator.of(
                                  context,
                                ).pushReplacementNamed('/login');
                              }
                            },
                          ),
                  ),
                ],
              ),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
            ],
          ),
        ),
    );
  }

  Widget _buildAuthOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: TradeRepublicTap(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
          splashColor: (widget.isLight ? Colors.black : Colors.white)
              .withOpacity(0.05),
          highlightColor: (widget.isLight ? Colors.black : Colors.white)
              .withOpacity(0.02),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: widget.isLight
                  ? Colors.transparent
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: widget.isLight
                      ? Colors.black.withOpacity(0.6)
                      : Colors.white.withOpacity(0.6),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w500,
                      color: widget.isLight ? Colors.black : Colors.white,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 14,
                  color: (widget.isLight ? Colors.black : Colors.white)
                      .withOpacity(0.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Success Animation Widget
class _SuccessAnimationWidget extends StatefulWidget {
  final bool isLight;

  const _SuccessAnimationWidget({required this.isLight});

  @override
  State<_SuccessAnimationWidget> createState() =>
      _SuccessAnimationWidgetState();
}

class _SuccessAnimationWidgetState extends State<_SuccessAnimationWidget>
    with TickerProviderStateMixin {
  late AnimationController _checkController;
  late AnimationController _scaleController;
  late AnimationController _confettiController;
  late AnimationController _fadeController;
  late AnimationController _blurController;

  late Animation<double> _checkAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _blurAnimation;

  final List<_ConfettiParticle> _confettiParticles = [];

  @override
  void initState() {
    super.initState();

    // Apple-style smooth scale animation
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Apple uses custom curves similar to easeInOut but smoother
    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeInOutCubic, // Apple-style smooth curve
    );

    // Check mark animation - smooth and fluid
    _checkController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );

    _checkAnimation = CurvedAnimation(
      parent: _checkController,
      curve: Curves.easeOutCubic, // Smooth, no bounce
    );

    // Fade animation for text
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );

    // Blur animation for background
    _blurController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _blurAnimation = CurvedAnimation(
      parent: _blurController,
      curve: Curves.easeOut,
    );

    // Confetti animation - longer and smoother
    _confettiController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );

    // Generate confetti particles - Apple style (fewer, more elegant)
    final random = math.Random();
    for (int i = 0; i < 30; i++) {
      // Fewer particles for cleaner look
      _confettiParticles.add(
        _ConfettiParticle(
          color: _getRandomColor(random),
          startX: 0.5 + (random.nextDouble() - 0.5) * 0.6, // More centered
          startY: -0.05,
          endX: 0.5 + (random.nextDouble() - 0.5) * 1.5, // Wider spread
          endY: 1.1 + random.nextDouble() * 0.2,
          rotation: random.nextDouble() * 2 * math.pi,
          size: random.nextDouble() * 6 + 3, // Smaller, more subtle
        ),
      );
    }

    // Start animations
    _startAnimations();
  }

  Color _getRandomColor(math.Random random) {
    // Apple-style colors - more subtle and elegant
    final colors = [
      const Color(0xFF34C759), // Apple Green
      const Color(0xFF007AFF), // Apple Blue
      const Color(0xFFAF52DE), // Apple Purple
      const Color(0xFFFF9500), // Apple Orange
      const Color(0xFFFF2D55), // Apple Pink
      const Color(0xFF5AC8FA), // Apple Teal
      const Color(0xFFFFCC00), // Apple Yellow
    ];
    return colors[random.nextInt(colors.length)];
  }

  Future<void> _startAnimations() async {
    // Apple-style sequential animations with smooth timing

    // 1. Start blur background
    _blurController.forward();

    // 2. Scale in circle (slightly delayed)
    await Future.delayed(const Duration(milliseconds: 100));
    _scaleController.forward();

    // 3. Draw checkmark (smooth, no delay)
    await Future.delayed(const Duration(milliseconds: 300));
    _checkController.forward();

    // 4. Fade in text
    await Future.delayed(const Duration(milliseconds: 200));
    _fadeController.forward();

    // 5. Start confetti (subtle and elegant)
    _confettiController.forward();

    // Wait for animations to complete (Apple typically holds success state briefly)
    await Future.delayed(const Duration(milliseconds: 1800));

    // Close with fade out
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _checkController.dispose();
    _scaleController.dispose();
    _confettiController.dispose();
    _fadeController.dispose();
    _blurController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _blurAnimation,
      builder: (context, child) {
        return Material(
          color: Colors.transparent,
          child: Container(
            // Apple-style background - pure black in dark mode
            decoration: BoxDecoration(
              color: widget.isLight
                  ? Colors.white.withOpacity(0.95 * _blurAnimation.value)
                  : Colors.black.withOpacity(0.95 * _blurAnimation.value),
            ),
            child: Center(
              child: Stack(
                children: [
                  // Animated glow rings around success (Apple-style)
                  Center(
                    child: AnimatedBuilder(
                      animation: _scaleAnimation,
                      builder: (context, child) {
                        return Container(
                          width: 100 + (60 * _scaleAnimation.value),
                          height: 100 + (60 * _scaleAnimation.value),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF34C759).withOpacity(
                              0.08 *
                                  _scaleAnimation.value *
                                  (1 - _scaleAnimation.value),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // Second glow ring (delayed)
                  Center(
                    child: AnimatedBuilder(
                      animation: _checkAnimation,
                      builder: (context, child) {
                        return Container(
                          width: 100 + (100 * _checkAnimation.value),
                          height: 100 + (100 * _checkAnimation.value),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF34C759).withOpacity(
                              0.06 *
                                  _checkAnimation.value *
                                  (1 - _checkAnimation.value),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // Confetti particles (subtle, in background)
                  AnimatedBuilder(
                    animation: _confettiController,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: _ConfettiPainter(
                          particles: _confettiParticles,
                          progress: _confettiController.value,
                        ),
                        size: Size(
                          MediaQuery.of(context).size.width,
                          MediaQuery.of(context).size.height,
                        ),
                      );
                    },
                  ),

                  // Success checkmark with Apple-style shadow
                  Center(
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: const Color(0xFF34C759), // Apple Green
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF34C759).withOpacity(0.5),
                              blurRadius: 40,
                              spreadRadius: 0,
                              offset: const Offset(0, 10),
                            ),
                            BoxShadow(
                              color: const Color(0xFF34C759).withOpacity(0.3),
                              blurRadius: 80,
                              spreadRadius: 0,
                              offset: const Offset(0, 25),
                            ),
                            // Inner glow effect
                            BoxShadow(
                              color: const Color(0xFF34C759).withOpacity(0.8),
                              blurRadius: 20,
                              spreadRadius: -5,
                              offset: Offset.zero,
                            ),
                          ],
                        ),
                        child: AnimatedBuilder(
                          animation: _checkAnimation,
                          builder: (context, child) {
                            return CustomPaint(
                              painter: _CheckMarkPainter(
                                progress: _checkAnimation.value,
                                color: Colors.white,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),

                  // Subtle pulse effect on circle
                  Center(
                    child: AnimatedBuilder(
                      animation: _fadeAnimation,
                      builder: (context, child) {
                        final pulseScale =
                            1.0 +
                            (math.sin(_fadeAnimation.value * math.pi * 2) *
                                0.05);
                        return Transform.scale(
                          scale: pulseScale,
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(
                                0.08 * _fadeAnimation.value,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // Welcome text with smooth fade and slide up
                  Positioned(
                    bottom: MediaQuery.of(context).size.height * 0.35,
                    left: 0,
                    right: 0,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: SlideTransition(
                        position:
                            Tween<Offset>(
                              begin: const Offset(0, 0.5),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: _fadeController,
                                curve: Curves.easeOutCubic,
                              ),
                            ),
                        child: Column(
                          children: [
                            Text(
                              AppLocalizations.of(context)?.welcomeBack ?? 'Welcome Back',
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w600,
                                color: widget.isLight
                                    ? Colors.black
                                    : Colors.white,
                                letterSpacing: -0.5,
                                shadows: widget.isLight
                                    ? null
                                    : [
                                        Shadow(
                                          color: Colors.black.withOpacity(0.3),
                                          offset: const Offset(0, 2),
                                          blurRadius: 4,
                                        ),
                                      ],
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF34C759).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                              ),
                              child: Text(
                                '✓ Login successful',
                                style: TextStyle(
                                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF34C759),
                                  letterSpacing: -0.2,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Shimmer effect (Apple-style light reflection)
                  AnimatedBuilder(
                    animation: _checkAnimation,
                    builder: (context, child) {
                      if (_checkAnimation.value < 0.3) {
                        return const SizedBox.shrink();
                      }

                      return Center(
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white.withOpacity(
                                  0.4 * (_checkAnimation.value - 0.3),
                                ),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.5],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// Confetti Particle Data
class _ConfettiParticle {
  final Color color;
  final double startX;
  final double startY;
  final double endX;
  final double endY;
  final double rotation;
  final double size;

  _ConfettiParticle({
    required this.color,
    required this.startX,
    required this.startY,
    required this.endX,
    required this.endY,
    required this.rotation,
    required this.size,
  });
}

// Confetti Painter
class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final double progress;

  _ConfettiPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    for (var particle in particles) {
      // Apple-style fade: faster fade out for cleaner look
      final fadeProgress = progress < 0.7
          ? 1.0
          : (1.0 - (progress - 0.7) / 0.3);

      final paint = Paint()
        ..color = particle.color
            .withOpacity(0.8 * fadeProgress) // More subtle opacity
        ..style = PaintingStyle.fill;

      // Calculate position with easing
      final easedProgress =
          progress * progress * (3 - 2 * progress); // Smoothstep
      final x =
          size.width *
          (particle.startX + (particle.endX - particle.startX) * easedProgress);
      final y =
          size.height *
          (particle.startY + (particle.endY - particle.startY) * easedProgress);

      // Save canvas state
      canvas.save();

      // Move to particle position
      canvas.translate(x, y);

      // Slower rotation for more elegant effect
      canvas.rotate(particle.rotation * progress * 0.5);

      // Draw rounded rectangle (confetti piece) - Apple uses rounded shapes
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: particle.size,
            height: particle.size * 1.8, // Less elongated
          ),
          Radius.circular(particle.size * 0.3), // More rounded
        ),
        paint,
      );

      // Restore canvas state
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) => true;
}

// Check Mark Painter - Apple Style
class _CheckMarkPainter extends CustomPainter {
  final double progress;
  final Color color;

  _CheckMarkPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    // Apple-style checkmark - thicker and more prominent
    final paint = Paint()
      ..color = color
      ..strokeWidth =
          5.0 // Apple uses thinner, cleaner lines
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round; // Smooth joins

    final path = Path();

    // Apple-style checkmark proportions (more balanced)
    final p1 = Offset(size.width * 0.27, size.height * 0.52);
    final p2 = Offset(size.width * 0.43, size.height * 0.67);
    final p3 = Offset(size.width * 0.73, size.height * 0.33);

    path.moveTo(p1.dx, p1.dy);

    // Smooth, continuous animation
    if (progress < 0.4) {
      // Draw first part of check (down) - slower
      final t = progress / 0.4;
      // Use cubic interpolation for smoother animation
      final smoothT = t * t * (3 - 2 * t); // Smoothstep
      path.lineTo(
        p1.dx + (p2.dx - p1.dx) * smoothT,
        p1.dy + (p2.dy - p1.dy) * smoothT,
      );
    } else {
      // Draw first part completely
      path.lineTo(p2.dx, p2.dy);

      // Draw second part of check (up) - faster
      final t = (progress - 0.4) / 0.6;
      // Use cubic interpolation for smoother animation
      final smoothT = t * t * (3 - 2 * t); // Smoothstep
      path.lineTo(
        p2.dx + (p3.dx - p2.dx) * smoothT,
        p2.dy + (p3.dy - p2.dy) * smoothT,
      );
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckMarkPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
