import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:window_manager/window_manager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'app_router.dart';
import 'auth/pages/login_page.dart';
import 'auth/pages/auto_login_page.dart';
import 'shared/services/app_settings.dart';
import 'shared/services/app_localizations.dart';
import 'splash_screen.dart';
import 'onboarding_page.dart';
import 'auth/pages/register_page.dart';
import 'modules/delvioo/pages/delvioo_main_page.dart';
import 'shared/services/push_notification_service.dart';
import 'config/api_config.dart';
import 'auth/pages/driver_registration/driver_registration_main.dart';
import 'shared/widgets/cultioo_spinner.dart';
import 'shared/widgets/keyboard_toolbar.dart';
import 'shared/services/driver_location_service.dart';

/// Custom ScrollBehavior that enables mouse-drag scrolling on desktop.
class DesktopScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details) {
    // Disable automatic desktop scrollbars. Several screens already provide
    // explicit Scrollbar widgets with dedicated controllers.
    return child;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure minimum window size for desktop platforms
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await windowManager.ensureInitialized();
    
    const minimumSize = Size(1400, 900);
    const defaultSize = Size(1400, 900);
    
    WindowOptions windowOptions = const WindowOptions(
      size: defaultSize,
      minimumSize: minimumSize,
      center: true,
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.hidden);
    
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // Initialize Network Connectivity (critical for external devices)
  await ApiConfig.initializeNetworking();

  // Initialise driver background location service (Android foreground service + iOS)
  await initDriverLocationService();

  // Initialize Firebase and Push Notifications
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform);
    print('[SUCCESS] Firebase initialized successfully');

    // Register background message handler BEFORE any other Firebase calls
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Initialize Push Notifications
    await PushNotificationService.initialize();
    print('[SUCCESS] Push Notification Service initialized');
  } catch (e) {
    print('[ERROR] Firebase initialization failed: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final AppSettings _appSettings = AppSettings();
  bool _isLoading = true;
  Widget? _initialRoute; // ✅ Store initial route to prevent re-evaluation

  @override
  void initState() {
    super.initState();
    // ✅ DON'T add listener until after initial load completes
    _loadUserData();
  }

  void _loadUserData() async {
    await _appSettings.loadUserData();

    // ✅ If a token is present the user has already completed onboarding.
    // Ensure the flag is stored so the condition can never flip back to true.
    if (_appSettings.authToken != null && _appSettings.authToken!.isNotEmpty) {
      if (!_appSettings.onboardingCompleted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('onboarding_completed', true);
        print('[DEBUG] onboarding_completed back-filled (token exists)');
      }
    }

    // Preload splash logos to avoid grey placeholder while assets resolve
    try {
      await precacheImage(
        const AssetImage('assets/images/cultioo_logo_light.png'),
        context);
      await precacheImage(
        const AssetImage('assets/images/cultioo_logo_dark.png'),
        context);
      print('🖼️ Splash logos pre-cached');
    } catch (e) {
      print('[WARNING] Failed to precache logos: $e');
    }

    // ✅ Set initial route ONCE when app starts
    _initialRoute = _getInitialRoute();

    // ✅ Add listener AFTER initial data is loaded to prevent build-time conflicts
    if (mounted) {
      _appSettings.addListener(_onSettingsChanged);
    }

    // ✅ Use post-frame callback to avoid setState during build
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          print(
            '[SUCCESS] User data loaded - Token available: ${_appSettings.authToken != null}');
        }
      });
    }
  }

  @override
  void dispose() {
    _appSettings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    // ✅ Only rebuild for theme changes, NOT for route changes
    // ✅ Use post-frame callback to avoid rebuilding during build
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  Widget _getInitialRoute() {
    // ✅ Token check comes FIRST — a stored token means the user already completed
    // onboarding and logged in before. Never show onboarding when a token is present.
    if (_appSettings.authToken != null &&
        _appSettings.authToken!.isNotEmpty) {
      print('[DEBUG] App Start: Token found, showing AutoLoginPage');
      return const AutoLoginPage();
    }

    // Show onboarding only if it's not completed AND no stored accounts exist
    if (!_appSettings.onboardingCompleted &&
        _appSettings.storedAccounts.isEmpty) {
      print('🔍 App Start: Showing Onboarding');
      return const SplashScreen();
    }

    // No active session - go to login page
    print('[DEBUG] App Start: No token, showing LoginPage');
    return const LoginPage();
  }

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    // Show modern loading screen while user data is being loaded
    if (_isLoading || _initialRoute == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        builder: (context, child) =>
            KeyboardToolbar(child: child ?? SizedBox()),
        home: Builder(
          builder: (context) {
            final isDark =
                MediaQuery.of(context).platformBrightness == Brightness.dark;
            // Dark mode = light.png (white logo), Light mode = dark.png (black logo)
            final assetPath = isDark
                ? 'assets/images/cultioo_logo_light.png'
                : 'assets/images/cultioo_logo_dark.png';

            return Scaffold(
              backgroundColor: isDark ? Colors.black : Colors.white,
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 🖼️ Cultioo Logo
                    Image.asset(
                      assetPath,
                      width: 220,
                      height: 124,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          Icons.eco_rounded,
                          size: 60,
                          color: const Color(0xFF34C759));
                      }),
                    SizedBox(height: 48),
                    // Modern minimal loading indicator
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CultiooLoadingIndicator(size: 20)),
                  ])));
          }));
    }

    return ChangeNotifierProvider<AppSettings>(
      create: (context) => _appSettings,
      child: MediaQuery(
        // Apply global text scale factor from AppSettings so changes in App Settings
        // (Small/Medium/Large) affect the whole app consistently.
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(_appSettings.getTextSizeMultiplier())),
        child: MaterialApp(
          title: AppLocalizations.of(context)?.cultiooBusiness ?? 'Cultioo Business',
          debugShowCheckedModeBanner: false,
          scrollBehavior: DesktopScrollBehavior(),
          builder: (context, child) =>
              KeyboardToolbar(child: child ?? SizedBox()),
          // Locale from AppSettings
          locale: _appSettings.appLocale,
          supportedLocales: AppLocales.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          themeMode: _appSettings.themeMode,
          theme: ThemeData(
            colorScheme:
                ColorScheme.fromSeed(
                  seedColor: Colors.white,
                  brightness: Brightness.light).copyWith(
                  primary: Colors.black,
                  secondary: Colors.black.withOpacity(0.7)),
            textSelectionTheme: TextSelectionThemeData(
              cursorColor: Colors.black,
              selectionColor: Colors.black.withOpacity(0.15),
              selectionHandleColor: Colors.black),
            // Konsistente Switch-Farben im Light Mode
            switchTheme: SwitchThemeData(
              thumbColor: WidgetStateProperty.resolveWith<Color>((
                Set<WidgetState> states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white; // White thumb when active
                }
                return Colors.black.withOpacity(
                  0.4); // Lighter gray thumb when inactive
              }),
              trackColor: WidgetStateProperty.resolveWith<Color>((
                Set<WidgetState> states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.black;
                }
                return Colors.black.withOpacity(
                  0.15); // Heller Track wenn inaktiv
              }),
              trackOutlineColor: WidgetStateProperty.resolveWith<Color>((
                Set<WidgetState> states) {
                return Colors.transparent; // Kein Rand im Light Mode
              })),
            fontFamily: 'Poppins',
            useMaterial3: true),
          darkTheme: ThemeData(
            colorScheme:
                ColorScheme.fromSeed(
                  seedColor: Colors.black,
                  brightness: Brightness.dark).copyWith(
                  primary: Colors.white,
                  secondary: Colors.white.withOpacity(0.15)),
            textSelectionTheme: TextSelectionThemeData(
              cursorColor: Colors.white,
              selectionColor: Colors.white.withOpacity(0.5),
              selectionHandleColor: Colors.white),
            // Fix for red switches in Dark Mode on Android
            switchTheme: SwitchThemeData(
              thumbColor: WidgetStateProperty.resolveWith<Color>((
                Set<WidgetState> states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white; // White thumb when active
                }
                return Colors.white.withOpacity(
                  0.4); // Lighter thumb when inactive
              }),
              trackColor: WidgetStateProperty.resolveWith<Color>((
                Set<WidgetState> states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                return Colors.transparent; // Transparent track when inactive
              }),
              trackOutlineColor: WidgetStateProperty.resolveWith<Color>((
                Set<WidgetState> states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.transparent; // Kein Rand wenn aktiv
                }
                return Colors.white.withOpacity(
                  0.5); // White border when inactive
              })),
            fontFamily: 'Poppins',
            useMaterial3: true),
          home:
              _initialRoute, // ✅ Use stored initial route instead of calling method again
          onGenerateRoute: (settings) {
            Widget page;
            switch (settings.name) {
              case '/onboarding':
                page = const OnboardingPage();
                break;
              case '/login':
                page = const LoginPage();
                break;
              case '/auto-login':
                page = const AutoLoginPage();
                break;
              case '/register':
                page = const RegisterPage();
                break;
              case '/main':
                page = const AppRouter();
                break;
              case '/delvioo-main':
                page = const DelviooMainPage();
                break;
              case '/driver-registration':
                page = DriverRegistrationMain();
                break;
              default:
                return null;
            }
            return CupertinoPageRoute(
              settings: settings,
              builder: (_) => page);
          })));
  }
}
