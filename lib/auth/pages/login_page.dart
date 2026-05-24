import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../shared/services/app_settings.dart';
import '../../shared/services/api_service.dart';
import '../../shared/widgets/top_notification.dart';
import '../../shared/widgets/trade_republic_button.dart';
import '../../shared/widgets/trade_republic_text_field.dart';
import '../../shared/widgets/trade_republic_slider.dart';
import '../../shared/widgets/drag_handle.dart';
import '../../shared/widgets/trade_republic_bottom_sheet.dart';
import '../../config/api_config.dart';
import '../../shared/services/app_localizations.dart';
import '../../shared/widgets/trade_republic_tap.dart';
import '../../app_router.dart';
import '../../modules/delvioo/pages/delvioo_main_page.dart';
import 'package:cultioo_business/shared/widgets/desktop_app_wrapper.dart';
import 'package:cultioo_business/shared/widgets/desktop_optimized_widgets.dart';

/// Web client ID (must match backend `GOOGLE_CLIENT_ID`) so ID tokens verify on the server.
// Web/Server client ID for backend verification (must match backend GOOGLE_CLIENT_ID)
// Created in Google Cloud Console: https://console.cloud.google.com/apis/credentials?project=cultioo
// NOTE: This should be set via environment variable or backend configuration
const String _kGoogleOAuthServerClientId =
    'GOOGLE_OAUTH_CLIENT_ID_PLACEHOLDER';


class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final bool _obscurePassword = true;
  bool _isLoading = false;

  // Cache Platform checks
  late final bool _isIOS = Platform.isIOS;
  late final bool _isMacOS = Platform.isMacOS;
  late final bool _isAndroid = Platform.isAndroid;

  // Tab Bar Index (0 = Business, 1 = Delvioo)
  int _tabIndex = 0;
  bool get _isDelviooMode => _tabIndex == 1;

  void _navigateToHome({bool delvioo = false}) {
    if (!mounted) return;
    final target = delvioo
        ? const DelviooMainPage()
        : const AppRouter();
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => target,
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 320),
        transitionsBuilder: (_, animation, __, child) {
          final slide = Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOutCubic,
          ));
          return SlideTransition(position: slide, child: child);
        },
      ),
      (route) => false,
    );
  }

  // Account type selection screen
  bool _hasSelectedMode = false;

  // Business Upgrade - Store verified email
  String? _verifiedEmail;
  String? _businessUpgradeVerificationToken;

  // Business Profile Picture
  File? _selectedBusinessImage;

  // Business Upgrade Form Controllers
  final _businessNameController = TextEditingController();
  final _businessEmailController = TextEditingController();
  final _businessPhoneController = TextEditingController();
  final _businessWebsiteController = TextEditingController();
  final _businessDescriptionController = TextEditingController();
  final _taxNumberController = TextEditingController();
  final _vatNumberController = TextEditingController();
  final _streetController = TextEditingController();
  final _houseNumberController = TextEditingController();
  final _stateController = TextEditingController();
  final _cityController = TextEditingController();
  final _zipCodeController = TextEditingController();
  final _emailVerificationController = TextEditingController();
  String _selectedSize = '1-10 employees';
  String _selectedCountry = 'United States';

  // Helper to convert country name to emoji flag
  String _countryToFlag(String country) {
    const map = {
      'United States': '🇺🇸',
      'Canada': '🇨🇦',
      'Mexico': '🇲🇽',
      'Germany': '🇩🇪',
      'Austria': '🇦🇹',
      'France': '🇫🇷',
      'Italy': '🇮🇹',
      'Spain': '🇪🇸',
      'Netherlands': '🇳🇱',
      'Belgium': '🇧🇪',
      'Poland': '🇵🇱',
      'Russia': '🇷🇺',
    };
    return map[country] ?? '🏳️';
  }

  // Animation Controllers
  late AnimationController _slideController;
  late AnimationController _fadeController;
  late AnimationController _switchController;
  AnimationController? _modeTransitionControllerRaw;
  AnimationController get _modeTransitionController {
    _modeTransitionControllerRaw ??= AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    return _modeTransitionControllerRaw!;
  }

  // Animations
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // Desktop should always use Business login only.
    if (_isMacOS || Platform.isWindows || Platform.isLinux) {
      _tabIndex = 0;
      _hasSelectedMode = true;
    }

    // Initialize animation controllers with faster durations
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    _switchController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    // Initialize animations with faster, simpler animations
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeIn));

    _scaleAnimation = Tween<double>(
      begin: 0.95,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    // Start animations
    _startAnimations();

    // Check for navigation arguments (from driver registration completion)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final arguments =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (arguments != null) {
        // Enable Delvioo mode if coming from driver registration
        if (arguments['showDelviooOption'] == true &&
            !(_isMacOS || Platform.isWindows || Platform.isLinux)) {
          setState(() {
            _tabIndex = 1; // Set to Delvioo mode
            _hasSelectedMode = true; // Skip selection screen
          });
        }

        // Show success message if registration was completed
        if (arguments['registrationSuccess'] == true) {
          final message = arguments['message'] as String?;
          if (message != null) {
            _showSuccessDialog(message);
          }
        }
      }
    });
  }

  void _startAnimations() async {
    // Start animations immediately without delay
    _slideController.forward();
    _fadeController.forward();
  }

  @override
  void deactivate() {
    super.deactivate();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _fadeController.dispose();
    _switchController.dispose();
    _modeTransitionControllerRaw?.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _businessNameController.dispose();
    _businessEmailController.dispose();
    _businessPhoneController.dispose();
    _businessWebsiteController.dispose();
    _businessDescriptionController.dispose();
    _taxNumberController.dispose();
    _vatNumberController.dispose();
    _streetController.dispose();
    _houseNumberController.dispose();
    _stateController.dispose();
    _cityController.dispose();
    _zipCodeController.dispose();
    _emailVerificationController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      print('⚠️ Please fill in all fields');
      return;
    }
    
    // 🌐 CRITICAL: Verify backend is reachable before attempting login
    print('🔍 Pre-login network check...');
    print('🌐 Current baseUrl: ${ApiConfig.baseUrl}');

    // Basic validation - check if it's a reasonable input.
    // Defensive lowercasing in case the value was pasted/auto-filled before
    // the lowercase input formatter had a chance to run.
    final input = _emailController.text.trim().toLowerCase();
    _emailController.value = TextEditingValue(
      text: input,
      selection: TextSelection.collapsed(offset: input.length),
    );
    if (input.length < 3) {
      print('⚠️ Please enter a valid email or username');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 🌐 Verify network connectivity first
      try {
        final testResponse = await http.get(
          Uri.parse('${ApiConfig.baseUrl}/api/health'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 8));
        
        print('🌐 Health check status: ${testResponse.statusCode}');
        
        if (testResponse.statusCode != 200) {
          throw Exception('Backend unavailable (status ${testResponse.statusCode})');
        }
      } catch (e) {
        print('❌ Network check failed: $e');
        if (mounted) {
          TopNotification.error(
            context,
            AppLocalizations.of(context)?.connectionError ??
                'Cannot connect to server. Please check your internet connection.',
          );
        }
        return;
      }

      // 🔐 STEP 1: Check if user has 2FA enabled BEFORE attempting login
      if (_isDelviooMode) {
        print('🔍 Delvioo mode - Checking 2FA status before login...');
        print('🌐 Using API URL: ${ApiConfig.baseUrl}/api/auth/check-2fa');

        try {
          final check2FAResponse = await http
              .post(
                Uri.parse('${ApiConfig.baseUrl}/api/auth/check-2fa'),
                headers: {'Content-Type': 'application/json'},
                body: json.encode({
                  'email': _emailController.text.trim(),
                  'isDelviooMode': true,
                }),
              )
              .timeout(
                const Duration(seconds: 10),
                onTimeout: () {
                  print('⏱️ 2FA check timeout - continuing with login');
                  throw Exception('Connection timeout');
                },
              );

          print('📥 2FA Check Response: ${check2FAResponse.statusCode}');

          if (check2FAResponse.statusCode == 200) {
            final check2FAData = json.decode(check2FAResponse.body);
            print('📊 2FA Check Data: $check2FAData');

            if (check2FAData['requiresTwoFA'] == true) {
              print(
                '🔐 2FA is enabled for this Delvioo user - showing 2FA input first',
              );

              // User has 2FA enabled - show 2FA modal BEFORE login
              setState(() => _isLoading = false);
              _show2FABeforeLoginModal(
                check2FAData['userId']?.toString() ?? '',
                check2FAData['email'] ?? _emailController.text.trim(),
              );
              return; // Stop here - don't proceed with login yet
            }
          } else if (check2FAResponse.statusCode == 404) {
            // User not found - continue with normal login flow (will show proper error)
            print('ℹ️ User not found in 2FA check - continuing with login');
          } else {
            print(
              '⚠️ Unexpected 2FA check response: ${check2FAResponse.statusCode}',
            );
          }
        } catch (e) {
          print('❌ 2FA Check failed: $e');
          print('ℹ️ Continuing with normal login flow');
          // Continue with normal login if 2FA check fails
        }
      }

      // 🔐 STEP 2: Proceed with normal login (if no 2FA or 2FA already verified)
      final result = await ApiService.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        isDelviooMode: _isDelviooMode,
      );

      if (result['success'] == true) {
        final userProvider = Provider.of<AppSettings>(context, listen: false);
        await userProvider.setIsLoggedIn(true);

        // Set user data if available - INCLUDING TOKEN AND userType!
        if (result['user'] != null) {
          // Extract data with fallbacks
          final userId = result['user']['id']?.toString() ?? '';
          final username = result['user']['username']?.toString() ?? userId;
          final email = result['user']['email']?.toString() ?? '';
          final name = result['user']['name']?.toString() ?? '';
          final token = result['token']?.toString() ?? '';

          // Debug logging - show what we received
          print('🔍 Login Response Analysis:');
          print('  userId: $userId');
          print('  username: $username');
          print('  email: $email');
          print('  name: $name');
          print('  token: ${token.isNotEmpty ? '${token.substring(0, 20)}...' : 'EMPTY!'}');
          print('  isDelviooMode: $_isDelviooMode');

          // Validate critical fields
          if (userId.isEmpty) {
            print('⚠️ WARNING: userId is empty!');
          }
          if (token.isEmpty) {
            print('⚠️ WARNING: token is empty!');
          }

          await userProvider.setUserData(
            userId: userId,
            name: name,
            email: email,
            token: token, // ✅ Save the token!
            userType: _isDelviooMode
                ? 'Driver'
                : AppLocalizations.of(context)?.business ?? 'Business',
            authMethod: 'email', // Mark as email/password login
          );

          // Also save username and company_name so account page can find them
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('username', username);
          if (!_isDelviooMode) {
            final companyName =
                result['user']['companyName']?.toString() ?? '';
            if (companyName.isNotEmpty) {
              await prefs.setString('company_name', companyName);
            }
            final phone = result['user']['phone']?.toString() ?? '';
            if (phone.isNotEmpty) {
              await prefs.setString('phone', phone);
            }
          }

          print('✅ Login successful');
          print('✅ Token saved: ${token.length >= 20 ? token.substring(0, 20) : token}...');
          print('✅ UserType saved: ${_isDelviooMode ? 'Driver' : 'Business'}');
          print('✅ User ID saved: $userId');
          print('✅ Username saved: $username');
        } else {
          print('❌ ERROR: result["user"] is null!');
          if (mounted) {
            TopNotification.error(
              context,
              result['message'] ?? 'Login error: user data missing. Please try again.',
            );
          }
          return;
        }

        if (mounted) {
          print('✅ Login complete - navigating to main');
          _navigateToHome(delvioo: _isDelviooMode);
        }
      } else if (result['requiresEmailVerification'] == true) {
        // Email verification required - for both Business and Delvioo users
        print('⚠️ Email verification required: ${result['message']}');
        if (mounted) {
          TopNotification.error(
            context,
            result['message'] ?? 'Please verify your email address before signing in.',
          );
        }
      } else if (result['requiresTwoFA'] == true) {
        // Reset loading BEFORE showing the sheet so the Verify button is enabled
        setState(() => _isLoading = false);
        final step = result['step'] ?? 'static_code';
        if (step == 'static_code') {
          _show2FABottomSheet(result['userId'] ?? '', isStaticCodeStep: true);
        } else if (step == 'email_code') {
          _show2FABottomSheet(result['userId'] ?? '', isStaticCodeStep: false);
        } else {
          // Fallback for compatibility
          _show2FABottomSheet(result['userId'] ?? '');
        }
      } else {
        print('❌ Login failed: ${result['message']}');
        if (mounted) {
          TopNotification.error(
            context,
            result['message'] ??
                AppLocalizations.of(context)?.loginFailed ??
                'Login failed. Please check your credentials.',
          );
        }
      }
    } catch (e) {
      print('❌ Connection error: $e');
      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.connectionError ??
              'Connection error. Please check your internet connection.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 🔵 Google Sign-In
  Future<void> _signInWithGoogle() async {
    // Use Web OAuth flow for all platforms (iOS, macOS, Desktop)
    // This avoids invalid_audience errors and native SDK issues
    setState(() => _isLoading = true);

    try {
      print('🔵 Starting Google Sign-In via Web OAuth...');

      // Generate state for CSRF protection
      final state = _generateRandomString(32);

      // Build OAuth URL with proper parameters
      final authParams = {
        'client_id': _kGoogleOAuthServerClientId,
        'redirect_uri': 'https://cultioo.com/auth/google-business-callback',
        'response_type': 'code',
        'scope': 'openid email profile',
        'state': state,
        'access_type': 'offline',
        'prompt': 'select_account',
      };

      final authUrl = Uri.https(
        'accounts.google.com',
        '/o/oauth2/v2/auth',
        authParams,
      ).toString();

      print('🌐 Opening web auth...');

      // Use flutter_web_auth_2 for consistent callback handling
      final resultUrl = await FlutterWebAuth2.authenticate(
        url: authUrl,
        callbackUrlScheme: 'cultioo-business',
      );

      print('✅ Received callback: $resultUrl');

      // Parse the code from callback URL
      final uri = Uri.parse(resultUrl);
      final code = uri.queryParameters['code'];
      final error = uri.queryParameters['error'];

      if (error != null) {
        throw Exception('User cancelled or error: $error');
      }

      if (code == null) {
        throw Exception('No authorization code received');
      }

      print('✅ Got authorization code');

      // Exchange code for token directly with Google
      print('🔵 Exchanging code for tokens with Google...');
      final tokenResponse = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'code': code,
          'client_id': _kGoogleOAuthServerClientId,
          'client_secret': 'GOOGLE_OAUTH_CLIENT_SECRET_PLACEHOLDER',
          'redirect_uri': 'https://cultioo.com/auth/google-business-callback',
          'grant_type': 'authorization_code',
        },
      );

      print('🔵 Google token response: ${tokenResponse.statusCode}');

      if (tokenResponse.statusCode != 200) {
        throw Exception('Failed to exchange code: ${tokenResponse.body}');
      }

      final tokenData = json.decode(tokenResponse.body);
      final idToken = tokenData['id_token'] as String?;
      final accessToken = tokenData['access_token'] as String?;

      if (idToken == null) {
        throw Exception('No ID token received from Google');
      }

      // Decode JWT payload (base64url) to extract email and name
      final parts = idToken.split('.');
      if (parts.length < 2) throw Exception('Invalid ID token format');
      String payload = parts[1];
      // Pad base64 string if needed
      while (payload.length % 4 != 0) payload += '=';
      final decoded = utf8.decode(base64Url.decode(payload));
      final claims = json.decode(decoded) as Map<String, dynamic>;
      final email = claims['email'] as String? ?? '';
      final name = claims['name'] as String? ?? '';
      final googleId = claims['sub'] as String? ?? '';

      print('🔵 Got ID token: email=$email, name=$name');

      // Send tokens to backend for verification and login
      // Try multiple endpoint patterns for compatibility
      http.Response? response;
      final endpoints = [
        '/api/auth/google-verify',
        '/api/auth/google',
        '/api/auth/google-signin',
      ];

      for (final endpoint in endpoints) {
        try {
          response = await http.post(
            Uri.parse('${ApiConfig.baseUrl}$endpoint'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'idToken': idToken,
              'accessToken': accessToken,
              'email': email,
              'name': name,
              'googleId': googleId,
              'isDelviooMode': _isDelviooMode,
            }),
          );
          if (response.statusCode != 404) break;
        } catch (e) {
          print('🔵 Endpoint $endpoint failed: $e');
        }
      }

      if (response == null) {
        throw Exception('All backend endpoints failed');
      }

      print('🔵 Backend response: ${response.statusCode}');
      print('🔵 Backend body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true) {
          final userProvider = Provider.of<AppSettings>(context, listen: false);
          await userProvider.setIsLoggedIn(true);

          // Extract data with proper field mapping
          final userId = data['user']?['id']?.toString() ??
                        data['user']?['username']?.toString() ??
                        '';
          final email = data['user']?['email']?.toString() ?? '';
          final name = data['user']?['name']?.toString() ??
                      '${data['user']?['firstname'] ?? ''} ${data['user']?['lastname'] ?? ''}'.trim();
          final token = data['token']?.toString() ?? '';

          await userProvider.setUserData(
            userId: userId,
            name: name,
            email: email,
            token: token,
            userType: _isDelviooMode
                ? 'Driver'
                : AppLocalizations.of(context)?.business ?? 'Business',
            authMethod: 'google',
          );

          print('✅ Google Sign-In successful');

          if (mounted) {
            _navigateToHome(delvioo: _isDelviooMode);
          }
        } else {
          throw Exception(data['message'] ?? 'Google Sign-In failed');
        }
      } else {
        throw Exception('Backend error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Google Sign-In error: $e');
      if (mounted) {
        TopNotification.error(
          context,
          'Google Sign-In failed: ${e.toString().split('\n').first}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 🌐 OAuth-based Google Sign-In for Desktop (deprecated - use _signInWithGoogle for all)
  Future<void> _signInWithGoogleOAuth() async {
    setState(() => _isLoading = true);

    final channel = const MethodChannel('cultioo_business/oauth_callback');
    final completer = Completer<String?>();

    try {
      const redirectUri = 'https://cultioo.com/auth/google-business-callback';

      print('🔵 Waiting for OAuth callback via cultioo-business:// URL scheme');

      // Receive the auth code from macOS AppDelegate via URL scheme cultioo-business://
      channel.setMethodCallHandler((call) async {
        if (call.method == 'onCode' && !completer.isCompleted) {
          final args = call.arguments as Map?;
          final code = args?['code'] as String?;
          completer.complete(code);
        }
      });

      // Generate state for CSRF protection
      final state = _generateRandomString(32);

      // Build OAuth URL with proper parameters
      final clientId = 'GOOGLE_OAUTH_CLIENT_ID_PLACEHOLDER';

      final authParams = {
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': 'openid email profile',
        'state': state,
        'access_type': 'offline',
        'prompt': 'select_account',
      };

      final authUrl = Uri.https(
        'accounts.google.com',
        '/o/oauth2/v2/auth',
        authParams,
      ).toString();

      print('🌐 Opening browser for Google Sign-In...');

      // Open browser
      final uri = Uri.parse(authUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Could not launch browser');
      }

      // Wait for callback (with timeout)
      final code = await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          print('⏱️ OAuth timeout');
          return null;
        },
      );

      if (code == null) {
        return;
      }

      print('✅ Received authorization code');

      // Exchange code for token via backend
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/google-oauth-desktop'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'code': code,
          'redirectUri': redirectUri,
          'isDelviooMode': _isDelviooMode,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // ✅ Check if user needs to upgrade to Business (BEFORE checking success)
        if (!_isDelviooMode && data['requiresBusinessUpgrade'] == true) {
          print('⚠️ User needs to upgrade to Business account');

          // Extract email from Google data
          final googleEmail = data['user']?['email'];
          if (googleEmail != null) {
            _verifiedEmail = googleEmail;
            print('📧 Setting verified email: $googleEmail');

            // Show business upgrade modal directly
            if (mounted) {
              _showUpgradeModal();
            }
          }
          return;
        }

        if (data['success'] == true) {
          final userProvider = Provider.of<AppSettings>(context, listen: false);
          await userProvider.setIsLoggedIn(true);

          // Extract data with proper field mapping
          final userId = data['user']['id']?.toString() ?? 
                        data['user']['username']?.toString() ?? 
                        '';
          final username = data['user']['username']?.toString() ?? userId;
          final email = data['user']['email']?.toString() ?? '';
          final name = data['user']['name']?.toString() ?? 
                      '${data['user']['firstname'] ?? ''} ${data['user']['lastname'] ?? ''}'.trim();
          final token = data['token']?.toString() ?? '';

          print('✅ Google OAuth Desktop Response:');
          print('  userId: $userId');
          print('  username: $username');
          print('  email: $email');
          print('  name: $name');
          print('  token: ${token.isNotEmpty ? '${token.substring(0, 20)}...' : 'EMPTY!'}');

          await userProvider.setUserData(
            userId: userId,
            name: name,
            email: email,
            token: token,
            userType: _isDelviooMode
                ? 'Driver'
                : AppLocalizations.of(context)?.business ?? 'Business',
            authMethod: 'google',
          );

          // Store username in SharedPreferences for profile loading
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('username', username);

          print('✅ Google Sign-In successful (OAuth)');
          print('📦 Stored username: $username');

          if (mounted) {
            await Future.delayed(const Duration(milliseconds: 100));
            _navigateToHome(delvioo: _isDelviooMode);
          }
        }
      }
    } catch (e) {
      print('❌ Google OAuth error: $e');
    } finally {
      channel.setMethodCallHandler(null); // clean up listener
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Helper method to complete Google Sign-In
  Future<void> _completeGoogleSignIn({
    String? idToken,
    String? accessToken,
    required String email,
    String? displayName,
    String? photoUrl,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/auth/google-signin'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'idToken': idToken,
        'accessToken': accessToken,
        'email': email,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'isDelviooMode': _isDelviooMode,
      }),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) {
        // ✅ Check if user needs to upgrade to Business (only in Business mode)
        if (!_isDelviooMode && data['requiresBusinessUpgrade'] == true) {
          print('⚠️ User needs to upgrade to Business account');

          // Set verified email and show upgrade modal directly
          _verifiedEmail = email;
          print('📧 Setting verified email: $email');

          if (mounted) {
            _showUpgradeModal();
          }
          return;
        }

        final userProvider = Provider.of<AppSettings>(context, listen: false);
        await userProvider.setIsLoggedIn(true);

        // Extract data with proper field mapping
        final userId = data['user']['id']?.toString() ?? 
                      data['user']['username']?.toString() ?? 
                      '';
        final username = data['user']['username']?.toString() ?? userId;
        final userEmail = data['user']['email']?.toString() ?? '';
        final userName = data['user']['name']?.toString() ?? 
                        '${data['user']['firstname'] ?? ''} ${data['user']['lastname'] ?? ''}'.trim();
        final token = data['token']?.toString() ?? '';

        print('✅ Google Sign-In Response:');
        print('  userId: $userId');
        print('  username: $username');
        print('  email: $userEmail');
        print('  name: $userName');

        await userProvider.setUserData(
          userId: userId,
          name: userName,
          email: userEmail,
          token: token,
          userType: _isDelviooMode
              ? 'Driver'
              : AppLocalizations.of(context)?.business ?? 'Business',
          authMethod: 'google',
        );

        // Store username
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('username', username);

        print('✅ Google Sign-In successful');

        if (mounted) {
          await Future.delayed(const Duration(milliseconds: 100));
          _navigateToHome(delvioo: _isDelviooMode);
        }
      }
    }
  }

  // 🍎 Apple Sign-In
  Future<void> _signInWithApple() async {
    if (!_isIOS) {
      print('⚠️ Apple Sign-In is only available on iOS');
      return;
    }

    setState(() => _isLoading = true);

    try {
      print('🍎 Requesting Apple Sign-In with email and fullName scopes...');
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      print('🍎 Apple Sign-In credential received');

      if (credential.identityToken == null) {
        throw Exception('Apple did not return an identity token');
      }

      // Apple only returns email on the FIRST sign-in. Cache it so subsequent
      // sign-ins (where email is null) can still send it to the backend.
      final prefs = await SharedPreferences.getInstance();
      final emailCacheKey = 'apple_email_${credential.userIdentifier}';
      final userIdCacheKey = 'apple_user_id';

      String? appleEmail = credential.email;
      print('🍎 Apple returned email: $appleEmail');
      
      // If Apple didn't return email, try to extract it from the identity token
      if ((appleEmail == null || appleEmail.isEmpty) && credential.identityToken != null) {
        print('🍎 Apple did not return email directly - decoding identity token...');
        try {
          final parts = credential.identityToken!.split('.');
          if (parts.length >= 2) {
            String payload = parts[1];
            // Pad base64 string if needed
            while (payload.length % 4 != 0) payload += '=';
            final decoded = utf8.decode(base64Url.decode(payload));
            final claims = json.decode(decoded) as Map<String, dynamic>;
            appleEmail = claims['email'] as String?;
            print('🍎 Extracted email from token: $appleEmail');
          }
        } catch (e) {
          print('⚠️ Failed to decode identity token: $e');
        }
      }
      
      if (appleEmail != null && appleEmail.isNotEmpty) {
        await prefs.setString(emailCacheKey, appleEmail);
        print('🍎 Cached email: $appleEmail');
      } else {
        appleEmail = prefs.getString(emailCacheKey);
        print('🍎 Using cached email: $appleEmail');
      }

      // Always store the userIdentifier for subsequent logins
      await prefs.setString(userIdCacheKey, credential.userIdentifier ?? '');
      
      // If still no email, something is wrong
      if (appleEmail == null || appleEmail.isEmpty) {
        print('❌ No email available from Apple or cache');
        if (mounted) {
          setState(() => _isLoading = false);
          TopNotification.error(
            context,
            'Apple Sign-In Error: Email not available. Please try again or contact support.',
          );
        }
        return;
      }

      print('🍎 Apple credential obtained - sending to backend...');
      print('🍎 identityToken length: ${credential.identityToken!.length}');
      print('🍎 userIdentifier: ${credential.userIdentifier}');
      print('🍎 email (resolved): $appleEmail');

      // Send to backend
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/apple-signin'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'identityToken': credential.identityToken,
          'authorizationCode': credential.authorizationCode,
          'email': appleEmail,
          'givenName': credential.givenName,
          'familyName': credential.familyName,
          'userIdentifier': credential.userIdentifier,
          'isDelviooMode': _isDelviooMode,
        }),
      ).timeout(const Duration(seconds: 20));

      print('🍎 Backend response: ${response.statusCode}');
      print('🍎 Backend body: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final userProvider = Provider.of<AppSettings>(context, listen: false);
          await userProvider.setIsLoggedIn(true);

          // Extract data with proper field mapping
          final userId = data['user']['id']?.toString() ?? 
                        data['user']['username']?.toString() ?? 
                        '';
          final username = data['user']['username']?.toString() ?? userId;
          final userEmail = data['user']['email']?.toString() ?? '';
          final userName = data['user']['name']?.toString() ?? 
                          '${data['user']['firstname'] ?? ''} ${data['user']['lastname'] ?? ''}'.trim();
          final token = data['token']?.toString() ?? '';

          await userProvider.setUserData(
            userId: userId,
            name: userName,
            email: userEmail,
            token: token,
            userType: _isDelviooMode
                ? 'Driver'
                : AppLocalizations.of(context)?.business ?? 'Business',
            authMethod: 'apple', // Mark as Apple Sign-In
          );

          // Store username
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('username', username);

          print('✅ Apple Sign-In successful');

          if (mounted) {
            await Future.delayed(const Duration(milliseconds: 100));
            _navigateToHome(delvioo: _isDelviooMode);
          }
        } else {
          print('❌ Apple Sign-In failed: ${data['message']}');
          if (mounted) {
            TopNotification.error(
              context,
              data['message'] ?? 'Apple Sign-In failed. Please try again.',
            );
          }
        }
      } else {
        String backendError = 'Apple Sign-In failed (${response.statusCode})';
        try {
          final errData = json.decode(response.body);
          backendError = errData['message']?.toString() ?? backendError;
        } catch (_) {}
        print('❌ Apple Sign-In backend error: $backendError');
        if (mounted) {
          TopNotification.error(context, backendError);
        }
      }
    } catch (err) {
      final isCancelled = err is SignInWithAppleAuthorizationException &&
          err.code == AuthorizationErrorCode.canceled;
      print('❌ Apple Sign-In error: $err');
      if (!isCancelled && mounted) {
        TopNotification.error(
          context,
          'Apple Sign-In failed. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _generateRandomString(int length) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(
      length,
      (index) => chars[random.nextInt(chars.length)],
    ).join();
  }

  // 🔵 Google Sign-In for Business Upgrade (checks if email exists in users table)
  Future<void> _signInWithGoogleForBusinessUpgrade() async {
    // Use browser-based OAuth for macOS to avoid keychain issues
    if (Platform.isMacOS) {
      print('⚠️ Browser-based sign-in for business upgrade not implemented');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        scopes: const ['email', 'profile'],
        serverClientId: _kGoogleOAuthServerClientId,
      );

      // Sign out first to force account selection
      await googleSignIn.signOut();

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        // User cancelled
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Send to backend with business upgrade flag
      final response = await http.post(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/auth/google-signin-business-upgrade',
        ),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'idToken': googleAuth.idToken,
          'accessToken': googleAuth.accessToken,
          'email': googleUser.email,
          'displayName': googleUser.displayName,
          'photoUrl': googleUser.photoUrl,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          if (data['requiresBusinessUpgrade'] == true) {
            // User exists but is not a business yet - show business details modal
            print(
              '✅ Google email verified - User exists, showing business upgrade form',
            );
            _verifiedEmail = googleUser.email;
            if (mounted) {
              setState(() => _isLoading = false);
              _showBusinessDetailsModal();
            }
          } else if (data['alreadyBusiness'] == true) {
            // User is already a business - just log them in
            print('✅ User is already a business - logging in');
            final userProvider = Provider.of<AppSettings>(
              context,
              listen: false,
            );
            await userProvider.setIsLoggedIn(true);
            await userProvider.setUserData(
              userId: data['user']['id']?.toString() ?? '',
              name: data['user']['name'] ?? '',
              email: data['user']['email'] ?? '',
              token: data['token'] ?? '',
              userType: AppLocalizations.of(context)?.business ?? 'Business',
            );

            if (mounted) {
              await Future.delayed(const Duration(milliseconds: 100));
              _navigateToHome(delvioo: false);
            }
          } else {
            // New user - create account and show business details
            print(
              '✅ New Google user - creating account and showing business upgrade form',
            );
            _verifiedEmail = googleUser.email;
            if (mounted) {
              setState(() => _isLoading = false);
              _showBusinessDetailsModal();
            }
          }
        }
      }
    } catch (e) {
      print('❌ Google Sign-In error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSuccessDialog(String message) {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final isLight = appSettings.isLightMode(context);

    TradeRepublicBottomSheet.show(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DragHandle(),
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.checkmark_circle_fill,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.success ?? 'Success',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.green,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.7),
            ),
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
          SizedBox(
            width: double.infinity,
            child: TradeRepublicButton(
              label: AppLocalizations.of(context)?.ok ?? 'OK',
              onPressed: () => Navigator.of(context).pop(),
              backgroundColor: Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  // 🔐 NEW: Show 2FA modal BEFORE login attempt (for Delvioo users with 2FA enabled)
  void _show2FABeforeLoginModal(String userId, String email) {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final isLight = appSettings.isLightMode(context);
    final twoFAController = TextEditingController();

    TradeRepublicBottomSheet.show(
      context: context,
      enableDrag: true,
      isDismissible: false, // User must enter 2FA code
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DragHandle(),
            // ── Sheet header: Icon left + Title ──
            Row(
              children: [
                Icon(
                  CupertinoIcons.lock_shield_fill,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)?.twoFactorAuthentication ??
                        'Two-Factor Authentication',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: isLight ? Colors.black : Colors.white,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

            Text(
              AppLocalizations.of(context)?.pleaseEnter2faCodeToContinue ??
                  'Please enter your 2FA code to continue',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: DesktopOptimizedWidgets.getFontSize(),
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.7),
              ),
            ),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

            // 2FA Code Input
            TradeRepublicTextField(
              controller: twoFAController,
              keyboardType: TextInputType.number,
              maxLength: 8,
              textAlign: TextAlign.center,
              hintText: '00000000',
            ),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

            // Verify Button
            SizedBox(
              width: double.infinity,
              child: Platform.isIOS
                  ? TradeRepublicButton(
                      label:
                          AppLocalizations.of(context)?.verifyLogin ??
                          'Verify & Login',
                      onPressed: () async {
                        if (twoFAController.text.length != 8) {
                          print('⚠️ Please enter your 8-digit 2FA code');
                          return;
                        }

                        print('═══════════════════════════════════════');
                        print('🔐 STARTING 2FA LOGIN PROCESS');
                        print('═══════════════════════════════════════');

                        // Get Provider and Navigator BEFORE closing modal (while context is valid)
                        // Get Provider and Navigator BEFORE closing modal (while context is valid)
                        final userProvider = Provider.of<AppSettings>(
                          context,
                          listen: false,
                        );
                        final navigatorContext = Navigator.of(context);

                        print('📧 Email: $email');
                        print('🔑 2FA Code: ${twoFAController.text}');
                        print(
                          '🔑 Password length: ${_passwordController.text.length}',
                        );
                        print('🌐 API Base URL: ${ApiConfig.baseUrl}');
                        print(
                          '🌐 Full Login URL: ${ApiConfig.baseUrl}/api/auth/login',
                        );

                        navigatorContext.pop(); // Close 2FA modal
                        print('✅ Modal closed');

                        if (!mounted) {
                          print('❌ Widget not mounted after modal close');
                          return;
                        }
                        setState(() => _isLoading = true);
                        print('✅ Loading state set to true');

                        try {
                          print('───────────────────────────────────────');
                          print('� Sending login request...');

                          // Now attempt login WITH 2FA code
                          final result = await ApiService.login(
                            email: email,
                            password: _passwordController.text,
                            isDelviooMode: true,
                            twoFACode: twoFAController.text,
                          );

                          print('───────────────────────────────────────');
                          print('📥 Login Result received: $result');
                          print('📥 Success: ${result['success']}');
                          print('📥 Message: ${result['message']}');
                          if (result['token'] != null) {
                            print(
                              '📥 Token: ${result['token'].toString().substring(0, 50)}...',
                            );
                          }

                          if (!mounted) return;

                          if (result['success'] == true) {
                            print('✅ Login successful with 2FA!');

                            // Check if email verification is required
                            if (result['requiresEmailVerification'] == true ||
                                result['user']?['email_verified'] == false ||
                                result['user']?['email_verified'] == 0) {
                              print(
                                '📧 Email verification required - showing verification modal',
                              );

                              // Save user data first
                              if (result['user'] != null) {
                                await userProvider.setUserData(
                                  userId:
                                      result['user']['id']?.toString() ?? '',
                                  name: result['user']['name'] ?? '',
                                  email: result['user']['email'] ?? '',
                                  token: result['token'] ?? '',
                                  userType: 'Driver',
                                );
                              }

                              // Show email verification modal
                              if (mounted) {
                                _showDelviooEmailVerificationModal(
                                  email: result['user']?['email'] ?? email,
                                  userId:
                                      result['user']?['id']?.toString() ??
                                      userId,
                                  userProvider: userProvider,
                                  navigatorContext: navigatorContext,
                                );
                              }
                              return; // Don't proceed to main page yet
                            }

                            // Use the Provider reference we saved earlier
                            await userProvider.setIsLoggedIn(true);

                            if (result['user'] != null) {
                              await userProvider.setUserData(
                                userId: result['user']['id']?.toString() ?? '',
                                name: result['user']['name'] ?? '',
                                email: result['user']['email'] ?? '',
                                token: result['token'] ?? '',
                                userType: 'Driver',
                              );
                            }

                            // Wait a bit for state updates to complete
                            await Future.delayed(
                              const Duration(milliseconds: 100),
                            );

                            if (mounted) {
                              print('✅ About to navigate to Delvioo main page');
                              _navigateToHome(delvioo: true);
                              print('✅ Navigation command issued');
                            }
                          } else {
                            print('❌ Login failed: ${result['message']}');
                          }
                        } catch (e) {
                          print('═══════════════════════════════════════');
                          print('❌ LOGIN EXCEPTION CAUGHT');
                          print('═══════════════════════════════════════');
                          print('❌ Exception Type: ${e.runtimeType}');
                          print('❌ Exception Message: $e');
                          print('❌ Exception Details: ${e.toString()}');
                          print(
                            '🌐 Was trying to connect to: ${ApiConfig.baseUrl}',
                          );
                          print('═══════════════════════════════════════');

                          print('❌ Connection error: $e');
                        } finally {
                          if (mounted) {
                            setState(() => _isLoading = false);
                            print('✅ Loading state set to false');
                          }
                          print('═══════════════════════════════════════');
                          print('🏁 2FA LOGIN PROCESS COMPLETED');
                          print('═══════════════════════════════════════');
                        }
                      },
                    )
                  : TradeRepublicButton(
                      label:
                          AppLocalizations.of(context)?.verifyLogin ??
                          'Verify & Login',
                      backgroundColor: Colors.green,
                      onPressed: () async {
                        if (twoFAController.text.length != 8) {
                          print('⚠️ Please enter your 8-digit 2FA code');
                          return;
                        }
                        // Same logic as above
                        final userProvider = Provider.of<AppSettings>(
                          context,
                          listen: false,
                        );
                        Navigator.of(context).pop();
                        setState(() => _isLoading = true);
                        try {
                          final result = await ApiService.login(
                            email: _emailController.text.trim(),
                            password: _passwordController.text,
                            twoFACode: twoFAController.text.trim(),
                            isDelviooMode: _isDelviooMode,
                          );
                          if (result['success'] == true) {
                            await userProvider.setIsLoggedIn(true);
                            if (result['user'] != null) {
                              await userProvider.setUserData(
                                userId: result['user']['id']?.toString() ?? '',
                                name: result['user']['name'] ?? '',
                                email: result['user']['email'] ?? '',
                                token: result['token'] ?? '',
                                userType: 'Driver',
                              );
                            }
                            await Future.delayed(
                              const Duration(milliseconds: 100),
                            );
                            if (mounted) {
                              _navigateToHome(delvioo: true);
                            }
                          } else {
                            print('❌ Login failed: ${result['message']}');
                          }
                        } catch (e) {
                          print('❌ Connection error: $e');
                        } finally {
                          if (mounted) {
                            setState(() => _isLoading = false);
                          }
                        }
                      },
                    ),
            ),

            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

            // Cancel Button
            Platform.isIOS
                ? TradeRepublicButton(
                    label: AppLocalizations.of(context)?.cancel ?? 'Cancel',
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  )
                : TradeRepublicButton(
                    label: AppLocalizations.of(context)?.cancel ?? 'Cancel',
                    isSecondary: true,
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),

            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
          ],
        ),
      ),
    );
  }

  void _show2FABottomSheet(String userId, {bool? isStaticCodeStep}) {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final isLight = appSettings.isLightMode(context);
    final twoFAController = TextEditingController();
    final bool isStaticStep =
        isStaticCodeStep ??
        true; // Default to static code step for compatibility

    TradeRepublicBottomSheet.show(
      context: context,
      enableDrag: true,
      isDismissible: false, // User must enter 2FA code
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DragHandle(),
            // ── Sheet header: Icon left + Title ──
            Row(
              children: [
                Icon(
                  CupertinoIcons.lock_shield_fill,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)?.twoFactorAuthentication ??
                        'Two-Factor Authentication',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: isLight ? Colors.black : Colors.white,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

            Text(
              isStaticStep
                  ? AppLocalizations.of(context)?.pleaseEnter8DigitAuthCode ??
                        'Please enter your 8-digit authentication code'
                  : AppLocalizations.of(context)?.verificationCodeDescription ??
                        'An 8-digit verification code has been sent to your email',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: DesktopOptimizedWidgets.getFontSize(),
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.7),
              ),
            ),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

            // 2FA Code Input - Trade Republic Style
            TradeRepublicTextField(
              controller: twoFAController,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              textAlign: TextAlign.center,
              hintText: '00000000',
            ),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

            // Verify Button
            TradeRepublicButton(
              label: AppLocalizations.of(context)?.verifyCode ?? 'Verify Code',
              onPressed: _isLoading
                  ? null
                  : () async {
                      final code = twoFAController.text.trim();
                      if (code.isEmpty) {
                        print('⚠️ Please enter your 2FA code');
                        return;
                      }

                      // Prevent double submission
                      if (_isLoading) {
                        print(
                          '⚠️ 2FA verification already in progress, ignoring duplicate request',
                        );
                        return;
                      }

                      // Show loading state
                      setState(() => _isLoading = true);

                      try {
                        Map<String, dynamic> result;

                        if (isStaticStep) {
                          // ✅ For static code: use login endpoint with twoFACode
                          print(
                            '🔐 Verifying static 2FA code via login endpoint',
                          );
                          result = await ApiService.login(
                            email: _emailController.text.trim(),
                            password: _passwordController.text,
                            twoFACode: code,
                            isDelviooMode: _isDelviooMode,
                          );
                        } else {
                          // ✅ For email code: use verify-2fa endpoint
                          print(
                            '📧 Verifying email 2FA code via verify-2fa endpoint',
                          );
                          result = await ApiService.verify2FA(
                            userId: userId,
                            code: code,
                            isDelviooMode: _isDelviooMode,
                          );
                        }

                        if (result['success'] == true) {
                          print(
                            '✅ 2FA SUCCESS - Starting navigation process...',
                          );

                          final userProvider = Provider.of<AppSettings>(
                            context,
                            listen: false,
                          );

                          print('✅ Closing 2FA sheet...');
                          // Close 2FA sheet first - use root navigator
                          if (mounted) {
                            Navigator.of(context, rootNavigator: true).pop();
                          }

                          // Small delay to ensure modal is closed
                          await Future.delayed(
                            const Duration(milliseconds: 100),
                          );

                          print(
                            '✅ Navigating to main page BEFORE saving token...',
                          );
                          // Navigate FIRST, before saving token (which triggers notifyListeners)
                          if (mounted) {
                            final targetRoute = _isDelviooMode
                                ? '/delvioo-main'
                                : '/main';
                            print('✅ Target route: $targetRoute');

                            // Push to main page
                            _navigateToHome(delvioo: _isDelviooMode);

                            print(
                              '✅ Navigation initiated, now saving token...',
                            );
                          }

                          // NOW save the token and user data (after navigation is started)
                          await userProvider.setIsLoggedIn(true);

                          if (result['user'] != null) {
                            await userProvider.setUserData(
                              userId: result['user']['id']?.toString() ?? '',
                              name: result['user']['name'] ?? '',
                              email: result['user']['email'] ?? '',
                              token: result['token'],
                              userType: _isDelviooMode
                                  ? 'Driver'
                                  : AppLocalizations.of(
                                          context,
                                        )?.businessLabel ??
                                        'Business', // ✅ Save the userType!
                            );
                            print(
                              '✅ Token stored after 2FA: ${result['token']?.substring(0, 20)}...',
                            );
                            print(
                              '✅ UserType saved: ${_isDelviooMode ? 'Driver' : 'Business'}',
                            );
                          }

                          print('✅ 2FA login completed successfully');
                        } else if (result['requiresTwoFA'] == true &&
                            result['step'] == 'email_code') {
                          // ✅ Static code was correct, now close current modal and open NEW modal for email code
                          print(
                            '✅ Static code verified, switching to email code step',
                          );

                          // Close current static code modal
                          if (mounted && Navigator.canPop(context)) {
                            Navigator.of(context).pop();
                          }

                          // Wait a moment for modal to close, then open 2FA email code sheet
                          // NOTE: Do NOT call _showEmailCodeModal here – the backend already
                          // sent the email code via send2FACode(). Calling _showEmailCodeModal
                          // would send a SECOND email with a DIFFERENT code.
                          await Future.delayed(
                            const Duration(milliseconds: 200),
                          );

                          if (mounted) {
                            _show2FABottomSheet(userId, isStaticCodeStep: false);
                          }
                        } else {
                          // Show error but keep sheet open so user can retry
                          if (mounted) {
                            TopNotification.error(
                              context,
                              result['message'] ??
                                  AppLocalizations.of(
                                    context,
                                  )?.twoFaVerificationFailed ??
                                  '2FA verification failed',
                            );
                          }
                        }
                      } catch (e) {
                        // Show error but keep sheet open so user can retry
                        if (mounted) {
                          TopNotification.error(
                            context,
                            '${AppLocalizations.of(context)?.verificationError ?? "Verification error"}: ${e.toString()}',
                          );
                        }
                      } finally {
                        if (mounted) {
                          setState(() => _isLoading = false);
                        }
                      }
                    },
            ),

            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

            // Resend Email Button (only for email step)
            if (!isStaticStep) ...[
              Platform.isIOS
                  ? TradeRepublicButton(
                      label:
                          AppLocalizations.of(context)?.resendEmail ??
                          'Resend email',
                      onPressed: () async {
                        try {
                          final response = await http
                              .post(
                                Uri.parse(
                                  '${ApiService.baseUrl}/auth/resend-2fa-email',
                                ),
                                headers: {
                                  'Content-Type': 'application/json',
                                  'Accept': 'application/json',
                                },
                                body: jsonEncode({'username': userId}),
                              )
                              .timeout(const Duration(seconds: 15));

                          final data = jsonDecode(response.body);

                          if (response.statusCode == 200) {
                            TopNotification.success(
                              context,
                              data['message'] ??
                                  AppLocalizations.of(context)?.newEmailSent ??
                                  'New email has been sent',
                            );
                          } else {
                            TopNotification.error(
                              context,
                              data['message'] ??
                                  AppLocalizations.of(
                                    context,
                                  )?.errorSendingEmail ??
                                  'Error sending email',
                            );
                          }
                        } catch (e) {
                          TopNotification.error(
                            context,
                            '${AppLocalizations.of(context)?.connectionError ?? 'Connection error'}: ${e.toString()}',
                          );
                        }
                      },
                    )
                  : TradeRepublicButton(
                      label:
                          AppLocalizations.of(context)?.resendEmail ??
                          'Resend email',
                      isSecondary: true,
                      onPressed: () async {
                        try {
                          final response = await http
                              .post(
                                Uri.parse(
                                  '${ApiService.baseUrl}/auth/resend-2fa-email',
                                ),
                                headers: {
                                  'Content-Type': 'application/json',
                                  'Accept': 'application/json',
                                },
                                body: jsonEncode({'username': userId}),
                              )
                              .timeout(const Duration(seconds: 15));

                          final data = jsonDecode(response.body);

                          if (response.statusCode == 200) {
                            TopNotification.success(
                              context,
                              data['message'] ??
                                  AppLocalizations.of(context)?.newEmailSent ??
                                  'New email has been sent',
                            );
                          } else {
                            TopNotification.error(
                              context,
                              data['message'] ??
                                  AppLocalizations.of(
                                    context,
                                  )?.errorSendingEmail ??
                                  'Error sending email',
                            );
                          }
                        } catch (e) {
                          TopNotification.error(
                            context,
                            '${AppLocalizations.of(context)?.connectionError ?? 'Connection error'}: ${e.toString()}',
                          );
                        }
                      },
                    ),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
            ],

            // Cancel Button
            Platform.isIOS
                ? TradeRepublicButton(
                    label: AppLocalizations.of(context)?.cancel ?? 'Cancel',
                    onPressed: () {
                      Navigator.of(context).pop();
                      setState(() => _isLoading = false);
                    },
                  )
                : TradeRepublicButton(
                    label: AppLocalizations.of(context)?.cancel ?? 'Cancel',
                    isSecondary: true,
                    onPressed: () {
                      Navigator.of(context).pop();
                      setState(() => _isLoading = false);
                    },
                  ),

            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
          ],
        ),
      ),
    );
  }

  Widget _buildAppModeSwitch(bool isLight) {
    // On macOS: Use TradeRepublicSlider
    if (_isMacOS) {
      return Container(
        width: 300,
        padding: EdgeInsets.symmetric(horizontal: DesktopAppWrapper.getHorizontalPadding()),
        child: TradeRepublicSliderExpanded(
          labels: [
            AppLocalizations.of(context)?.businessLabel ?? 'Business',
            'Delvioo',
          ],
          selectedIndex: _tabIndex,
          horizontalPadding: 0,
          height: 52,
          onChanged: (index) {
            setState(() {
              _tabIndex = index;
              if (index == 0) {
                _switchController.reverse();
              } else {
                _switchController.forward();
              }
            });
          },
        ),
      );
    }

    // On iOS: Use TradeRepublicSlider (same as macOS/Android)
    if (_isIOS) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: DesktopAppWrapper.getHorizontalPadding()),
        child: TradeRepublicSliderExpanded(
          labels: [
            AppLocalizations.of(context)?.businessLabel ?? 'Business',
            'Delvioo',
          ],
          selectedIndex: _tabIndex,
          horizontalPadding: 0,
          height: 52,
          onChanged: (index) {
            setState(() {
              _tabIndex = index;
              if (index == 0) {
                _switchController.reverse();
              } else {
                _switchController.forward();
              }
            });
          },
        ),
      );
    }

    // On Android: Use TradeRepublicSlider
    return Container(
      padding: EdgeInsets.symmetric(horizontal: DesktopAppWrapper.getHorizontalPadding()),
      child: TradeRepublicSliderExpanded(
        labels: [
          AppLocalizations.of(context)?.businessLabel ?? 'Business',
          'Delvioo',
        ],
        selectedIndex: _tabIndex,
        horizontalPadding: 0,
        height: 52,
        onChanged: (index) {
          setState(() {
            _tabIndex = index;
            if (index == 0) {
              _switchController.reverse();
            } else {
              _switchController.forward();
            }
          });
        },
      ),
    );
  }

  // Kept for backwards compatibility but no longer used
  Widget _buildAppModeSwitchOld(bool isLight) {
    if (_isMacOS) {
      const double buttonWidth = 140.0;
      const double buttonHeight = 48.0;

      return ClipRRect(
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: buttonWidth * 2 + 12,
            height: buttonHeight + 12,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: (isLight ? Colors.white : Colors.black).withOpacity(0.3),
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            ),

            child: LayoutBuilder(
              builder: (context, constraints) {
                final halfWidth = constraints.maxWidth / 2;
                return Stack(
                  children: [
                    // Animated sliding background
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      left: _tabIndex == 0 ? 0 : halfWidth,
                      top: 0,
                      bottom: 0,
                      width: halfWidth,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isLight ? Colors.black : Colors.white,
                          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          boxShadow: [
                            BoxShadow(
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Buttons
                    Row(
                      children: [
                        // Business Button
                        Expanded(
                          child: TradeRepublicTap(
                            onTap: () {
                              setState(() {
                                _tabIndex = 0;
                                _switchController.reverse();
                              });
                            },
                            child: Container(
                              height: buttonHeight,
                              color: Colors.transparent,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    child: Icon(
                                      CupertinoIcons.briefcase_fill,
                                      key: ValueKey(_tabIndex == 0),
                                      size: 20,
                                      color: _tabIndex == 0
                                          ? (isLight
                                                ? Colors.white
                                                : Colors.black)
                                          : (isLight
                                                    ? Colors.black
                                                    : Colors.white)
                                                .withOpacity(0.5),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 200),
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: _tabIndex == 0
                                          ? (isLight
                                                ? Colors.white
                                                : Colors.black)
                                          : (isLight
                                                    ? Colors.black
                                                    : Colors.white)
                                                .withOpacity(0.5),
                                    ),
                                    child: Text(
                                      AppLocalizations.of(context)?.business ??
                                          'Business',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Delvioo Button
                        Expanded(
                          child: TradeRepublicTap(
                            onTap: () {
                              setState(() {
                                _tabIndex = 1;
                                _switchController.forward();
                              });
                            },
                            child: Container(
                              height: buttonHeight,
                              color: Colors.transparent,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    child: Icon(
                                      CupertinoIcons.cube_box_fill,
                                      key: ValueKey(_tabIndex == 1),
                                      size: 20,
                                      color: _tabIndex == 1
                                          ? (isLight
                                                ? Colors.white
                                                : Colors.black)
                                          : (isLight
                                                    ? Colors.black
                                                    : Colors.white)
                                                .withOpacity(0.5),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 200),
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: _tabIndex == 1
                                          ? (isLight
                                                ? Colors.white
                                                : Colors.black)
                                          : (isLight
                                                    ? Colors.black
                                                    : Colors.white)
                                                .withOpacity(0.5),
                                    ),
                                    child: Text(
                                      AppLocalizations.of(context)?.delvioo ??
                                          'Delvioo',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
    }

    // On iOS: Use TradeRepublicSlider (same as macOS/Android)
    if (_isIOS) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: DesktopAppWrapper.getHorizontalPadding()),
        child: TradeRepublicSliderExpanded(
          labels: [
            AppLocalizations.of(context)?.businessLabel ?? 'Business',
            'Delvioo',
          ],
          selectedIndex: _tabIndex,
          horizontalPadding: 0,
          height: 52,
          onChanged: (index) {
            setState(() {
              _tabIndex = index;
              if (index == 0) {
                _switchController.reverse();
              } else {
                _switchController.forward();
              }
            });
          },
        ),
      );
    }

    // On Android: Use custom glass morphism switch
    return ClipRRect(
      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isLight
                ? Colors.white.withOpacity(0.15)
                : Colors.black.withOpacity(0.25),
            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            boxShadow: [
              BoxShadow(
                color: isLight
                    ? Colors.black.withOpacity(0.1)
                    : Colors.black.withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final switchWidth = constraints.maxWidth;
              final buttonWidth = switchWidth / 2;

              return Stack(
                children: [
                  // Animated sliding background with glass effect
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOutCubic,
                    width: buttonWidth,
                    height: 56,
                    margin: EdgeInsets.only(
                      left: _isDelviooMode ? buttonWidth : 0,
                    ),
                    decoration: BoxDecoration(
                      color: isLight
                          ? Colors.black.withOpacity(0.8)
                          : Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                      boxShadow: [
                        BoxShadow(
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.4),
                          blurRadius: 15,
                          spreadRadius: 2,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                  // Button texts
                  Row(
                    children: [
                      Expanded(
                        child: TradeRepublicTap(
                          onTap: () {
                            if (_isDelviooMode) {
                              setState(() {
                                _tabIndex = 0;
                              });
                              _switchController.reverse();
                            }
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 18,
                              horizontal: 12,
                            ),
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.easeInOutCubic,
                              style: TextStyle(
                                color: !_isDelviooMode
                                    ? (isLight ? Colors.white : Colors.black)
                                    : isLight
                                    ? Colors.black.withOpacity(0.6)
                                    : Colors.white.withOpacity(0.6),
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                fontWeight: FontWeight.w700,
                              ),
                              child: Text(
                                AppLocalizations.of(context)?.business ??
                                    'Business',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: TradeRepublicTap(
                          onTap: () {
                            if (!_isDelviooMode) {
                              setState(() {
                                _tabIndex = 1;
                              });
                              _switchController.forward();
                            }
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 18,
                              horizontal: 12,
                            ),
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.easeInOutCubic,
                              style: TextStyle(
                                color: _isDelviooMode
                                    ? (isLight ? Colors.white : Colors.black)
                                    : isLight
                                    ? Colors.black.withOpacity(0.6)
                                    : Colors.white.withOpacity(0.6),
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                fontWeight: FontWeight.w700,
                              ),
                              child: Text(
                                AppLocalizations.of(context)?.delvioo ??
                                    'Delvioo',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // macOS Switch Button Helper
  Widget _buildMacOSSwitchButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required bool isLight,
    required VoidCallback onTap,
  }) {
    return TradeRepublicTap(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? (isLight ? Colors.black : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? (isLight ? Colors.white : Colors.black)
                  : (isLight ? Colors.black : Colors.white).withOpacity(0.6),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: DesktopOptimizedWidgets.getFontSize(),
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? (isLight ? Colors.white : Colors.black)
                    : (isLight ? Colors.black : Colors.white).withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Animated transition to select a mode
  void _selectMode(int index) {
    setState(() {
      _tabIndex = index;
    });
    // Animate out selection screen, then show login
    _modeTransitionController.forward().then((_) {
      setState(() {
        _hasSelectedMode = true;
      });
      _modeTransitionController.reset();
      // Reset and replay login form animations
      _slideController.reset();
      _fadeController.reset();
      _startAnimations();
    });
  }

  /// Animated transition back to mode selection
  void _goBackToModeSelection() {
    if (_isMacOS || Platform.isWindows || Platform.isLinux) {
      return;
    }

    _fadeController.reverse().then((_) {
      setState(() {
        _hasSelectedMode = false;
      });
      _fadeController.reset();
      _fadeController.forward();
      _slideController.reset();
      _slideController.forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    final appSettings = Provider.of<AppSettings>(context, listen: true);
    final isLight = appSettings.isLightMode(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    // Platform-adaptive sizing
    final isDesktop = _isMacOS || Platform.isWindows || Platform.isLinux;
    final isMobile = _isIOS || _isAndroid;

    // Desktop: always Business login only (no mode selector / no Delvioo option).
    // Mobile: keep mode selection.
    if (!_hasSelectedMode && !isDesktop) {
      return _buildModeSelectionScreen(
        isLight,
        isDesktop,
        isMobile,
        screenHeight,
      );
    }

    // Responsive values
    final horizontalPadding = isDesktop ? 0.0 : 24.0;
    final maxFormWidth = isDesktop ? 420.0 : double.infinity;
    final logoSize = 60.0;
    final titleSize = 30.0;
    final inputHeight = 54.0;
    final buttonHeight = 56.0;
    final topSpacing =
        MediaQuery.of(context).padding.top +
        (isDesktop ? screenHeight * 0.1 : screenHeight * 0.06);

    return Scaffold(
      backgroundColor: isLight ? Colors.white : Colors.black,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Stack(
            children: [
              // Main scrollable content
              Center(
                child: SingleChildScrollView(
                    physics: isMobile
                        ? const BouncingScrollPhysics()
                        : const ClampingScrollPhysics(),
                    child: Container(
                      constraints: BoxConstraints(maxWidth: maxFormWidth),
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(height: topSpacing),

                          // Back button to go back to mode selection
                          if (!isDesktop)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: TradeRepublicTap(
                                  onTap: _goBackToModeSelection,
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color:
                                          (isLight ? Colors.black : Colors.white)
                                              .withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                    ),
                                    child: Icon(
                                      CupertinoIcons.back,
                                      size: 20,
                                      color: isLight
                                          ? Colors.black
                                          : Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                          const SizedBox(height: 20),

                          // App Logo — uses actual logo images
                          ClipRRect(
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                            child: Image.asset(
                              isLight
                                  ? 'logo/cultioo_word_transparent_lightmode.png'
                                  : 'logo/cultioo_word_transparent_darkmode.png',
                              height: logoSize,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Container(
                                width: logoSize,
                                height: logoSize,
                                decoration: BoxDecoration(
                                  color: isLight ? Colors.black : Colors.white,
                                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                ),
                                child: Icon(
                                  _isDelviooMode
                                      ? CupertinoIcons.cube_box_fill
                                      : CupertinoIcons.briefcase_fill,
                                  size: logoSize * 0.45,
                                  color: isLight ? Colors.white : Colors.black,
                                ),
                              ),
                            ),
                          ),

                          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                          // Title
                          Text(
                            _isDelviooMode
                                ? AppLocalizations.of(context)?.delviooLabel ??
                                      'Delvioo'
                                : 'Seller Login',
                            style: TextStyle(
                              fontSize: titleSize,
                              fontWeight: FontWeight.w700,
                              color: isLight ? Colors.black : Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),

                          const SizedBox(height: 6),

                          // Subtitle
                          Text(
                            _isDelviooMode
                                ? AppLocalizations.of(
                                        context,
                                      )?.signInToStartDelivering ??
                                      'Sign in to start delivering'
                                : 'Sign in to your seller account',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.5),
                            ),
                          ),

                          SizedBox(height: isDesktop ? 40 : 36),

                          // Email Input — email/username is always stored
                          // lowercase on the backend, so we force lowercase
                          // here to stop "Invalid password" errors caused by
                          // capitalisation on iOS autocapitalise.
                          _buildInputField(
                            controller: _emailController,
                            hint:
                                AppLocalizations.of(context)?.emailOrUsername ??
                                'Email or Username',
                            isLight: isLight,
                            height: inputHeight,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            forceLowercase: true,
                          ),

                          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                          // Password Input
                          _buildInputField(
                            controller: _passwordController,
                            hint:
                                AppLocalizations.of(context)?.password ??
                                'Password',
                            isLight: isLight,
                            height: inputHeight,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _login(),
                          ),

                          const SizedBox(height: 14),

                          // Forgot Password
                          Align(
                            alignment: Alignment.centerRight,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: TradeRepublicTap(
                                onTap: _showForgotPasswordModal,
                                child: Text(
                                  AppLocalizations.of(
                                        context,
                                      )?.forgotPasswordQuestion ??
                                      'Forgot password?',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color:
                                        (isLight ? Colors.black : Colors.white)
                                            .withOpacity(0.45),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                          // Sign In Button
                          _buildPrimaryButton(
                            label:
                                AppLocalizations.of(context)?.signIn ??
                                'Sign In',
                            onPressed: _isLoading ? null : _login,
                            isLoading: _isLoading,
                            isLight: isLight,
                            height: buttonHeight,
                            isDesktop: isDesktop,
                          ),

                          const SizedBox(height: 28),

                          // Divider with OR
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  height: 1,
                                  color: (isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.08),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Text(
                                  AppLocalizations.of(context)?.orLabel ?? 'or',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color:
                                        (isLight ? Colors.black : Colors.white)
                                            .withOpacity(0.3),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  height: 1,
                                  color: (isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.08),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 28),

                          // Social Sign In Buttons
                          Row(
                            children: [
                              // Google
                              Expanded(
                                child: _buildSocialButton(
                                  onTap: _isLoading ? null : _signInWithGoogle,
                                  icon: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: SvgPicture.string(
                                      '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path fill="currentColor" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/><path fill="currentColor" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/><path fill="currentColor" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/><path fill="currentColor" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/></svg>',
                                      color: isLight ? Colors.black : Colors.white,
                                    ),
                                  ),
                                  label: isDesktop
                                      ? (AppLocalizations.of(context)?.googleLabel ?? '')
                                      : null,
                                  isLight: isLight,
                                  height: buttonHeight,
                                ),
                              ),
                              // Apple (iOS only)
                              if (_isIOS) ...[
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildSocialButton(
                                    onTap: _isLoading ? null : _signInWithApple,
                                    icon: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: SvgPicture.string(
                                        '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path fill="currentColor" d="M17.05 13.5c-.91 0-1.82.55-2.25 1.51.93.64 1.54 1.77 1.54 3.02 0 2.05-1.53 3.76-3.41 3.76-1.9 0-3.44-1.71-3.44-3.76 0-1.25.61-2.38 1.54-3.02-.43-.96-1.34-1.51-2.25-1.51-2.06 0-3.71 1.88-3.71 4.2 0 2.33 1.65 4.2 3.71 4.2 1.06 0 2.05-.41 2.8-1.12.75.71 1.74 1.12 2.8 1.12 2.06 0 3.71-1.87 3.71-4.2 0-2.32-1.65-4.2-3.71-4.2zm-5.14-2.5c0 1.38-1.12 2.5-2.5 2.5s-2.5-1.12-2.5-2.5 1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5zm5 0c0 1.38-1.12 2.5-2.5 2.5s-2.5-1.12-2.5-2.5 1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5z"/></svg>',
                                        color: isLight ? Colors.black : Colors.white,
                                      ),
                                    ),
                                    label: isDesktop
                                        ? (AppLocalizations.of(context)?.appleLabel ?? '')
                                        : null,
                                    isLight: isLight,
                                    height: buttonHeight,
                                  ),
                                ),
                              ],
                            ],
                          ),

                          const SizedBox(height: 36),

                          // Register Section
                          Column(
                            children: [
                              Text(
                                _isDelviooMode
                                    ? AppLocalizations.of(
                                            context,
                                          )?.dontHaveAccountSignUp ??
                                          "Don't have an account?"
                                    : "Don't have a seller account?",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: (isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.45),
                                ),
                              ),
                              SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                              _buildSecondaryButton(
                                label: _isDelviooMode
                                    ? AppLocalizations.of(
                                            context,
                                          )?.becomeADriver ??
                                          'Become a Driver'
                                    : 'Create Seller Account',
                                onPressed: () {
                                  if (_isDelviooMode) {
                                    Navigator.pushNamed(
                                      context,
                                      '/driver-registration',
                                    );
                                  } else {
                                    Navigator.pushNamed(context, '/register');
                                  }
                                },
                                isLight: isLight,
                                height: buttonHeight - 4,
                                isDesktop: isDesktop,
                              ),
                            ],
                          ),

                          // Bottom spacing
                          SizedBox(height: isMobile ? (_isIOS ? 60 : 40) : 40),
                        ],
                      ),
                    ),
                  ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Mode selection screen — shown before login with logo + compelling cards
  Widget _buildModeSelectionScreen(
    bool isLight,
    bool isDesktop,
    bool isMobile,
    double screenHeight,
  ) {
    final maxFormWidth = isDesktop ? 500.0 : double.infinity;
    final horizontalPadding = isDesktop ? 0.0 : 28.0;

    // Animate out when a mode is selected
    final fadeOut = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _modeTransitionController, curve: Curves.easeIn),
    );
    final scaleOut = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _modeTransitionController, curve: Curves.easeIn),
    );

    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: isLight ? Colors.white : Colors.black,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: FadeTransition(
          opacity: fadeOut,
          child: ScaleTransition(
            scale: scaleOut,
            child: Center(
              child: Container(
                constraints: BoxConstraints(maxWidth: maxFormWidth),
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: Column(
                  children: [
                    // Spacer pushes cards to center
                    const Spacer(),

                    // Subtitle — "How would you like to start?"
                    SlideTransition(
                      position: _slideAnimation,
                      child: Text(
                        AppLocalizations.of(context)?.chooseAccountType ??
                            'How do you want to get started?',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: isLight ? Colors.black : Colors.white,
                          letterSpacing: -0.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                    const SizedBox(height: 36),

                    // Business Card
                    _buildModeCard(
                      isLight: isLight,
                      icon: CupertinoIcons.briefcase_fill,
                      title:
                          AppLocalizations.of(context)?.businessLabel ??
                          'Business',
                      subtitle:
                          AppLocalizations.of(
                            context,
                          )?.businessModeDescription ??
                          'Sell at YOUR price. We give customers the freedom.',
                      delay: 0,
                      onTap: () => _selectMode(0),
                    ),

                    SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                    // Delvioo Card
                    _buildModeCard(
                      isLight: isLight,
                      icon: CupertinoIcons.cube_box_fill,
                      title:
                          AppLocalizations.of(context)?.delviooLabel ??
                          'Delvioo',
                      subtitle:
                          AppLocalizations.of(
                            context,
                          )?.delviooModeDescription ??
                          'Drive. Deliver. Earn. On your terms.',
                      delay: 1,
                      onTap: () => _selectMode(1),
                    ),

                    // Spacer at bottom for balance
                    const Spacer(),

                    SizedBox(height: isMobile ? 30 : 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A single mode selection card with staggered slide-in animation
  Widget _buildModeCard({
    required bool isLight,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    int delay = 0,
  }) {
    // Stagger the card animations
    final staggeredSlide =
        Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _slideController,
            curve: Interval(delay * 0.15, 1.0, curve: Curves.easeOut),
          ),
        );

    return SlideTransition(
      position: staggeredSlide,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: TradeRepublicTap(
            onTap: onTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: (isLight ? Colors.black : Colors.white).withOpacity(
                  0.04,
                ),
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              ),
              child: Row(
                children: [
                  // Icon
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: isLight ? Colors.black : Colors.white,
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius()),
                    ),
                    child: Icon(
                      icon,
                      size: 24,
                      color: isLight ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(width: 18),
                  // Text
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                            fontWeight: FontWeight.w600,
                            color: isLight ? Colors.black : Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.5),
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Arrow
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 18,
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required bool isLight,
    required double height,
    bool obscureText = false,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    Function(String)? onSubmitted,
    bool forceLowercase = false,
  }) {
    final inputTextColor = isLight ? Colors.black : Colors.white;
    return TradeRepublicTextField(
      controller: controller,
      obscureText: obscureText,
      showVisibilityToggle: obscureText,
      suffixIcon: obscureText ? null : const IgnorePointer(child: Icon(CupertinoIcons.eye_slash, size: 18, color: Colors.transparent)),
      hintText: hint,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      textCapitalization: forceLowercase ? TextCapitalization.none : TextCapitalization.none,
      inputFormatters: forceLowercase ? [TextInputFormatter.withFunction((oldValue, newValue) {
        final lowered = newValue.text.toLowerCase();
        if (lowered == newValue.text) return newValue;
        return TextEditingValue(text: lowered, selection: newValue.selection, composing: TextRange.empty);
      })] : null,
      style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize(), fontWeight: FontWeight.w500, color: inputTextColor, height: 1.0),
      hintStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: inputTextColor.withOpacity(0.4), height: 1.0),
      fillColor: isLight ? Colors.black.withOpacity(0.05) : const Color(0xFF111111),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required VoidCallback? onPressed,
    required bool isLoading,
    required bool isLight,
    required double height,
    required bool isDesktop,
  }) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: TradeRepublicButton(
        label: label,
        onPressed: onPressed,
        isLoading: isLoading,
      ),
    );
  }

  Widget _buildSecondaryButton({
    required String label,
    required VoidCallback onPressed,
    required bool isLight,
    required double height,
    required bool isDesktop,
  }) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: TradeRepublicButton(
        label: label,
        onPressed: onPressed,
        isSecondary: true,
      ),
    );
  }

  Widget _buildSocialButton({
    required VoidCallback? onTap,
    required Widget icon,
    String? label,
    required bool isLight,
    required double height,
  }) {
    return MouseRegion(
      cursor: onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: TradeRepublicTap(
        onTap: onTap,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: (isLight ? Colors.black : Colors.white).withOpacity(0.04),
            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              if (label != null) ...[
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w500,
                    color: isLight ? Colors.black : Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showUpgradeModal() {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final isLight = appSettings.isLightMode(context);

    TradeRepublicBottomSheet.show(
      context: context,
      enableDrag: true,
      isDismissible: true,
      child: _buildEmailVerificationModal(isLight),
    );
  }

  Widget _buildUpgradeField(
    String label,
    String hint,
    IconData icon,
    TextEditingController controller,
    bool isLight,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: DesktopOptimizedWidgets.getFontSize(),
            fontWeight: FontWeight.w600,
            color: isLight ? Colors.black : Colors.white,
          ),
        ),
        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
        TradeRepublicTextField(
          controller: controller,
          hintText: hint,
          prefixIcon: Icon(icon),
        ),
      ],
    );
  }

  Future<void> _processBusinessUpgrade(
    String businessName,
    String businessWebsite,
    String street,
    String houseNumber,
    String state,
    String city,
    String country,
    String businessSize,
    String zipCode,
  ) async {
    print('DEBUG: Business Name value: "$businessName"');
    print('DEBUG: Business Name length: ${businessName.length}');

    if (businessName.isEmpty) {
      print('⚠️ Please enter your business name');
      return;
    }

    // Create full address from components - USA format
    final fullAddress = [
      if (street.isNotEmpty) street,
      if (houseNumber.isNotEmpty) houseNumber,
      if (city.isNotEmpty) city,
      if (state.isNotEmpty) state,
      if (zipCode.isNotEmpty) zipCode,
      if (country.isNotEmpty) country,
    ].join(', ');

    setState(() => _isLoading = true);

    try {
      // Prepare request data - use verified email
      final userEmail = _verifiedEmail ?? _emailController.text.trim();

      if (userEmail.isEmpty) {
        print('⚠️ Email verification required');
        return;
      }

      if (_businessUpgradeVerificationToken == null ||
          _businessUpgradeVerificationToken!.isEmpty) {
        print('⚠️ Please verify your email first');
        return;
      }

      final requestData = {
        'email': userEmail,
        'businessName': businessName,
        // businessEmail and businessPhone are taken from user account
        'businessWebsite': businessWebsite.isNotEmpty ? businessWebsite : null,
        'businessAddress': fullAddress,
        'street': street,
        'houseNumber': houseNumber,
        'state': state,
        'city': city,
        'zipCode': zipCode,
        'country': country,
        'businessSize': businessSize,
        'verificationToken': _businessUpgradeVerificationToken,
        'hasBusinessLogo': _selectedBusinessImage != null,
      };

      // Send upgrade request to backend
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/business/upgrade'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestData),
      );

      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.of(context).pop(); // Close modal

        if (response.statusCode == 200) {
          final responseData = json.decode(response.body);
          if (responseData['success'] == true) {
            // Show success bottom sheet
            TradeRepublicBottomSheet.show(
              context: context,
              enableDrag: true,
              isDismissible: true,
              child: Builder(
                builder: (context) {
                  final AppSettings appSettings = AppSettings();
                  final isLight = appSettings.isLightMode(context);

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DragHandle(),
                      // ── Sheet header: Icon left + Title ──
                      Row(
                        children: [
                          Icon(
                            CupertinoIcons.checkmark_circle_fill,
                            size: 22,
                            color: isLight ? Colors.black : Colors.white,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              AppLocalizations.of(context)?.upgradeSuccessful ??
                                  'Upgrade Successful!',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Colors.green,
                                letterSpacing: -0.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                      Text(
                        AppLocalizations.of(
                              context,
                            )?.businessUpgradeSubmitted ??
                            'Your business upgrade request has been submitted. You can now login with your business account.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.7),
                        ),
                      ),
                      SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                      SizedBox(
                        width: double.infinity,
                        child: Platform.isIOS
                            ? TradeRepublicButton(
                                label:
                                    AppLocalizations.of(
                                      context,
                                    )?.continueToLogin ??
                                    'Continue to Login',
                                onPressed: () {
                                  Navigator.of(context).pop();
                                },
                              )
                            : TradeRepublicButton(
                                label:
                                    AppLocalizations.of(
                                      context,
                                    )?.continueToLogin ??
                                    'Continue to Login',
                                backgroundColor: Colors.green,
                                onPressed: () {
                                  Navigator.of(context).pop();
                                },
                              ),
                      ),
                      SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                    ],
                  );
                },
              ),
            );
          } else {
            print('❌ Upgrade failed: ${responseData['message']}');
          }
        } else {
          print('❌ Upgrade request failed');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.of(context).pop(); // Close modal
        print('❌ Connection error: $e');
      }
    }
  }

  Future<void> _selectBusinessImage(StateSetter setModalState) async {
    TradeRepublicBottomSheet.show(
      context: context,
      child: Builder(
        builder: (context) {
          final appSettings = Provider.of<AppSettings>(context, listen: false);
          final isLight = appSettings.isLightMode(context);

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DragHandle(),
              // ── Sheet header: Icon left + Title ──
              Row(
                children: [
                  Icon(
                    CupertinoIcons.camera_fill,
                    size: 22,
                    color: isLight ? Colors.black : Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    AppLocalizations.of(context)?.selectBusinessLogo ??
                        'Select Business Logo',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: isLight ? Colors.black : Colors.white,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: TradeRepublicTap(
                      onTap: () async {
                        Navigator.pop(context);
                        await _pickImageFromSource(
                          ImageSource.camera,
                          setModalState,
                        );
                      },
                      child: Container(
                        padding: DesktopAppWrapper.getPagePadding(),
                        decoration: BoxDecoration(
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              CupertinoIcons.camera_fill,
                              size: 40,
                              color: isLight ? Colors.black : Colors.white,
                            ),
                            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                            Text(
                              AppLocalizations.of(context)?.camera ?? 'Camera',
                              style: TextStyle(
                                color: isLight ? Colors.black : Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TradeRepublicTap(
                      onTap: () async {
                        Navigator.pop(context);
                        await _pickImageFromSource(
                          ImageSource.gallery,
                          setModalState,
                        );
                      },
                      child: Container(
                        padding: DesktopAppWrapper.getPagePadding(),
                        decoration: BoxDecoration(
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              CupertinoIcons.photo_fill_on_rectangle_fill,
                              size: 40,
                              color: isLight ? Colors.black : Colors.white,
                            ),
                            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                            Text(
                              AppLocalizations.of(context)?.gallery ??
                                  'Gallery',
                              style: TextStyle(
                                color: isLight ? Colors.black : Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickImageFromSource(
    ImageSource source,
    StateSetter setModalState,
  ) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1024,
        maxHeight: 1024,
      );

      if (image != null) {
        setModalState(() {
          _selectedBusinessImage = File(image.path);
        });

        TopNotification.success(
          context,
          'Business logo selected successfully!',
        );
      }
    } catch (e) {
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.errorSelectingImage ?? "Error selecting image"}: $e',
      );
    }
  }

  void _showCountrySelection(
    StateSetter setModalState,
    String currentCountry,
    Function(String) onCountrySelected,
  ) {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final isLight = appSettings.isLightMode(context);

    final countries = [
      // North America
      {'name': 'United States', 'code': 'US', 'flag': '🇺🇸'},
      {'name': 'Canada', 'code': 'CA', 'flag': '🇨🇦'},
      {'name': 'Mexico', 'code': 'MX', 'flag': '🇲🇽'},
      // EU Countries
      {'name': 'Germany', 'code': 'DE', 'flag': '🇩🇪'},
      {'name': 'Austria', 'code': 'AT', 'flag': '🇦🇹'},
      {'name': 'France', 'code': 'FR', 'flag': '🇫🇷'},
      {'name': 'Italy', 'code': 'IT', 'flag': '🇮🇹'},
      {'name': 'Spain', 'code': 'ES', 'flag': '🇪🇸'},
      {'name': 'Netherlands', 'code': 'NL', 'flag': '🇳🇱'},
      {'name': 'Belgium', 'code': 'BE', 'flag': '🇧🇪'},
      {'name': 'Poland', 'code': 'PL', 'flag': '🇵🇱'},
      // Russia
      {'name': 'Russia', 'code': 'RU', 'flag': '🇷🇺'},
    ];

    TradeRepublicBottomSheet.show(
      context: context,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.4,
        child: Column(
          children: [
            DragHandle(),
            // ── Sheet header: Icon left + Title ──
            Row(
              children: [
                Icon(
                  CupertinoIcons.globe,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white,
                ),
                const SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)?.selectCountry ?? 'Select Country',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

            Expanded(
              child: ListView.builder(
                itemCount: countries.length,
                itemBuilder: (context, index) {
                  final country = countries[index];
                  final isSelected = country['name'] == currentCountry;

                  return TradeRepublicTap(
                    onTap: () {
                      Navigator.pop(context);
                      onCountrySelected(country['name']!);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: DesktopAppWrapper.getPagePadding(),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.15)
                            : (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.04),
                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                      ),
                      child: Row(
                        children: [
                          // Flag emoji
                          Text(
                            country['flag']!,
                            style: const TextStyle(fontSize: 28),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              country['name']!,
                              style: TextStyle(
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                                color: isLight ? Colors.black : Colors.white,
                              ),
                            ),
                          ),
                          if (isSelected)
                            Icon(
                              CupertinoIcons.checkmark_circle_fill,
                              color: isLight ? Colors.black : Colors.white,
                              size: 24,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBusinessSizeSelection(
    StateSetter setModalState,
    String currentSize,
    Function(String) onSizeSelected,
  ) {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final isLight = appSettings.isLightMode(context);

    final sizeOptions = [
      {'size': '1-10 employees', 'icon': CupertinoIcons.bag_fill},
      {'size': '11-50 employees', 'icon': CupertinoIcons.building_2_fill},
      {'size': '51-100 employees', 'icon': CupertinoIcons.building_2_fill},
      {'size': '101-500 employees', 'icon': CupertinoIcons.building_2_fill},
      {'size': '500+ employees', 'icon': CupertinoIcons.briefcase_fill},
    ];

    TradeRepublicBottomSheet.show(
      context: context,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            DragHandle(),
            // ── Sheet header: Icon left + Title ──
            Row(
              children: [
                Icon(
                  CupertinoIcons.briefcase_fill,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)?.selectBusinessSize ??
                        'Select Business Size',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: isLight ? Colors.black : Colors.white,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

            Expanded(
              child: ListView.builder(
                itemCount: sizeOptions.length,
                itemBuilder: (context, index) {
                  final option = sizeOptions[index];
                  final isSelected = option['size'] == currentSize;

                  return TradeRepublicTap(
                    onTap: () {
                      Navigator.pop(context);
                      onSizeSelected(option['size'] as String);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: DesktopAppWrapper.getPagePadding(),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.15)
                            : (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.04),
                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            option['icon'] as IconData,
                            color: isLight ? Colors.black : Colors.white,
                            size: 24,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              option['size'] as String,
                              style: TextStyle(
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                                color: isLight ? Colors.black : Colors.white,
                              ),
                            ),
                          ),
                          if (isSelected)
                            Icon(
                              Icons.check_circle,
                              color: isLight ? Colors.black : Colors.white,
                              size: 24,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Email Verification Modal - Step 1 of Business Upgrade
  Widget _buildEmailVerificationModal(bool isLight) {
    // Initialize controller text if empty
    if (_emailVerificationController.text.isEmpty) {
      _emailVerificationController.text = _emailController.text.trim();
    }

    bool isSending = false;

    return StatefulBuilder(
      builder: (context, setModalState) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              children: [
                DragHandle(),

                // Scrollable content
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        // Header Icon
                        Container(
                          padding: DesktopAppWrapper.getPagePadding(),
                          decoration: BoxDecoration(
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.1),
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          ),
                          child: Icon(
                            CupertinoIcons.mail,
                            size: 40,
                            color: isLight ? Colors.black : Colors.white,
                          ),
                        ),
                        SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                        Text(
                          AppLocalizations.of(context)?.emailVerification ??
                              'Email Verification',
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize() + 10,
                            fontWeight: FontWeight.w700,
                            color: isLight ? Colors.black : Colors.white,
                          ),
                        ),
                        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                        Text(
                          AppLocalizations.of(
                                context,
                              )?.verifyEmailBeforeUpgrade ??
                              'We need to verify your email address before upgrading to a business account',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.7),
                          ),
                        ),
                        SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                        // Email Input Field
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.of(context)?.emailAddress ??
                                  'Email Address',
                              style: TextStyle(
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                fontWeight: FontWeight.w600,
                                color: isLight ? Colors.black : Colors.white,
                              ),
                            ),
                            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                            TradeRepublicTextField(
                              controller: _emailVerificationController,
                              hintText:
                                  AppLocalizations.of(
                                    context,
                                  )?.enterYourEmailAddress ??
                                  'Enter your email address',
                              prefixIcon: const Icon(CupertinoIcons.mail_solid),
                              keyboardType: TextInputType.emailAddress,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Fixed bottom buttons
                Column(
                  children: [
                    // Send Email Button
                    TradeRepublicButton(
                      label: isSending
                          ? AppLocalizations.of(context)?.sendingCode ??
                                'Sending Code...'
                          : AppLocalizations.of(
                                  context,
                                )?.sendVerificationCode ??
                                'Send Verification Code',
                      onPressed: isSending
                          ? null
                          : () async {
                              final email = _emailVerificationController.text
                                  .trim();
                              if (email.isEmpty) {
                                print('⚠️ Please enter your email address');
                                return;
                              }

                              setModalState(() => isSending = true);

                              _businessUpgradeVerificationToken = null;

                              try {
                                await _sendVerificationCode(email);
                                // Only close current modal and show code input modal if email was sent successfully
                                if (mounted) {
                                  Navigator.of(context).pop();
                                  _showCodeInputModal(email);
                                }
                              } catch (e) {
                                print('❌ Error: ${e.toString().replaceAll('Exception: ', '')}');
                              } finally {
                                if (mounted) {
                                  setModalState(() => isSending = false);
                                }
                              }
                            },
                    ),
                    SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                    // Cancel Button
                    Platform.isIOS
                        ? TradeRepublicButton(
                            label:
                                AppLocalizations.of(context)?.cancel ??
                                'Cancel',
                            onPressed: () => Navigator.of(context).pop(),
                          )
                        : TradeRepublicButton(
                            label:
                                AppLocalizations.of(context)?.cancel ??
                                'Cancel',
                            isSecondary: true,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                    SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Code Input Modal - Step 2 of Email Verification
  void _showCodeInputModal(String email) {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final isLight = appSettings.isLightMode(context);

    TradeRepublicBottomSheet.show(
      context: context,
      enableDrag: true,
      isDismissible: true,
      child: _buildCodeInputModal(email, isLight),
    );
  }

  Widget _buildCodeInputModal(String email, bool isLight) {
    final codeController = TextEditingController();
    bool isVerifying = false;
    bool canResend = false;
    int countdownSeconds = 60;
    Timer? countdownTimer;

    return StatefulBuilder(
      builder: (context, setModalState) {
        // Start countdown timer with proper cleanup
        if (countdownSeconds > 0 && !canResend && countdownTimer == null) {
          countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
            if (!context.mounted) {
              timer.cancel();
              return;
            }
            if (countdownSeconds > 0) {
              setModalState(() => countdownSeconds--);
              if (countdownSeconds == 0) {
                setModalState(() => canResend = true);
                timer.cancel();
              }
            } else {
              timer.cancel();
            }
          });
        }

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            left: 4,
            right: 4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DragHandle(),

              Row(
                children: [
                  Icon(CupertinoIcons.checkmark_seal_fill, size: 22, color: isLight ? Colors.black : Colors.white),
                  const SizedBox(width: 12),
                  Flexible(child: Text(
                    AppLocalizations.of(context)?.enterVerificationCode ?? 'Enter Verification Code',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                      color: isLight ? Colors.black : Colors.white, letterSpacing: -0.4),
                  )),
                ],
              ),

              // Scrollable content
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                      Text(
                        AppLocalizations.of(context)?.weSentVerificationCode ??
                            'We sent an 8-digit verification code to',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(height: 4),

                      Text(
                        email,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Verification Code Input
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            AppLocalizations.of(context)?.verificationCode ??
                                'Verification Code',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.6),
                            ),
                          ),
                        ),
                      ),
                      TradeRepublicTextField.code(
                        controller: codeController,
                        hintText: '00000000',
                        maxLength: 8,
                        autofocus: true,
                      ),
                      const SizedBox(height: 20),

                      // Resend row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            AppLocalizations.of(context)?.didntReceiveCode ??
                                "Didn't receive the code?",
                            style: TextStyle(
                              fontSize: DesktopOptimizedWidgets.getFontSize(),
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.5),
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (!canResend)
                            Text(
                              '${countdownSeconds}s',
                              style: TextStyle(
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                fontWeight: FontWeight.w600,
                                color: (isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.35),
                              ),
                            )
                          else
                            TradeRepublicTap(
                              onTap: () async {
                                setModalState(() {
                                  canResend = false;
                                  countdownSeconds = 60;
                                  countdownTimer = null;
                                });
                                await _sendVerificationCode(email);
                              },
                              child: Text(
                                AppLocalizations.of(context)?.sendNewCode ??
                                    'Resend',
                                style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize(),
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Verify Button
              TradeRepublicButton(
                label: isVerifying
                    ? AppLocalizations.of(context)?.verifying ?? 'Verifying...'
                    : AppLocalizations.of(context)?.verifyCode ?? 'Verify Code',
                onPressed: isVerifying
                    ? null
                    : () async {
                        final code = codeController.text.trim();
                        if (code.length != 8) {
                          print('⚠️ Please enter the complete 8-digit code');
                          return;
                        }

                        setModalState(() => isVerifying = true);

                        try {
                          final success = await _verifyCode(email, code);
                          if (success) {
                            setState(() => _verifiedEmail = email);
                            Navigator.of(context).pop();
                            _showBusinessDetailsModal();
                          }
                        } catch (e) {
                          print('❌ Failed to verify code');
                        } finally {
                          setModalState(() => isVerifying = false);
                        }
                      },
              ),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

              TradeRepublicButton(
                label:
                    AppLocalizations.of(context)?.backToEmail ?? 'Back to Email',
                isSecondary: true,
                onPressed: () {
                  Navigator.of(context).pop();
                  _showUpgradeModal();
                },
              ),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
            ],
          ),
        );
      },
    );
  }

  void _showBusinessDetailsModal() {
    TradeRepublicBottomSheet.show(
      context: context,
      enableDrag: true,
      isDismissible: true,
      child: _buildBusinessDetailsModal(),
    );
  }

  Widget _buildBusinessDetailsModal() {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final isLight = appSettings.isLightMode(context);

    // Pre-fill email from login form
    _businessEmailController.text = _emailController.text.trim();

    return StatefulBuilder(
      builder: (context, setModalState) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DragHandle(),
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.briefcase_fill,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.businessDetails ?? 'Business Details',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Form - Flexible height
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Business Logo Section
                  _buildBusinessLogoSection(setModalState, isLight),
                  const SizedBox(height: 20),

                  // Business Name
                  _buildBusinessField(
                    icon: CupertinoIcons.briefcase_fill,
                    title:
                        AppLocalizations.of(context)?.businessName ??
                        'Business Name',
                    subtitle: '*',
                    controller: _businessNameController,
                    hint:
                        AppLocalizations.of(context)?.enterYourBusinessName ??
                        'Enter your business name',
                    isLight: isLight,
                  ),

                  // Business Description
                  _buildBusinessField(
                    icon: CupertinoIcons.doc_text_fill,
                    title:
                        AppLocalizations.of(context)?.businessDescription ??
                        'Business Description',
                    subtitle:
                        AppLocalizations.of(context)?.optional ?? 'Optional',
                    controller: _businessDescriptionController,
                    hint:
                        AppLocalizations.of(context)?.describeYourBusiness ??
                        'Describe your business...',
                    isLight: isLight,
                  ),

                  // Business Website
                  _buildBusinessField(
                    icon: CupertinoIcons.globe,
                    title:
                        AppLocalizations.of(context)?.businessWebsite ??
                        'Business Website',
                    subtitle:
                        AppLocalizations.of(context)?.optional ?? 'Optional',
                    controller: _businessWebsiteController,
                    hint: 'https://example.com',
                    isLight: isLight,
                  ),

                  // Tax Information Section Header
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      children: [
                        Icon(
                          CupertinoIcons.doc_text,
                          size: 20,
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.7),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(context)?.taxInformation ??
                              'Tax Information',
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                            fontWeight: FontWeight.w600,
                            color: isLight ? Colors.black : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Tax and VAT Numbers - same height containers
                  Row(
                    children: [
                      Expanded(
                        child: _buildBusinessField(
                          icon: CupertinoIcons.doc,
                          title:
                              AppLocalizations.of(context)?.taxNumber ??
                              'Tax Number',
                          subtitle:
                              AppLocalizations.of(context)?.optional ??
                              'Optional',
                          controller: _taxNumberController,
                          hint: AppLocalizations.of(context)?.taxId ?? 'Tax ID',
                          isLight: isLight,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildBusinessField(
                          icon: CupertinoIcons.doc_text,
                          title:
                              AppLocalizations.of(context)?.vatNumber ??
                              'VAT Number',
                          subtitle:
                              AppLocalizations.of(context)?.optional ??
                              'Optional',
                          controller: _vatNumberController,
                          hint: AppLocalizations.of(context)?.vatId ?? 'VAT ID',
                          isLight: isLight,
                        ),
                      ),
                    ],
                  ),

                  // Address Section Header
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      children: [
                        Icon(
                          CupertinoIcons.location_fill,
                          size: 20,
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.7),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(context)?.businessAddressLabel ??
                              'Business Address',
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                            fontWeight: FontWeight.w600,
                            color: isLight ? Colors.black : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Street and Number - better proportions
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _buildBusinessField(
                          icon: CupertinoIcons.location,
                          title:
                              AppLocalizations.of(context)?.street ?? 'Street',
                          subtitle: '*',
                          controller: _streetController,
                          hint:
                              AppLocalizations.of(context)?.streetName ??
                              'Street name',
                          isLight: isLight,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2, // Made wider as requested
                        child: _buildBusinessField(
                          icon: CupertinoIcons.house_fill,
                          title: AppLocalizations.of(context)?.nr ?? 'Nr.',
                          subtitle: '*',
                          controller: _houseNumberController,
                          hint: '123',
                          isLight: isLight,
                        ),
                      ),
                    ],
                  ),

                  // City and State - same height containers
                  Row(
                    children: [
                      Expanded(
                        child: _buildBusinessField(
                          icon: CupertinoIcons.building_2_fill,
                          title: AppLocalizations.of(context)?.city ?? 'City',
                          subtitle: '*',
                          controller: _cityController,
                          hint:
                              AppLocalizations.of(context)?.cityName ??
                              'City name',
                          isLight: isLight,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildBusinessField(
                          icon: CupertinoIcons.map_fill,
                          title: AppLocalizations.of(context)?.state ?? 'State',
                          subtitle: '*',
                          controller: _stateController,
                          hint:
                              AppLocalizations.of(context)?.stateProvince ??
                              'State/Province',
                          isLight: isLight,
                        ),
                      ),
                    ],
                  ),

                  // ZIP and Country - same height containers
                  Row(
                    children: [
                      Expanded(
                        child: _buildBusinessField(
                          icon: CupertinoIcons.envelope_fill,
                          title:
                              AppLocalizations.of(context)?.zipCode ??
                              'ZIP Code',
                          subtitle: '*',
                          controller: _zipCodeController,
                          hint: '12345',
                          isLight: isLight,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildCountrySelector(setModalState, isLight),
                      ),
                    ],
                  ),

                  // Business Size Selector - same height
                  _buildBusinessSizeSelector(setModalState, isLight),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: TradeRepublicButton(
                  label: AppLocalizations.of(context)?.cancel ?? 'Cancel',
                  isSecondary: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: TradeRepublicButton(
                  label: _isLoading
                      ? AppLocalizations.of(context)?.creating ?? 'Creating...'
                      : AppLocalizations.of(context)?.createBusiness ??
                            'Create Business',
                  onPressed: _isLoading
                      ? null
                      : () => _processBusinessUpgrade(
                          _businessNameController.text.trim(),
                          _businessWebsiteController.text.trim(),
                          _streetController.text.trim(),
                          _houseNumberController.text.trim(),
                          _stateController.text.trim(),
                          _cityController.text.trim(),
                          _selectedCountry,
                          _selectedSize,
                          _zipCodeController.text.trim(),
                        ),
                ),
              ),
            ],
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
        ],
      ),
    );
  }

  // Helper methods for verification process
  Future<void> _sendVerificationCode(String email) async {
    try {
      print('📧 Sending verification code to: $email');
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/business/send-verification'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'email': email}),
          )
          .timeout(const Duration(seconds: 15));

      print('📧 Response status: ${response.statusCode}');
      print('📧 Response body: ${response.body}');

      final responseData = json.decode(response.body);

      print('📧 Response data keys: ${responseData.keys.toList()}');
      print('📧 alreadyBusiness value: ${responseData['alreadyBusiness']}');

      if (response.statusCode == 200 && responseData['success'] == true) {
        // Check if user is already a business
        if (responseData['alreadyBusiness'] == true) {
          print('⚠️ User is already a business account');
          throw Exception(
            'This email is already registered as a Business account. Please log in instead.',
          );
        }

        final userName = responseData['userName'] ?? '';
        print('✅ Verification code sent successfully');
        TopNotification.success(
          context,
          'Verification code sent to $email${userName.isNotEmpty ? ' ($userName)' : ''}!',
        );
      } else if (response.statusCode == 404) {
        print('❌ No account found for email: $email');
        throw Exception(
          AppLocalizations.of(context)?.noAccountFoundWithEmailAddress ??
              'No account found with this email address. Please check the email or create an account first.',
        );
      } else {
        print('❌ Failed to send verification code: ${responseData['message']}');
        throw Exception(
          responseData['message'] ??
              AppLocalizations.of(context)?.failedToSendVerificationCode ??
              'Failed to send verification code',
        );
      }
    } catch (e) {
      print('❌ Error sending verification code: $e');
      rethrow; // Re-throw to be caught by the button's error handler
    }
  }

  Future<bool> _verifyCode(String email, String code) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/business/verify-code'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email, 'code': code}),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          _businessUpgradeVerificationToken =
              responseData['verificationToken']?.toString();
          return true;
        } else {
          print('❌ Invalid verification code: ${responseData['message']}');
          return false;
        }
      } else {
        print('❌ Verification failed');
        return false;
      }
    } catch (e) {
      print('❌ Connection error: $e');
      return false;
    }
  }

  // Build helper widgets with country flags
  Widget _buildCountrySelector(StateSetter setModalState, bool isLight) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              '${AppLocalizations.of(context)?.country ?? 'Country'} *',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.6),
              ),
            ),
          ),
          TradeRepublicTap(
            onTap: () => _showCountrySelection(
              setModalState,
              _selectedCountry,
              (country) {
                setModalState(() => _selectedCountry = country);
              },
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isLight
                    ? Colors.black.withOpacity(0.04)
                    : const Color(0xFF111111),
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                    child: Text(
                      _countryToFlag(_selectedCountry),
                      style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize() + 6,,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedCountry,
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.expand_more,
                    color: (isLight ? Colors.black : Colors.white)
                        .withOpacity(0.5),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessSizeSelector(StateSetter setModalState, bool isLight) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              '${AppLocalizations.of(context)?.businessSize ?? 'Business Size'} *',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.6),
              ),
            ),
          ),
          TradeRepublicTap(
            onTap: () => _showBusinessSizeSelection(
              setModalState,
              _selectedSize,
              (size) {
                setModalState(() => _selectedSize = size);
              },
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isLight
                    ? Colors.black.withOpacity(0.04)
                    : const Color(0xFF111111),
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              ),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.building_2_fill,
                    size: 18,
                    color: (isLight ? Colors.black : Colors.white)
                        .withOpacity(0.5),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedSize,
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.expand_more,
                    color: (isLight ? Colors.black : Colors.white)
                        .withOpacity(0.5),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Business Detail Modal Helper Methods
  Widget _buildBusinessLogoSection(StateSetter setModalState, bool isLight) {
    return Column(
      children: [
        TradeRepublicTap(
          onTap: () => _selectBusinessImage(setModalState),
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: isLight
                  ? Colors.black.withOpacity(0.05)
                  : const Color(0xFF121212),
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            ),
            child: _selectedBusinessImage != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                    child: Image.file(
                      _selectedBusinessImage!,
                      fit: BoxFit.cover,
                    ),
                  )
                : Icon(
                    CupertinoIcons.photo,
                    size: 28,
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.5,
                    ),
                  ),
          ),
        ),
        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
        Text(
          AppLocalizations.of(context)?.businessLogoOptional ??
              'Business Logo (Optional)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildBusinessField({
    required IconData icon,
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required String hint,
    required bool isLight,
  }) {
    final bool isRequired = subtitle == '*';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TradeRepublicTextField.withLabel(
        label: isRequired
          ? '$title ${String.fromCharCode(42)}'
          : title,
        controller: controller,
        hintText: hint,
        fillColor: isLight
            ? Colors.black.withOpacity(0.04)
            : const Color(0xFF111111),
      ),
    );
  }

  // 📧 NEW: Email verification modal for Delvioo users after 2FA
  void _showDelviooEmailVerificationModal({
    required String email,
    required String userId,
    required AppSettings userProvider,
    required NavigatorState navigatorContext,
  }) async {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final isLight = appSettings.isLightMode(context);
    final emailCodeController = TextEditingController();
    bool isVerifying = false;
    bool isSendingCode = false;

    // Send verification code automatically
    try {
      setState(() => _isLoading = true);

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/send-email-verification'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'userId': userId,
          'isDelviooMode': true,
        }),
      );

      if (mounted) setState(() => _isLoading = false);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          print('✅ Email verification code sent to: $email');
        }
      }
    } catch (e) {
      print('❌ Failed to send verification code: $e');
      if (mounted) setState(() => _isLoading = false);
    }

    if (!mounted) return;

    TradeRepublicBottomSheet.show(
      context: context,
      enableDrag: true,
      isDismissible: false, // User must verify email
      child: StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DragHandle(),
                // ── Sheet header: Icon left + Title ──
                Row(
                  children: [
                    TradeRepublicTap(
                      onTap: () async {
                        if (Navigator.canPop(context)) {
                          Navigator.of(context).pop();
                        }

                        await Future.delayed(
                          const Duration(milliseconds: 180),
                        );

                        if (mounted) {
                          _show2FABottomSheet(
                            userId,
                            isStaticCodeStep: true,
                          );
                        }
                      },
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          CupertinoIcons.back,
                          size: 18,
                          color: isLight ? Colors.black : Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      CupertinoIcons.mail_solid,
                      size: 22,
                      color: isLight ? Colors.black : Colors.white,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context)?.emailVerification ??
                            'Email Verification',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: isLight ? Colors.black : Colors.white,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                Text(
                  '${AppLocalizations.of(context)?.verificationCodeSent ?? "Verification code sent"}: $email',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.7,
                    ),
                  ),
                ),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                // Email Code Input
                TradeRepublicTextField(
                  controller: emailCodeController,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  textAlign: TextAlign.center,
                  hintText: '••••••••',
                ),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                // Verify Button
                SizedBox(
                  width: double.infinity,
                  child: TradeRepublicButton(
                    label:
                        AppLocalizations.of(context)?.verifyCode ??
                        'Verify & Continue',
                    backgroundColor: Colors.blue,
                    onPressed: isVerifying
                        ? null
                        : () async {
                            if (emailCodeController.text.length != 8) {
                              print('⚠️ Please enter the 8-digit code');
                              return;
                            }

                            setModalState(() => isVerifying = true);

                            try {
                              final response = await http.post(
                                Uri.parse(
                                  '${ApiConfig.baseUrl}/api/auth/verify-email-code',
                                ),
                                headers: {'Content-Type': 'application/json'},
                                body: json.encode({
                                  'email': email,
                                  'code': emailCodeController.text,
                                  'userId': userId,
                                  'isDelviooMode': true,
                                }),
                              );

                              if (response.statusCode == 200) {
                                final data = json.decode(response.body);
                                if (data['success'] == true) {
                                  print('✅ Email verified successfully!');

                                  // Close modal
                                  Navigator.of(context).pop();

                                  // Set user as logged in
                                  await userProvider.setIsLoggedIn(true);

                                  // Navigate to Delvioo main
                                  _navigateToHome(delvioo: true);
                                } else {
                                  setModalState(() => isVerifying = false);
                                  print('❌ Invalid code: ${data['message']}');
                                }
                              } else {
                                setModalState(() => isVerifying = false);
                                print('❌ Verification failed');
                              }
                            } catch (e) {
                              setModalState(() => isVerifying = false);
                              print('❌ Connection error: $e');
                            }
                          },
                  ),
                ),

                SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                // Resend Code Button
                TradeRepublicButton(
                  label:
                      AppLocalizations.of(context)?.resendEmail ??
                      'Resend Code',
                  isSecondary: true,
                  onPressed: isSendingCode
                      ? null
                      : () async {
                          setModalState(() => isSendingCode = true);

                          try {
                            final response = await http.post(
                              Uri.parse(
                                '${ApiConfig.baseUrl}/api/auth/send-email-verification',
                              ),
                              headers: {'Content-Type': 'application/json'},
                              body: json.encode({
                                'email': email,
                                'userId': userId,
                                'isDelviooMode': true,
                              }),
                            );

                            setModalState(() => isSendingCode = false);

                            if (response.statusCode == 200) {
                              TopNotification.success(
                                context,
                                AppLocalizations.of(context)?.codeResentSuccessfully ?? 'Code resent successfully!',
                              );
                            }
                          } catch (e) {
                            setModalState(() => isSendingCode = false);
                            print('❌ Error while sending: $e');
                          }
                        },
                ),

                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _sendEmailCodeForLogin2FA({
    required String email,
    required String userId,
  }) async {
    final response = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/api/auth/send-email-verification'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'email': email,
            'userId': userId,
            'isDelviooMode': _isDelviooMode,
          }),
        )
        .timeout(const Duration(seconds: 15));

    final data = json.decode(response.body);

    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(
        data['message'] ??
            AppLocalizations.of(context)?.failedToSendVerificationCode ??
            'Failed to send verification code',
      );
    }
  }

  // ✅ NEW: Separate modal for email code verification
  void _showEmailCodeModal(String userId, {String? loginEmail}) {
    final emailForVerification = (loginEmail != null &&
            loginEmail.trim().isNotEmpty)
        ? loginEmail.trim()
        : _emailController.text.trim();
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final isLight = appSettings.isLightMode(context);
    final emailCodeController = TextEditingController();
    final Map<String, bool> state = {
      'isVerifying': false,
      'isSendingCode': false,
      'hasSentInitialCode': false,
    }; // Use map to persist state

    TradeRepublicBottomSheet.show(
      context: context,
      enableDrag: true,
      isDismissible: false, // User must enter email code
      child: StatefulBuilder(
        builder: (context, setModalState) {
          if (state['hasSentInitialCode'] == false) {
            state['hasSentInitialCode'] = true;
            Future.microtask(() async {
              if (!mounted) return;
              setModalState(() => state['isSendingCode'] = true);
              try {
                await _sendEmailCodeForLogin2FA(
                  email: emailForVerification,
                  userId: userId,
                );
                if (mounted) {
                  TopNotification.success(
                    context,
                    AppLocalizations.of(context)?.verificationCodeSent ??
                        'Verification code sent to your email',
                  );
                }
              } catch (e) {
                if (mounted) {
                  TopNotification.error(
                    context,
                    e.toString().replaceAll('Exception: ', ''),
                  );
                }
              } finally {
                if (mounted) {
                  setModalState(() => state['isSendingCode'] = false);
                }
              }
            });
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                DragHandle(),
                // ── Sheet header: Icon left + Title ──
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.mail_solid,
                      size: 22,
                      color: isLight ? Colors.black : Colors.white,
                    ),
                    const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          AppLocalizations.of(context)?.emailVerification ??
                              'Email Verification',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: isLight ? Colors.black : Colors.white,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                // Subtitle
                Text(
                  AppLocalizations.of(context)?.enter8DigitCodeFromEmail ??
                      'Enter the 8-digit code from your email',
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.5,
                    ),
                  ),
                  textAlign: TextAlign.center,
                ),

                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                // Email Code Input
                TradeRepublicTextField.code(
                  controller: emailCodeController,
                  hintText: '12345678',
                  maxLength: 8,
                  onChanged: (value) {
                    if (value.length == 8) {
                      FocusScope.of(context).unfocus();
                    }
                  },
                ),

                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                // Verify Button
                TradeRepublicButton(
                  label:
                      AppLocalizations.of(context)?.verifyCode ?? 'Verify Code',
                  isLoading: state['isVerifying']!,
                  onPressed: state['isVerifying']!
                      ? null
                      : () async {
                          final code = emailCodeController.text.trim();
                          if (code.isEmpty || code.length != 8) {
                            TopNotification.error(
                              context,
                              AppLocalizations.of(
                                    context,
                                  )?.pleaseEnterThe8DigitCode ??
                                  'Please enter the 8-digit code',
                            );
                            return;
                          }

                          setModalState(() => state['isVerifying'] = true);

                          try {
                            print(
                              '📧 Verifying email 2FA code: $code for user: ${_emailController.text.trim()}',
                            );

                            // Verify 2FA code by calling login endpoint again with the code
                            final result = await ApiService.login(
                              email: _emailController.text.trim(),
                              password: _passwordController.text,
                              isDelviooMode: _isDelviooMode,
                              twoFACode: code, // Send the email code
                            );

                            if (result['success'] == true) {
                              print('✅ Email 2FA verified - Login successful!');

                              // Close email code modal
                              if (mounted && Navigator.canPop(context)) {
                                Navigator.of(context).pop();
                              }

                              // Save user data and token
                              final userProvider = Provider.of<AppSettings>(
                                context,
                                listen: false,
                              );
                              await userProvider.setIsLoggedIn(true);

                              if (result['user'] != null) {
                                await userProvider.setUserData(
                                  userId:
                                      result['user']['id']?.toString() ?? '',
                                  name: result['user']['name'] ?? '',
                                  email: result['user']['email'] ?? '',
                                  token: result['token'] ?? '',
                                  userType: _isDelviooMode
                                      ? 'Driver'
                                      : AppLocalizations.of(
                                              context,
                                            )?.businessLabel ??
                                            'Business', // ✅ Save the userType!
                                );

                                print('✅ Login successful - Token saved');
                                print(
                                  '✅ UserType saved: ${_isDelviooMode ? 'Driver' : 'Business'}',
                                );
                              }

                              if (mounted) {
                                // Navigate to appropriate home screen
                                _navigateToHome(delvioo: _isDelviooMode);
                              }
                            } else {
                              print(
                                '❌ Email 2FA verification failed: ${result['message']}',
                              );
                              TopNotification.error(
                                context,
                                result['message'] ??
                                    AppLocalizations.of(
                                      context,
                                    )?.verificationError ??
                                    'Verification failed',
                              );
                            }
                          } catch (e) {
                            print('❌ Email 2FA verification error: $e');
                            TopNotification.error(
                              context,
                              '${AppLocalizations.of(context)?.verificationError ?? "Verification error"}: ${e.toString()}',
                            );
                          } finally {
                            if (mounted) {
                              setModalState(() => state['isVerifying'] = false);
                            }
                          }
                        },
                ),

                SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                // Resend Email Button
                TradeRepublicButton(
                  label: state['isSendingCode'] == true
                      ? AppLocalizations.of(context)?.sendingCode ??
                            'Sending code...'
                      : AppLocalizations.of(context)?.resendEmail ??
                            'Resend Email',
                  isSecondary: true,
                  onPressed: state['isSendingCode'] == true
                      ? null
                      : () async {
                          setModalState(() => state['isSendingCode'] = true);

                          try {
                            await _sendEmailCodeForLogin2FA(
                              email: emailForVerification,
                              userId: userId,
                            );
                            if (mounted) {
                              TopNotification.success(
                                context,
                                AppLocalizations.of(context)
                                        ?.verificationCodeSent ??
                                    'Verification code sent to your email',
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              TopNotification.error(
                                context,
                                e.toString().replaceAll('Exception: ', ''),
                              );
                            }
                          } finally {
                            if (mounted) {
                              setModalState(
                                () => state['isSendingCode'] = false,
                              );
                            }
                          }
                        },
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
          );
        },
      ),
    );
}

  // 🔑 NEW: Forgot Password Modal
  void _showForgotPasswordModal() {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final isLight = appSettings.isLightMode(context);
    final emailController = TextEditingController();
    bool isSending = false;

    TradeRepublicBottomSheet.show(
      context: context,
      enableDrag: true,
      isDismissible: true,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DragHandle(),
                  // ── Sheet header: Icon left + Title ──
                  Row(
                    children: [
                      Icon(
                        CupertinoIcons.lock_rotation,
                        size: 22,
                        color: isLight ? Colors.black : Colors.white,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        AppLocalizations.of(context)?.forgotPassword ??
                            'Forgot Password?',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: isLight ? Colors.black : Colors.white,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                  // Subtitle
                  Text(
                    AppLocalizations.of(context)?.enterEmailToResetPassword ??
                        'Enter your email address and we\'ll send you a code to reset your password',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      color: (isLight ? Colors.black : Colors.white).withOpacity(
                        0.7,
                      ),
                    ),
                  ),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                  // Email Input
                  TradeRepublicTextField(
                    controller: emailController,
                    hintText:
                        AppLocalizations.of(context)?.yourEmailCom ??
                        'your@email.com',
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: const Icon(Icons.email),
                  ),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                  // Send Button
                  TradeRepublicButton(
                    label: isSending
                        ? AppLocalizations.of(context)?.sending ?? 'Sending...'
                        : AppLocalizations.of(context)?.sendResetLink ??
                              'Send Reset Code',
                    onPressed: isSending
                        ? null
                        : () async {
                            final email = emailController.text.trim();
                            if (email.isEmpty ||
                                !email.contains('@') ||
                                !email.contains('.')) {
                              TopNotification.error(
                                context,
                                AppLocalizations.of(
                                      context,
                                    )?.pleaseEnterYourEmail ??
                                    'Please enter a valid email address',
                              );
                              return;
                            }

                          setModalState(() => isSending = true);

                          try {
                            final response = await http.post(
                              Uri.parse(
                                '${ApiConfig.baseUrl}/api/auth/forgot-password',
                              ),
                              headers: {'Content-Type': 'application/json'},
                              body: json.encode({
                                'email': email,
                                'isDelviooMode': _isDelviooMode,
                              }),
                            );

                            if (mounted) {
                              setModalState(() => isSending = false);

                              if (response.statusCode == 200) {
                                Navigator.of(context).pop();
                                // Wait for modal to close before showing next one
                                await Future.delayed(
                                  const Duration(milliseconds: 300),
                                );
                                if (mounted) {
                                  _showVerifyCodeModal(email);
                                }
                              } else {
                                TopNotification.error(
                                  context,
                                  AppLocalizations.of(
                                        context,
                                      )?.failedToSendResetCode ??
                                      'Failed to send reset code. Please try again.',
                                );
                              }
                            }
                          } catch (e) {
                            if (mounted) {
                              setModalState(() => isSending = false);
                              TopNotification.error(
                                context,
                                '${AppLocalizations.of(context)?.errorPrefix ?? "Error"}: ${e.toString()}',
                              );
                            }
                          }
                          },
                  ),

                  SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                  // Cancel Button
                  TradeRepublicButton(
                    label: AppLocalizations.of(context)?.cancel ?? 'Cancel',
                    isSecondary: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // 🔑 STEP 2: Verify Code Modal
  void _showVerifyCodeModal(String email) {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final isLight = appSettings.isLightMode(context);
    final codeController = TextEditingController();
    bool isVerifying = false;

    TradeRepublicBottomSheet.show(
      context: context,
      enableDrag: true,
      isDismissible: false,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DragHandle(),
                  // ── Sheet header: Icon left + Title ──
                  Row(
                    children: [
                      Icon(
                        CupertinoIcons.checkmark_shield_fill,
                        size: 22,
                        color: isLight ? Colors.black : Colors.white,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        AppLocalizations.of(context)?.verifyCode ?? 'Verify Code',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: isLight ? Colors.black : Colors.white,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                  // Subtitle
                  Text(
                    '${AppLocalizations.of(context)?.enter8DigitCodeSentTo ?? "Enter the 8-digit code sent to"} $email',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.6),
                    ),
                  ),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                  // Code Input
                  TradeRepublicTextField.code(
                    controller: codeController,
                    hintText: '12345678',
                    maxLength: 8,
                  ),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                  // Verify Button
                  TradeRepublicButton(
                    label:
                        AppLocalizations.of(context)?.verifyCode ??
                        'Verify Code',
                    isLoading: isVerifying,
                    onPressed: isVerifying
                        ? null
                        : () async {
                            final code = codeController.text.trim();

                            if (code.isEmpty || code.length != 8) {
                              TopNotification.error(
                                context,
                                AppLocalizations.of(
                                      context,
                                    )?.pleaseEnterThe8DigitCode ??
                                    'Please enter the 8-digit code',
                              );
                              return;
                            }

                            setModalState(() => isVerifying = true);

                            try {
                              // Verify code with backend
                              final response = await http.post(
                                Uri.parse(
                                  '${ApiConfig.baseUrl}/api/auth/verify-reset-code',
                                ),
                                headers: {'Content-Type': 'application/json'},
                                body: json.encode({
                                  'email': email,
                                  'code': code,
                                  'isDelviooMode': _isDelviooMode,
                                }),
                              );

                              if (mounted) {
                                setModalState(() => isVerifying = false);

                                if (response.statusCode == 200) {
                                  final data = json.decode(response.body);
                                  if (data['success'] == true) {
                                    // Close code modal
                                    Navigator.of(context).pop();
                                    // Wait before opening password modal
                                    await Future.delayed(
                                      const Duration(milliseconds: 300),
                                    );
                                    if (mounted) {
                                      // Open password modal
                                      _showNewPasswordModal(email, code);
                                    }
                                  } else {
                                    TopNotification.error(
                                      context,
                                      data['message'] ??
                                          AppLocalizations.of(
                                            context,
                                          )?.invalidOrExpiredCode ??
                                          'Invalid or expired code',
                                    );
                                  }
                                } else {
                                  TopNotification.error(
                                    context,
                                    AppLocalizations.of(
                                          context,
                                        )?.invalidOrExpiredCode ??
                                        'Invalid or expired code',
                                  );
                                }
                              }
                            } catch (e) {
                              if (mounted) {
                                setModalState(() => isVerifying = false);
                                TopNotification.error(
                                  context,
                                  '${AppLocalizations.of(context)?.errorPrefix ?? "Error"}: ${e.toString()}',
                                );
                              }
                            }
                          },
                  ),

                  SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                  // Cancel Button
                  TradeRepublicButton(
                    label: AppLocalizations.of(context)?.cancel ?? 'Cancel',
                    isSecondary: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // 🔑 STEP 3: New Password Modal (after code verification)
  void _showNewPasswordModal(String email, String code) {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final isLight = appSettings.isLightMode(context);
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool obscurePassword = true;
    bool obscureConfirmPassword = true;
    bool isResetting = false;

    TradeRepublicBottomSheet.show(
      context: context,
      enableDrag: true,
      isDismissible: false,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DragHandle(),
                  // ── Sheet header: Icon left + Title ──
                  Row(
                    children: [
                      Icon(
                        CupertinoIcons.lock_rotation,
                        size: 22,
                        color: isLight ? Colors.black : Colors.white,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        AppLocalizations.of(context)?.newPassword ?? 'New Password',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: isLight ? Colors.black : Colors.white,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                  // Subtitle
                  Text(
                    AppLocalizations.of(context)?.enterYourNewPassword ??
                        'Enter your new password',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.7),
                    ),
                  ),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                  // New Password Input
                  TradeRepublicTextField.password(
                    controller: passwordController,
                    hintText:
                        AppLocalizations.of(context)?.newPassword ??
                        'New Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                  // Confirm Password Input
                  TradeRepublicTextField.password(
                    controller: confirmPasswordController,
                    hintText:
                        AppLocalizations.of(context)?.confirmNewPassword ??
                        'Confirm New Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                  // Reset Button
                  TradeRepublicButton(
                    label:
                        AppLocalizations.of(context)?.resetPassword ??
                        'Reset Password',
                    isLoading: isResetting,
                    onPressed: isResetting
                        ? null
                        : () async {
                            final password = passwordController.text;
                            final confirmPassword =
                                confirmPasswordController.text;

                            if (password.isEmpty || password.length < 8) {
                              TopNotification.error(
                                context,
                                AppLocalizations.of(
                                      context,
                                    )?.passwordMustBeAtLeast8Chars ??
                                    AppLocalizations.of(
                                      context,
                                    )?.passwordAtLeast8Characters ??
                                    'Password must be at least 8 characters',
                              );
                              return;
                            }

                            if (password != confirmPassword) {
                              TopNotification.error(
                                context,
                                AppLocalizations.of(
                                      context,
                                    )?.passwordsDoNotMatch ??
                                    'Passwords do not match',
                              );
                              return;
                            }

                            setModalState(() => isResetting = true);

                            try {
                              final response = await http.post(
                                Uri.parse(
                                  '${ApiConfig.baseUrl}/api/auth/reset-password',
                                ),
                                headers: {'Content-Type': 'application/json'},
                                body: json.encode({
                                  'email': email,
                                  'code': code,
                                  'newPassword': password,
                                  'isDelviooMode': _isDelviooMode,
                                }),
                              );

                              if (mounted) {
                                setModalState(() => isResetting = false);

                                if (response.statusCode == 200) {
                                  final data = json.decode(response.body);
                                  if (data['success'] == true) {
                                    Navigator.of(context).pop();
                                    TopNotification.success(
                                      context,
                                      AppLocalizations.of(
                                            context,
                                          )?.passwordResetSuccessful ??
                                          'Password reset successful! Please login with your new password.',
                                    );
                                  } else {
                                    TopNotification.error(
                                      context,
                                      data['message'] ??
                                          AppLocalizations.of(
                                            context,
                                          )?.failedToResetPassword ??
                                          'Failed to reset password',
                                    );
                                  }
                                } else {
                                  TopNotification.error(
                                    context,
                                    AppLocalizations.of(
                                          context,
                                        )?.failedToResetPassword ??
                                        'Failed to reset password',
                                  );
                                }
                              }
                            } catch (e) {
                              if (mounted) {
                                setModalState(() => isResetting = false);
                                TopNotification.error(
                                  context,
                                  '${AppLocalizations.of(context)?.errorPrefix ?? "Error"}: ${e.toString()}',
                                );
                              }
                            }
                          },
                  ),

                  SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                  // Cancel Button
                  TradeRepublicButton(
                    label: AppLocalizations.of(context)?.cancel ?? 'Cancel',
                    isSecondary: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
