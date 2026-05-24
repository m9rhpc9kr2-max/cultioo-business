import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../shared/services/app_settings.dart';
import '../../../shared/services/app_localizations.dart';
import '../../../shared/widgets/top_notification.dart';
import '../../../shared/widgets/trade_republic_button.dart';
import '../../../shared/widgets/trade_republic_text_field.dart';
import '../../../config/api_config.dart';
import '../../../shared/widgets/cultioo_spinner.dart';

class DriverStep10Success extends StatefulWidget {
  final Map<String, dynamic> registrationData;

  const DriverStep10Success({super.key, required this.registrationData});

  @override
  State<DriverStep10Success> createState() => _DriverStep10SuccessState();
}

class _DriverStep10SuccessState extends State<DriverStep10Success>
    with TickerProviderStateMixin {
  late AnimationController _checkController;
  late AnimationController _scaleController;
  late AnimationController _confettiController;
  late Animation<double> _checkAnimation;
  late Animation<double> _scaleAnimation;
  bool _isResending = false;
  bool _isVerifying = false;
  final List<TextEditingController> _codeControllers =
      List.generate(8, (_) => TextEditingController());
  final List<FocusNode> _codeFocusNodes =
      List.generate(8, (_) => FocusNode());

  @override
  void initState() {
    super.initState();

    // Check mark animation
    _checkController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _checkAnimation = CurvedAnimation(
      parent: _checkController,
      curve: Curves.easeInOut,
    );

    // Scale animation for the circle
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );

    // Confetti animation
    _confettiController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    // Start animations in sequence
    Future.delayed(const Duration(milliseconds: 300), () {
      _scaleController.forward();
    });

    Future.delayed(const Duration(milliseconds: 500), () {
      _checkController.forward();
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      _confettiController.forward();
    });
    _setupCodeInput();
  }

  @override
  void dispose() {
    _checkController.dispose();
    _scaleController.dispose();
    _confettiController.dispose();
    for (final c in _codeControllers) {
      c.dispose();
    }
    for (final n in _codeFocusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _setupCodeInput() {
    for (int i = 0; i < 8; i++) {
      _codeFocusNodes[i].addListener(() {
        if (mounted) setState(() {});
      });
      _codeFocusNodes[i].onKeyEvent = (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.backspace &&
            _codeControllers[i].text.isEmpty &&
            i > 0) {
          _codeControllers[i - 1].clear();
          _codeFocusNodes[i - 1].requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      };
    }
  }

  Future<void> _resendVerificationEmail() async {
    setState(() {
      _isResending = true;
    });

    try {
      HapticFeedback.lightImpact();

      final String baseUrl = ApiConfig.baseUrl;
      final String apiEndpoint =
          '$baseUrl/api/driver-registration/resend-verification';
      final String email = widget.registrationData['email'] ?? '';

      print('DEBUG: Resending verification code to: $email');

      final response = await http
          .post(
            Uri.parse(apiEndpoint),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode({'email': email}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          if (mounted) {
            TopNotification.success(
              context,
              AppLocalizations.of(context)?.verificationCodeSent ?? 'Verification code sent! Please check your inbox.',
            );
          }
        } else {
          throw Exception(data['message'] ?? AppLocalizations.of(context)?.failedToResendCode ?? 'Failed to resend code');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('DEBUG: Error resending code: $e');
      if (mounted) {
        // Stay on page, just show error
        String errorMessage = AppLocalizations.of(context)?.failedToResendCodeTryAgain ?? 'Failed to resend code. Please try again.';

        if (e.toString().contains('500')) {
          errorMessage = AppLocalizations.of(context)?.serverErrorContactSupport ?? 'Server error. Please try again or contact support.';
        } else if (e.toString().contains('TimeoutException')) {
          errorMessage = AppLocalizations.of(context)?.connectionTimeoutCheckInternet ?? 'Connection timeout. Please check your internet.';
        }

        TopNotification.error(context, errorMessage);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
  }

  Future<void> _verifyCode() async {
    final String code = _codeControllers.map((c) => c.text).join();

    if (code.length != 8) {
      TopNotification.error(context, AppLocalizations.of(context)?.pleaseEnterThe8DigitCode ?? 'Please enter the 8-digit code');
      return;
    }

    setState(() {
      _isVerifying = true;
    });

    try {
      HapticFeedback.lightImpact();

      final String baseUrl = ApiConfig.baseUrl;
      final String apiEndpoint = '$baseUrl/api/driver-registration/verify-code';
      final String email = widget.registrationData['email'] ?? '';

      print('DEBUG: Verifying code for: $email');

      final response = await http
          .post(
            Uri.parse(apiEndpoint),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode({'email': email, 'code': code}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          if (mounted) {
            HapticFeedback.mediumImpact();
            TopNotification.success(
              context,
              AppLocalizations.of(context)?.emailVerifiedLoggingIn ?? 'Email verified successfully! Logging you in...',
            );

            // Perform automatic login after successful verification
            await _performAutomaticLogin();
          }
        } else {
          throw Exception(data['message'] ?? AppLocalizations.of(context)?.invalidVerificationCode ?? 'Invalid verification code');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('DEBUG: Error verifying code: $e');
      if (mounted) {
        // Extract error message for better user feedback
        String errorMessage = AppLocalizations.of(context)?.verificationFailed ?? 'Verification failed. Please try again.';

        if (e.toString().contains('Invalid')) {
          errorMessage = AppLocalizations.of(context)?.invalidCodeCheckAndTryAgain ?? 'Invalid code. Please check and try again.';
        } else if (e.toString().contains('500')) {
          errorMessage = AppLocalizations.of(context)?.serverErrorContactSupport ?? 'Server error. Please try again or contact support.';
        } else if (e.toString().contains('TimeoutException')) {
          errorMessage =
              AppLocalizations.of(context)?.connectionTimeoutTryAgain ?? 'Connection timeout. Please check your internet and try again.';
        }

        TopNotification.error(context, errorMessage);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isVerifying = false;
        });
      }
    }
  }

  // Perform automatic login after email verification
  Future<void> _performAutomaticLogin() async {
    try {
      // Get username and password from registration data
      final String username = widget.registrationData['username'] ?? '';
      final String password = widget.registrationData['password'] ?? '';
      final String email = widget.registrationData['email'] ?? '';

      if (username.isEmpty || password.isEmpty) {
        print('❌ Missing login credentials in registration data');
        throw Exception('Login credentials not found');
      }

      print('🔗 Attempting automatic login for: $username');

      final String baseUrl = ApiConfig.baseUrl;
      final String loginEndpoint = '$baseUrl/api/auth/login';

      final response = await http
          .post(
            Uri.parse(loginEndpoint),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode({
              'email': username, // Use username for login
              'password': password, // Use actual password from registration
              'isDelviooMode': true, // Important: Use Delvioo mode
            }),
          )
          .timeout(const Duration(seconds: 30));

      print('📤 Login response status: ${response.statusCode}');
      print('📤 Login response body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> loginData = json.decode(response.body);

        if (loginData['success'] == true && loginData['token'] != null) {
          // Save login tokens and user data
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token', loginData['token']);
          await prefs.setString(
            'refresh_token',
            loginData['refreshToken'] ?? '',
          );
          await prefs.setString('user_data', json.encode(loginData['user']));
          await prefs.setBool('is_delvioo_mode', true);

          // Set user data in AppSettings Provider
          final AppSettings appSettings = Provider.of<AppSettings>(
            context,
            listen: false,
          );
          await appSettings.setIsLoggedIn(true);

          if (loginData['user'] != null) {
            await appSettings.setUserData(
              userId: loginData['user']['id']?.toString() ?? '',
              name: loginData['user']['name'] ?? '',
              email: loginData['user']['email'] ?? '',
              token: loginData['token'] ?? '',
              userType: 'Driver', // ✅ Set as Driver for Delvioo mode
              authMethod: 'email',
            );
          }

          print('✅ Automatic login successful! Navigating to Delvioo app...');
          print('✅ UserType set to: Driver');

          if (mounted) {
            TopNotification.success(
              context,
              '✅ Login successful! Welcome to Delvioo!',
            );

            // Wait to ensure Provider has propagated the changes
            await Future.delayed(const Duration(milliseconds: 100));

            // Navigate to Delvioo main app (not business main)
            if (mounted) {
              Navigator.of(
                context,
              ).pushNamedAndRemoveUntil('/delvioo-main', (route) => false);
            }
          }
        } else {
          throw Exception(loginData['message'] ?? 'Login failed');
        }
      } else {
        throw Exception('Login server error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Automatic login failed: $e');
      if (mounted) {
        // Show error but stay on verification page - don't navigate away
        TopNotification.error(
          context,
          'Login failed. Please use "Return to Login" button to login manually.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings appSettings = Provider.of<AppSettings>(context);
    final bool isLight = appSettings.isLightMode(context);
    final String email = widget.registrationData['email'] ?? 'your email';

    return Scaffold(
      backgroundColor: isLight ? Colors.white : Colors.black,
      body: Stack(
        children: [
          // Confetti background
          AnimatedBuilder(
            animation: _confettiController,
            builder: (context, child) {
              return CustomPaint(
                painter: ConfettiPainter(
                  animation: _confettiController,
                  isLight: isLight,
                ),
                size: Size.infinite,
              );
            },
          ),

          // Main content
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: (Platform.isMacOS || Platform.isWindows || Platform.isLinux) ? 600 : double.infinity),
                child: SingleChildScrollView(
                primary: false,
                padding: EdgeInsets.fromLTRB(
                  24,
                  MediaQuery.of(context).padding.top + 24,
                  24,
                  MediaQuery.of(context).padding.bottom + 40,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 16),

                    // Animated success icon
                    ScaleTransition(
                      scale: _scaleAnimation,
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: AnimatedBuilder(
                          animation: _checkAnimation,
                          builder: (context, child) {
                            return CustomPaint(
                              painter: CheckMarkPainter(
                                progress: _checkAnimation.value,
                                color: Colors.white,
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Success title
                    Text(
                      'Registration Submitted!',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white,
                        letterSpacing: -0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 16),

                    // Success subtitle
                    Text(
                      '🎉 Congratulations!',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 40),

                    // Email verification card
                    Container(
                      decoration: BoxDecoration(
                        color: isLight ? Colors.white : Colors.black,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          // Email icon
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              CupertinoIcons.mail,
                              size: 30,
                              color: Colors.blue,
                            ),
                          ),

                          const SizedBox(height: 20),

                          Text(
                            AppLocalizations.of(context)?.verifyYourEmail ?? 'Verify Your Email',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: isLight ? Colors.black : Colors.white,
                            ),
                          ),

                          const SizedBox(height: 12),

                          Text(
                            'We\'ve sent an 8-digit code to:',
                            style: TextStyle(
                              fontSize: 15,
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.6),
                            ),
                            textAlign: TextAlign.center,
                          ),

                          const SizedBox(height: 8),

                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.05),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              email,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.blue,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),

                          const SizedBox(height: 24),

                          Text(
                            AppLocalizations.of(context)?.enterVerificationCode ?? 'Enter Verification Code',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: isLight ? Colors.black : Colors.white,
                            ),
                          ),

                          const SizedBox(height: 16),

                          // OTP boxes — 4 + dash + 4
                          Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: List.generate(4, (i) => Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.only(right: i < 3 ? 6 : 0),
                                      child: _buildOtpBox(i, isLight),
                                    ),
                                  )),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  '–',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w300,
                                    color: (isLight ? Colors.black : Colors.white).withOpacity(0.25),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Row(
                                  children: List.generate(4, (i) => Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.only(right: i < 3 ? 6 : 0),
                                      child: _buildOtpBox(i + 4, isLight),
                                    ),
                                  )),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          // Verify button
                          _isVerifying
                              ? Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CultiooLoadingIndicator(size: 20),
                                  ),
                                )
                              : TradeRepublicButton(
                                  label: AppLocalizations.of(context)?.verifyEmail ?? 'Verify Email',
                                  onPressed: _verifyCode,
                                ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Info cards
                    _buildInfoCard(
                      icon: CupertinoIcons.time,
                      title: AppLocalizations.of(context)?.activationTime ?? 'Activation Time',
                      description:
                          AppLocalizations.of(context)?.accountActivatedAfterVerification ?? 'Your account will be activated immediately after email verification',
                      isLight: isLight,
                    ),

                    const SizedBox(height: 16),

                    _buildInfoCard(
                      icon: CupertinoIcons.mail,
                      title: AppLocalizations.of(context)?.didntReceiveCode ?? 'Didn\'t Receive Code?',
                      description:
                          AppLocalizations.of(context)?.checkSpamOrResend ?? 'Check your spam folder or click below to resend',
                      isLight: isLight,
                    ),

                    const SizedBox(height: 16),

                    // Resend Code Button
                    _isResending
                        ? Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CultiooLoadingIndicator(size: 20),
                            ),
                          )
                        : TradeRepublicButton(
                            label: AppLocalizations.of(context)?.resendVerificationCode ?? 'Resend Verification Code',
                            icon: Icon(CupertinoIcons.refresh, size: 18),
                            isSecondary: true,
                            onPressed: _resendVerificationEmail,
                          ),

                    const SizedBox(height: 24),

                    // Return to login button
                    TradeRepublicButton(
                            label: AppLocalizations.of(context)?.returnToLogin ?? 'Return to Login',
                            onPressed: () {
                              Navigator.of(context).popUntil((route) => route.isFirst);
                            },
                          ),

                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpBox(int index, bool isLight) {
    final bool isFocused = _codeFocusNodes[index].hasFocus;
    final bool isFilled = _codeControllers[index].text.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 56,
      decoration: BoxDecoration(
        color: isFilled
            ? (isLight ? Colors.black : Colors.white).withOpacity(0.08)
            : (isLight ? Colors.black : Colors.white).withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isFocused
              ? (isLight ? Colors.black : Colors.white)
              : (isLight ? Colors.black : Colors.white).withOpacity(0.12),
          width: isFocused ? 1.5 : 1.0,
        ),
      ),
      child: TradeRepublicTextField(
        controller: _codeControllers[index],
        focusNode: _codeFocusNodes[index],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        counterText: '',
        filled: false,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: isLight ? Colors.black : Colors.white,
          fontFamily: 'Poppins',
        ),
        onChanged: (value) {
          if (value.isNotEmpty && index < 7) {
            _codeFocusNodes[index + 1].requestFocus();
          } else if (value.isNotEmpty && index == 7) {
            _codeFocusNodes[index].unfocus();
            Future.microtask(_verifyCode);
          }
          setState(() {});
        },
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String description,
    required bool isLight,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isLight
            ? Colors.black.withOpacity(0.03)
            : Colors.black.withOpacity(0.24),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isLight ? Colors.white : Colors.black,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              icon,
              size: 24,
              color: isLight ? Colors.black : Colors.white,
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
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isLight ? Colors.black : Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.6,
                    ),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Check mark painter
class CheckMarkPainter extends CustomPainter {
  final double progress;
  final Color color;

  CheckMarkPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    final path = Path();

    // Check mark path
    final p1 = Offset(size.width * 0.25, size.height * 0.5);
    final p2 = Offset(size.width * 0.45, size.height * 0.7);
    final p3 = Offset(size.width * 0.75, size.height * 0.3);

    if (progress < 0.5) {
      // First part of check
      final t = progress * 2;
      path.moveTo(p1.dx, p1.dy);
      path.lineTo(p1.dx + (p2.dx - p1.dx) * t, p1.dy + (p2.dy - p1.dy) * t);
    } else {
      // Complete first part
      path.moveTo(p1.dx, p1.dy);
      path.lineTo(p2.dx, p2.dy);

      // Second part of check
      final t = (progress - 0.5) * 2;
      path.lineTo(p2.dx + (p3.dx - p2.dx) * t, p2.dy + (p3.dy - p2.dy) * t);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CheckMarkPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

// Confetti painter
class ConfettiPainter extends CustomPainter {
  final Animation<double> animation;
  final bool isLight;

  ConfettiPainter({required this.animation, required this.isLight});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    final random = math.Random(42); // Fixed seed for consistent animation

    for (int i = 0; i < 50; i++) {
      final x = random.nextDouble() * size.width;
      final startY = -50.0;
      final endY = size.height + 100;
      final y = startY + (endY - startY) * animation.value;

      final hue = random.nextDouble() * 360;
      paint.color = HSVColor.fromAHSV(
        0.8,
        hue,
        0.7,
        isLight ? 0.8 : 0.9,
      ).toColor();

      final rotation =
          animation.value * math.pi * 4 + random.nextDouble() * math.pi;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);

      // Draw confetti piece
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 8, height: 12),
          const Radius.circular(2),
        ),
        paint,
      );

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(ConfettiPainter oldDelegate) {
    return animation.value != oldDelegate.animation.value;
  }
}
