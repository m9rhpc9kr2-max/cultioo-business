import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'shared/services/app_settings.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _glowController;
  late AnimationController _splitController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;
  late Animation<double> _slideAnimation;
  late Animation<double> _splitAnimation;
  late Animation<double> _logoFadeOut;
  late Animation<Offset> _leftSlideAnimation;
  late Animation<Offset> _rightSlideAnimation;

  @override
  void initState() {
    super.initState();

    // Main animation controller
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this);

    // Glow effect controller
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this);

    // Split animation controller
    _splitController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this);

    // Fade in animation
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeInOut)));

    // Scale animation with bounce
    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut)));

    // Slide animation for text
    _slideAnimation = Tween<double>(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.4, 0.8, curve: Curves.easeOut)));

    // Glow pulse animation
    _glowAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut));

    // Split animation - logo fades out
    _logoFadeOut = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _splitController,
        curve: const Interval(0.0, 0.3, curve: Curves.easeInOut)));

    // Left slide animation - slides to left
    _leftSlideAnimation =
        Tween<Offset>(begin: Offset.zero, end: const Offset(-1.5, 0)).animate(
          CurvedAnimation(
            parent: _splitController,
            curve: const Interval(0.0, 0.6, curve: Curves.easeInCubic)));

    // Right slide animation - slides to right
    _rightSlideAnimation =
        Tween<Offset>(begin: Offset.zero, end: const Offset(1.5, 0)).animate(
          CurvedAnimation(
            parent: _splitController,
            curve: const Interval(0.0, 0.6, curve: Curves.easeInCubic)));

    // Start animations
    _animationController.forward();

    // Start glow pulse
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        _glowController.repeat(reverse: true);
      }
    });

    // Start split animation after initial animation
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) {
        _splitController.forward();
      }
    });

    // Haptic feedback
    Future.delayed(const Duration(milliseconds: 400), () {
      HapticFeedback.lightImpact();
    });

    // Haptic for split
    Future.delayed(const Duration(milliseconds: 1800), () {
      HapticFeedback.mediumImpact();
    });

    // Navigate after splash
    Future.delayed(const Duration(milliseconds: 3200), () {
      if (mounted) {
        HapticFeedback.mediumImpact();
        Navigator.of(context).pushReplacementNamed('/onboarding');
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _glowController.dispose();
    _splitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings appSettings = AppSettings();
    final isLight = appSettings.isLightMode(context);

    return Scaffold(
      backgroundColor: isLight ? Colors.white : Colors.black,
      body: Stack(
        children: [
          // Center animated logo
          Center(
            child: AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return FadeTransition(
                  opacity: _fadeAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: AnimatedBuilder(
                      animation: _splitController,
                      builder: (context, child) {
                        return FadeTransition(
                          opacity: _logoFadeOut,
                          child: Image.asset(
                            isLight
                                ? 'assets/images/cultioo_logo_dark.png'
                                : 'assets/images/cultioo_logo_light.png',
                            width: 220,
                            height: 124,
                            fit: BoxFit.contain));
                      })));
              })),
        ]));
  }
}
